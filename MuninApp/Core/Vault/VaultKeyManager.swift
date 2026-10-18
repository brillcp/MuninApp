import Foundation
import Observation

/// Makes sure this device has the user's vault key before any vault screen
/// loads. Creates one only for a user with nothing stored yet; otherwise the
/// key has to come from iCloud Keychain or the recovery key.
@Observable
final class VaultKeyManager {
    enum State: Equatable {
        case checking
        case ready
        /// Munin has data for this user, but this device has no key for it.
        case missing
        case failed(String)
    }

    private(set) var state: State = .checking

    func prepare(auth: AuthManager) async {
        guard let userID = auth.userID else {
            state = .failed(VaultError.notSignedIn.localizedDescription)
            return
        }
        if VaultKeyStore.load(userID: userID) != nil {
            state = .ready
            return
        }
        state = .checking
        do {
            let service = MuninService(tokenProvider: auth.tokenProvider)
            let entries = try await service.entries()
            let passwords = try await service.passwords()
            if entries.isEmpty && passwords.isEmpty {
                _ = VaultKeyStore.generate(userID: userID)
                state = .ready
            } else {
                // Don't create a new key: it couldn't read the existing data.
                state = .missing
            }
        } catch is CancellationError {
            return
        } catch let error where error.isMuninAuthRejection {
            auth.signOut()
        } catch {
            state = .failed(error.muninDescription)
        }
    }

    /// Saves a pasted recovery key. Returns false if it isn't a valid key.
    func restore(_ recoveryString: String, auth: AuthManager) -> Bool {
        guard let userID = auth.userID,
              let key = VaultKeyStore.key(fromRecoveryString: recoveryString) else { return false }
        VaultKeyStore.save(key, userID: userID)
        state = .ready
        return true
    }
}
