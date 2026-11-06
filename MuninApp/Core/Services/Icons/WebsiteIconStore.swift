import Foundation
import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// An actor that fetches website icons directly from each site and caches them in memory.
///
/// Candidates are tried in order: `<link rel="apple-touch-icon">` in the
/// page's HTML, `<link rel="icon">`, `/apple-touch-icon.png`, and
/// `/favicon.ico`.
///
/// Nothing is written to disk. Requests use an ephemeral session without a
/// URL cache or cookies, and results stay in memory until ``clear()``.
actor WebsiteIconStore {
    /// The shared icon store.
    static let shared = WebsiteIconStore()

    /// A URL session without a URL cache or cookie storage.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    /// Image data keyed by host; `nil` for hosts known to have no icon.
    private var icons: [String: Data?] = [:]
    /// In-flight fetches keyed by host, so concurrent callers share one request.
    private var inFlight: [String: Task<Data?, Never>] = [:]
    /// Each icon's dominant color keyed by host; `nil` when there's no icon.
    private var colors: [String: Color?] = [:]
}

extension WebsiteIconStore {
    /// Returns the icon for a URL, with or without a scheme.
    ///
    /// - Parameter urlString: A URL such as `example.com` or `https://example.com/login`.
    /// - Returns: The icon's image data, or `nil` if none was found.
    func icon(for urlString: String) async -> Data? {
        guard let host = Self.host(from: urlString) else { return nil }
        if let cached = icons[host] { return cached }
        if let task = inFlight[host] { return await task.value }

        let task = Task { await fetchIcon(host: host) }
        inFlight[host] = task
        let data = await task.value
        inFlight[host] = nil
        icons[host] = .some(data)
        return data
    }

    /// Returns the dominant color of a URL's icon, used for tinting.
    func dominantColor(for urlString: String) async -> Color? {
        guard let host = Self.host(from: urlString) else { return nil }
        if let cached = colors[host] { return cached }
        let color = await icon(for: urlString).flatMap(Self.dominantColor(in:))
        colors[host] = .some(color)
        return color
    }

    /// Cancels in-flight fetches and removes all cached icons and colors.
    func clear() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        icons = [:]
        colors = [:]
    }

    /// Returns icon URLs from an HTML document's `<link>` tags, apple-touch-icon first.
    static func iconLinks(in html: String, baseURL: URL) -> [URL] {
        guard let linkTag = try? Regex(#"<link\b[^>]*>"#).ignoresCase() else { return [] }
        var touchIcons: [URL] = []
        var icons: [URL] = []
        for match in html.matches(of: linkTag) {
            let tag = String(html[match.range])
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  let href = attribute("href", in: tag),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
            if rel.contains("apple-touch-icon") {
                touchIcons.append(url)
            } else if rel.split(separator: " ").contains("icon") {
                icons.append(url)
            }
        }
        return touchIcons + icons
    }

    /// Returns the lowercased host of a URL with or without a scheme, used as the cache key.
    static func host(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)?.host()?.lowercased()
    }
}

private extension WebsiteIconStore {
    /// Computes an icon's dominant color.
    ///
    /// Averages the icon's pixels at 24×24, weighting each by opacity and
    /// saturation so transparent, white, gray, and black areas barely count.
    ///
    /// - Returns: The dominant color, or `nil` for a grayscale icon.
    static func dominantColor(in data: Data) -> Color? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.1 else { continue }
            // Undo premultiplied alpha.
            let r = Double(pixels[index]) / 255 / alpha
            let g = Double(pixels[index + 1]) / 255 / alpha
            let b = Double(pixels[index + 2]) / 255 / alpha
            let maximum = max(r, g, b), minimum = min(r, g, b)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
            let weight = alpha * saturation * saturation
            red += r * weight; green += g * weight; blue += b * weight; total += weight
        }
        guard total > 0.5 else { return nil }
        return Color(.sRGB, red: red / total, green: green / total, blue: blue / total)
    }

    // MARK: - Fetching

    /// Tries each icon candidate for a host in order and returns the first image found.
    func fetchIcon(host: String) async -> Data? {
        guard let page = URL(string: "https://\(host)/") else { return nil }

        var candidates: [URL] = []
        if let (html, finalURL) = await fetchHTML(page) {
            candidates += Self.iconLinks(in: html, baseURL: finalURL)
        }
        candidates += ["/apple-touch-icon.png", "/favicon.ico"].compactMap { URL(string: $0, relativeTo: page) }

        for url in candidates {
            if Task.isCancelled { return nil }
            if let data = await fetchImage(url) { return data }
        }
        return nil
    }

    /// Fetches the first 256 KB of a page's HTML and its final URL after
    /// redirects, used to resolve relative icon links.
    func fetchHTML(_ url: URL) async -> (String, URL)? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        // Icon links live in <head>, near the top of the document.
        let head = data.prefix(256 * 1024)
        let html = String(decoding: head, as: UTF8.self)
        return (html, http.url ?? url)
    }

    /// Fetches a URL and returns its data if it's a decodable image under 2 MB.
    func fetchImage(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty, data.count < 2 * 1024 * 1024,
              PlatformImage(data: data) != nil else { return nil }
        return data
    }

    // MARK: - Parsing

    /// Returns the value of a named attribute in an HTML tag, quoted or unquoted.
    static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? Regex(#"\b\#(name)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#).ignoresCase(),
              let match = tag.firstMatch(of: regex) else { return nil }
        for index in 1...3 {
            if let range = match.output[index].range { return String(tag[range]) }
        }
        return nil
    }
}
