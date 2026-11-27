import Foundation
import Networking

/// Endpoints relative to the API's `/v1` base URL.
enum MuninEndpoint: EndpointType {
    /// `/codes`: the two-factor accounts.
    case codes
    /// `/codes/{id}`: a single two-factor account.
    case code(UUID)
    /// `/passwords`: the password items.
    case passwords
    /// `/passwords/{id}`: a single password item.
    case password(UUID)
    /// `/passwords/{id}/touch`: updates an item's last-updated date.
    case passwordTouch(UUID)
    /// `/cards`: the stored cards.
    case cards
    /// `/cards/{id}`: a single card.
    case card(UUID)
    /// `/vault-key`: the wrapped vault key.
    case vaultKey

    /// `/subscription`: the user's App Store subscription.
    case subscription
    /// `/account`: the user's account and all of its data.
    case account

    var path: String {
        switch self {
        case .codes:                  return "codes"
        case .code(let id):           return "codes/\(id.uuidString)"
        case .passwords:              return "passwords"
        case .password(let id):       return "passwords/\(id.uuidString)"
        case .passwordTouch(let id):  return "passwords/\(id.uuidString)/touch"
        case .cards:                  return "cards"
        case .card(let id):           return "cards/\(id.uuidString)"
        case .vaultKey:               return "vault-key"
        case .subscription:           return "subscription"
        case .account:                return "account"
        }
    }
}
