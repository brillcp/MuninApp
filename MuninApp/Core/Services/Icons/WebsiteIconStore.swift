import Foundation
import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Fetches a website's icon straight from the site, memory only.
///
/// Order: `<link rel="apple-touch-icon">` in the page's HTML (the home screen
/// icon), then `<link rel="icon">`, then `/apple-touch-icon.png`, then
/// `/favicon.ico`.
///
/// Nothing touches disk: an ephemeral session with no URL cache or cookies,
/// and results live in this actor until the vault locks (`clear()`).
actor WebsiteIconStore {
    /// The app-wide store.
    static let shared = WebsiteIconStore()

    /// A session that stores nothing: no URL cache, no cookies.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    /// Image data per host; `nil` once a host is known to have no icon.
    private var icons: [String: Data?] = [:]
    /// Fetches in progress per host, so concurrent callers share one fetch.
    private var inFlight: [String: Task<Data?, Never>] = [:]
    /// The icon's dominant colour per host; `nil` when there's no icon.
    private var colors: [String: Color?] = [:]

    /// The icon for the item's URL ("kattmat.com" or "https://kattmat.com/login").
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

    /// The dominant colour of the item's icon, for tinting its detail view.
    func dominantColor(for urlString: String) async -> Color? {
        guard let host = Self.host(from: urlString) else { return nil }
        if let cached = colors[host] { return cached }
        let color = await icon(for: urlString).flatMap(Self.dominantColor(in:))
        colors[host] = .some(color)
        return color
    }

    /// Cancels fetches and drops every cached icon and colour. Called on lock and sign out.
    func clear() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        icons = [:]
        colors = [:]
    }

    /// Averages the icon's pixels at 24×24, weighting each by its opacity and
    /// saturation, so transparent, white, grey and black areas barely count
    /// and the brand colour wins. Nil for an all-grey icon.
    private static func dominantColor(in data: Data) -> Color? {
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
            // Un-premultiply.
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

    /// Tries each icon candidate for `host` in order and returns the first image found.
    private func fetchIcon(host: String) async -> Data? {
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

    /// Fetches a page's HTML (its first 256 KB) and the URL it ended up at
    /// after redirects, for resolving relative icon links.
    private func fetchHTML(_ url: URL) async -> (String, URL)? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        // The <head> is near the top; no need to look at the whole page.
        let head = data.prefix(256 * 1024)
        let html = String(decoding: head, as: UTF8.self)
        return (html, http.url ?? url)
    }

    /// Fetches `url` and returns its data if it's a decodable image under 2 MB.
    private func fetchImage(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty, data.count < 2 * 1024 * 1024,
              PlatformImage(data: data) != nil else { return nil }
        return data
    }

    // MARK: - Parsing

    /// Icon URLs from `<link>` tags, apple-touch-icon first.
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

    /// The value of the attribute `name` in an HTML tag, quoted or not.
    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? Regex(#"\b\#(name)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#).ignoresCase(),
              let match = tag.firstMatch(of: regex) else { return nil }
        for index in 1...3 {
            if let range = match.output[index].range { return String(tag[range]) }
        }
        return nil
    }

    /// The lowercased host of a URL typed with or without a scheme, used as the cache key.
    static func host(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)?.host()?.lowercased()
    }
}
