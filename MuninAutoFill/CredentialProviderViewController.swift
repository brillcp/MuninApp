import AuthenticationServices
import SwiftUI

/// Munin's AutoFill: shown by the system when the user picks Munin for a
/// login or a 2FA code field, or taps one of Munin's keyboard suggestions.
///
/// The interface is `AutoFillView` (SwiftUI), hosted as a child controller.
/// It unlocks with Face ID / Touch ID, loads the vault from Munin, and hands
/// the chosen password or code back here to complete the request.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    /// No storyboard or nib: the view is a plain container for the SwiftUI view.
    override func loadView() {
        #if os(macOS)
        view = NSView()
        preferredContentSize = NSSize(width: 440, height: 560)
        #else
        view = UIView()
        #endif
    }

    /// The user chose Munin for a login field: list matching passwords first.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        show(AutoFillModel(mode: .passwords, serviceIdentifiers: serviceIdentifiers, handler: self))
    }

    /// The user chose Munin for a 2FA code field: list matching codes first.
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        show(AutoFillModel(mode: .oneTimeCodes, serviceIdentifiers: serviceIdentifiers, handler: self))
    }

    /// A keyboard suggestion was tapped. Munin always needs Face ID / Touch ID
    /// first, so the system is asked to show the interface instead.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        extensionContext.cancelRequest(withError: Self.error(.userInteractionRequired))
    }

    /// The interface for a tapped keyboard suggestion: unlocks and fills that
    /// item straight away.
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
    func fill(user: String, password: String) {
        extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: user, password: password), completionHandler: nil)
    }

    func fill(code: String) {
        extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code), completionHandler: nil)
    }

    func cancel() {
        extensionContext.cancelRequest(withError: Self.error(.userCanceled))
    }
}

private extension CredentialProviderViewController {
    /// Puts the SwiftUI interface for `model` in the view, filling it.
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

    /// An AutoFill error for the system.
    static func error(_ code: ASExtensionError.Code) -> NSError {
        NSError(domain: ASExtensionErrorDomain, code: code.rawValue)
    }
}
