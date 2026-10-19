import Foundation
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
    static let shared = WebsiteIconStore()

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
    private var inFlight: [String: Task<Data?, Never>] = [:]

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

    /// Called on lock and sign out.
    func clear() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        icons = [:]
    }

    // MARK: - Fetching

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

    private func fetchHTML(_ url: URL) async -> (String, URL)? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        // The <head> is near the top; no need to look at the whole page.
        let head = data.prefix(256 * 1024)
        let html = String(decoding: head, as: UTF8.self)
        return (html, http.url ?? url)
    }

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

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? Regex(#"\b\#(name)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#).ignoresCase(),
              let match = tag.firstMatch(of: regex) else { return nil }
        for index in 1...3 {
            if let range = match.output[index].range { return String(tag[range]) }
        }
        return nil
    }

    static func host(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)?.host()?.lowercased()
    }
}
