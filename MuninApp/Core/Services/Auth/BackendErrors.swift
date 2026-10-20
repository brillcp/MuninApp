import Foundation
import Networking

/// The one place that decides what a backend or auth error means.
extension Error {
    /// The Supabase session can't be reused: the token is missing, or the auth
    /// server rejected a refresh outright. The user needs to sign in again.
    var invalidatesSupabaseSession: Bool {
        if self is TokenProvidableError { return true }
        guard let status = httpStatus else { return false }
        switch status {
        case .badRequest, .unauthorized, .forbidden, .unprocessableEntity: return true
        default: return false
        }
    }

    /// Munin refused the token (expired or invalid), so the user has to sign in again.
    var isMuninAuthRejection: Bool {
        self is TokenProvidableError || httpStatus == .unauthorized
    }

    /// The HTTP status of a server response error, or nil for any other error.
    var httpStatus: HTTP.StatusCode? {
        guard let networkError = self as? Network.Service.NetworkError,
              case .badServerResponse(let statusCode, _) = networkError
        else { return nil }
        return statusCode
    }
}
