import Foundation
import Networking
import Observation

/// An object that checks the App Store for a newer version of the app and
/// asks the user to update.
///
/// The check runs once at launch. Update Now opens the App Store page, Don't
/// Ask for a While hides the alert for two to four days, and Later asks again
/// at the next launch.
@Observable
final class AppUpdateChecker {
    /// The user defaults key for the date until which the alert is hidden.
    private static let snoozedUntilKey = "munin.update.snoozedUntil"
    /// The base URL of the iTunes Search API.
    private static let baseURL = URL(string: "https://itunes.apple.com")!

    /// The service that sends the lookup to the App Store.
    private let service: Network.Service
    /// The user defaults the snooze date is stored in.
    private let defaults: UserDefaults

    /// The App Store page of the newer version, or `nil` if there's none.
    private(set) var storeURL: URL?
    /// A Boolean value that indicates whether the update alert is presented.
    var isAlertPresented = false

    /// Creates an update checker.
    ///
    /// - Parameter defaults: The user defaults the snooze date is stored in.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let server = ServerConfig(baseURL: Self.baseURL)
        service = Network.Service(server: server, logger: nil)
    }
}

// MARK: - Actions
extension AppUpdateChecker {
    /// Looks up the App Store version, and presents the alert if it's newer
    /// than the running app and the alert isn't hidden.
    ///
    /// Fails silently, for example when offline.
    func check() async {
        guard !isSnoozed,
              let bundleID = Bundle.main.bundleIdentifier,
              let lookup: AppStoreLookup = try? await service.request(AppStoreLookupRequest(bundleID: bundleID)),
              let app = lookup.results.first,
              app.version.compare(currentVersion, options: .numeric) == .orderedDescending else { return }
        storeURL = Self.storeURL(for: app.trackViewUrl)
        isAlertPresented = true
    }

    /// Hides the alert for two to four days.
    func snooze() {
        let date = Calendar.current.date(byAdding: .day, value: .random(in: 2...4), to: .now)
        defaults.set(date, forKey: Self.snoozedUntilKey)
    }

    /// Clears any snooze, so the alert appears again at the next launch.
    func remindLater() {
        defaults.removeObject(forKey: Self.snoozedUntilKey)
    }
}

private extension AppUpdateChecker {
    /// A Boolean value that indicates whether the alert is hidden for now.
    var isSnoozed: Bool {
        guard let date = defaults.object(forKey: Self.snoozedUntilKey) as? Date else { return false }
        return date > .now
    }

    /// The running app's version, such as `1.1`.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Returns the URL that opens an App Store page in the App Store app.
    ///
    /// On macOS, the `macappstore` scheme opens the Mac App Store instead of
    /// the browser.
    static func storeURL(for url: URL) -> URL {
        #if os(macOS)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "macappstore"
        return components?.url ?? url
        #else
        url
        #endif
    }
}
