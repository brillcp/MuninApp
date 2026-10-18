import Foundation
import Networking

/// Endpoints on Munin's `/v1` base URL.
enum MuninEndpoint: EndpointType {
    case entries
    case entry(UUID)
    case passwords
    case password(UUID)
    case passwordTouch(UUID)

    var path: String {
        switch self {
        case .entries:                return "entries"
        case .entry(let id):          return "entries/\(id.uuidString)"
        case .passwords:              return "passwords"
        case .password(let id):       return "passwords/\(id.uuidString)"
        case .passwordTouch(let id):  return "passwords/\(id.uuidString)/touch"
        }
    }
}
