import Foundation
import Networking

/// Endpoints relative to the API's `/v1` base URL.
enum MuninEndpoint: EndpointType {
    /// `/entries`: the two-factor accounts.
    case entries
    /// `/entries/{id}`: a single two-factor account.
    case entry(UUID)
    /// `/passwords`: the password items.
    case passwords
    /// `/passwords/{id}`: a single password item.
    case password(UUID)
    /// `/passwords/{id}/touch`: updates an item's last-updated date.
    case passwordTouch(UUID)
    /// `/vault-key`: the wrapped vault key.
    case vaultKey

    /// `/subscription`: the user's App Store subscription.
    case subscription
    /// `/account`: the user's account and all of its data.
    case account

    var path: String {
        switch self {
        case .entries:                return "entries"
        case .entry(let id):          return "entries/\(id.uuidString)"
        case .passwords:              return "passwords"
        case .password(let id):       return "passwords/\(id.uuidString)"
        case .passwordTouch(let id):  return "passwords/\(id.uuidString)/touch"
        case .vaultKey:               return "vault-key"
        case .subscription:           return "subscription"
        case .account:                return "account"
        }
    }
}
