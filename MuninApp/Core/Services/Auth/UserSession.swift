import Foundation

/// The signed-in user, as the vault and its models need it.
///
/// ``AuthManager`` is the live implementation. Models receive it in their
/// initializer, so tests can pass a fake.
protocol UserSession: AnyObject {
    /// A Boolean value that indicates whether a session exists.
    var isSignedIn: Bool { get }
    /// The signed-in user's ID, which scopes their data on the server.
    var userID: String? { get }
    /// Signs out, for example after the server rejects the session.
    func signOut()
}
