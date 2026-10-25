import Foundation
import Networking

/// Endpoints on Munin's `/v1` base URL.
enum MuninEndpoint: EndpointType {
    /// `/entries`: the 2FA accounts.
    case entries
    /// `/entries/{id}`: one 2FA account.
    case entry(UUID)
    /// `/passwords`: the password items.
    case passwords
    /// `/passwords/{id}`: one password item.
    case password(UUID)
    /// `/passwords/{id}/touch`: bumps an item's last updated time.
    case passwordTouch(UUID)
    /// `/vault-key`: the wrapped vault key.
    case vaultKey

    /// `/subscription`: the user's App Store subscription.
    case subscription
    /// `/account`: the user's account and everything in it.
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
