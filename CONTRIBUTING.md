# Contributing to Munin

Thanks for your interest in improving Munin. This guide covers setup, the pull
request flow, and the code conventions the project follows.

## Setup

1. Install Xcode 27.1 or later.
2. Install SwiftLint:

   ```
   brew install swiftlint
   ```

3. Fork and clone the repository.
4. Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and set your
   own signing settings. Git ignores this file.

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   APP_BUNDLE_ID = com.example.Munin
   ```

5. Open `MuninApp.xcodeproj` and run the **MuninApp** scheme.

See the [README](README.md#configuration) for every configuration setting.

## Pull requests

1. Create a branch from `main` with a short, descriptive name, such as
   `fix-autofill-search`.
2. Keep each pull request focused on one change.
3. Before you open the pull request:
   - Build for both iOS and macOS.
   - Run the tests with Command-U, or
     `xcodebuild test -scheme MuninApp -destination 'platform=macOS'`.
   - Run `swiftlint` from the repository root and fix any violations.
4. Describe what changed and why. Include screenshots for UI changes on each
   platform you touched.

Add or update tests for logic changes, especially in `Core/Vault`. For
changes to encryption, key handling, or the keychain, explain the security
impact in the pull request.

## Code conventions

The project uses Swift 6 language mode, with `MainActor` as the default actor
isolation. Mark pure helpers that run off the main actor `nonisolated`.

### Files

- One view per file, named after the view, in its feature's folder under
  `MuninApp/Features/`.
- Code shared by the app and the AutoFill extension lives in `MuninApp/Core/`.

### Views

Inside a `View` struct, order members as follows:

1. `private static` properties
2. `private` `@Environment` properties
3. Other `private` property wrappers, such as `@State` and `@FocusState`
4. Inputs: `let` properties, `@Binding`, and `var` properties with defaults
5. Initializers
6. `body`

Put subviews, computed properties, and helper methods in a
`private extension` below the struct.

```swift
struct PasswordRow: View {
    private static let iconSize: CGFloat = 24

    @Environment(VaultSession.self) private var session
    @State private var isCopied = false

    let item: PasswordItem

    var body: some View {
        HStack {
            icon
            Text(item.name)
        }
    }
}

private extension PasswordRow {
    var icon: some View {
        WebsiteIcon(url: item.url, size: Self.iconSize)
    }

    func copyPassword() {
        isCopied = true
    }
}
```

### Classes and actors

Inside a class or actor, order stored members as follows:

1. `private static` properties
2. `private` properties
3. `private(set)` properties
4. `let` and `var` properties
5. Initializers

Put internal computed properties and methods in an `extension`, and private
ones in a `private extension`. Within each extension, list computed
properties before methods.

```swift
@Observable
final class ExampleModel {
    private static let defaultsKey = "example.value"

    private var task: Task<Void, Never>?

    private(set) var items: [Item] = []

    var isEditing = false

    init() {}
}

extension ExampleModel {
    var isEmpty: Bool { items.isEmpty }

    func load() async { /* ... */ }
}

private extension ExampleModel {
    var sortedItems: [Item] { items.sorted() }

    func save() { /* ... */ }
}
```

### Comments and documentation

- Document every type and every non-private property and method with `///`,
  in the style of Apple's documentation: a short summary in the present
  tense, then a discussion only when it adds information.
- Use `- Parameters:`, `- Returns:`, and `- Throws:` when they say more than
  the signature does. Refer to symbols with double backticks, such as
  ``VaultSession``.
- Document private members only when the name and type don't explain them:
  side effects, threading, security reasons, units, or why a value is what
  it is.
- Describe the code as it is now. Don't describe past bugs, earlier
  implementations, or how the code got here.
- Use `//` comments to explain why, not what.
- Don't put comments between chained view modifiers. Explain the view in a
  comment above it instead.

## Localization

User-facing strings live in `MuninApp/<language>.lproj/Localizable.strings`,
with plurals in `Localizable.stringsdict`. Refer to strings by key, using
`Localized(_:_:)` for a `String` or `LocalizedKey(_:_:)` for a
`LocalizedStringKey`, or by passing the key directly to a SwiftUI view.

Every new string needs an entry in `en.lproj` at minimum. Translations for
other languages are welcome in the same or a later pull request.

## Security issues

Don't open public issues for vulnerabilities. Follow
[SECURITY.md](SECURITY.md) instead.

## License

Munin is licensed under the GNU General Public License v3.0. By contributing,
you agree that your contributions are licensed under the same license.
