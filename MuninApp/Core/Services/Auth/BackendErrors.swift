import Foundation
import Networking

/// Classification of server and authentication errors.
extension Error {
    /// A Boolean value that indicates whether the session can't be reused
    /// because the token is missing or a refresh was rejected.
    ///
    /// The user needs to sign in again.
    var invalidatesAuthSession: Bool {
        if self is TokenProvidableError { return true }
        guard let status = httpStatus else { return false }
        switch status {
        case .badRequest, .unauthorized, .forbidden, .unprocessableEntity: return true
        default: return false
        }
    }

    /// A Boolean value that indicates whether the server rejected the access token as expired or invalid.
    var isMuninAuthRejection: Bool {
        self is TokenProvidableError || httpStatus == .unauthorized
    }

    /// The HTTP status of a server response error, or `nil` for any other error.
    var httpStatus: HTTP.StatusCode? {
        guard let networkError = self as? Network.Service.NetworkError,
              case .badServerResponse(let statusCode, _) = networkError
        else { return nil }
        return statusCode
    }
}
