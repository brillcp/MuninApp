import Foundation
import Networking

/// The one place that decides what a backend/auth error means.
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

    /// Munin refused the token: expired or invalid → sign in again.
    var isMuninAuthRejection: Bool {
        self is TokenProvidableError || httpStatus == .unauthorized
    }

    var httpStatus: HTTP.StatusCode? {
        guard let networkError = self as? Network.Service.NetworkError,
              case .badServerResponse(let statusCode, _) = networkError
        else { return nil }
        return statusCode
    }
}
