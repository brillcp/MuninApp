import AuthenticationServices
import SwiftUI

/// The AutoFill credential provider.
///
/// The system presents it when the user chooses the app for a login or
/// one-time code field, or taps one of the app's keyboard suggestions. The
/// interface is ``AutoFillView``, hosted as a child view controller. It
/// unlocks with Face ID or Touch ID, loads the vault, and returns the chosen
/// password or code to complete the request.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    /// Creates a plain container view for the SwiftUI interface.
    override func loadView() {
        #if os(macOS)
        view = NSView()
        preferredContentSize = NSSize(width: 440, height: 560)
        #else
        view = UIView()
        #endif
    }

    /// Shows the password list, with matches for the service first.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        show(AutoFillModel(mode: .passwords, serviceIdentifiers: serviceIdentifiers, handler: self))
    }

    /// Shows the one-time code list, with matches for the service first.
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        show(AutoFillModel(mode: .oneTimeCodes, serviceIdentifiers: serviceIdentifiers, handler: self))
    }

    /// Requests user interaction, because the vault must be unlocked with
    /// Face ID or Touch ID before a credential can be provided.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        extensionContext.cancelRequest(withError: Self.error(.userInteractionRequired))
    }

    /// Shows the interface for a selected keyboard suggestion, which unlocks
    /// the vault and fills that item immediately.
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        guard let identity = credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity,
              let id = identity.recordIdentifier.flatMap(UUID.init(uuidString:)) else {
            extensionContext.cancelRequest(withError: Self.error(.credentialIdentityNotFound))
            return
        }
        show(AutoFillModel(mode: .passwords, serviceIdentifiers: [identity.serviceIdentifier], requestedItemID: id, handler: self))
    }
}

// MARK: - AutoFillHandler
extension CredentialProviderViewController: AutoFillHandler {
    /// Completes the request with a password credential.
    ///
    /// - Parameters:
    ///   - user: The username to fill.
    ///   - password: The password to fill.
    func fill(user: String, password: String) {
        extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: user, password: password), completionHandler: nil)
    }

    /// Completes the request with a one-time code.
    ///
    /// - Parameter code: The one-time code to fill.
    func fill(code: String) {
        extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code), completionHandler: nil)
    }

    /// Cancels the request because the user dismissed the interface.
    func cancel() {
        extensionContext.cancelRequest(withError: Self.error(.userCanceled))
    }
}

private extension CredentialProviderViewController {
    /// Embeds the SwiftUI interface for the model, filling the view.
    ///
    /// - Parameter model: The model that drives the interface.
    func show(_ model: AutoFillModel) {
        let root = AutoFillView(model: model)
        #if os(macOS)
        let host = NSHostingController(rootView: root)
        #else
        let host = UIHostingController(rootView: root)
        #endif
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        #if os(iOS)
        host.didMove(toParent: self)
        #endif
    }

    /// Creates an AutoFill extension error.
    ///
    /// - Parameter code: The error code.
    /// - Returns: An error in the AutoFill extension error domain.
    static func error(_ code: ASExtensionError.Code) -> NSError {
        NSError(domain: ASExtensionErrorDomain, code: code.rawValue)
    }
}
