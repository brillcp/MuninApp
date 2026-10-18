import SwiftUI

/// Covers the codes until the user authenticates.
struct LockView: View {
    @Environment(AppLock.self) private var appLock

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Munin is locked")
                .font(.title2.bold())
            Spacer()
            Button("Unlock") {
                Task { await appLock.unlock() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appLock.isAuthenticating)

            if let error = appLock.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
