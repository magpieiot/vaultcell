# VaultCell Agent Notes

## Project and Commands

- `project.yml` is the XcodeGen source of truth; run `xcodegen generate` after changing targets, packages, schemes, or build settings instead of hand-editing `VaultCell.xcodeproj/project.pbxproj`.
- The project contains two targets: the `VaultCell` app and the embedded `AutoFillProvider` app extension. Swift Package Manager dependencies are SnapKit and KeychainAccess.
- Build the default scheme without signing with `xcodebuild -project VaultCell.xcodeproj -scheme VaultCell -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/vaultcell-derived CODE_SIGNING_ALLOWED=NO build`.
- There is currently no project-owned test target or test source. Use a focused simulator build for compile verification; do not assume `xcodebuild test` exercises repository tests.

## Structure

- `VaultCell/App/VaultCellApp.swift` is the SwiftUI entry point; `AppState` owns authentication, lock state, and app lifecycle behavior.
- UI belongs in `VaultCell/Presentation/Views`; view models belong in `VaultCell/Presentation/ViewModels`; business operations are in `VaultCell/Domain/Services`; persistence is in `VaultCell/Data`.
- `VaultCell/Core/Security` contains the encryption, PBKDF2, Keychain, biometric, TOTP, and encrypted-file code. Treat changes there as security-sensitive and verify both lock/unlock and encryption/decryption flows.
- The Core Data model is `VaultCell/Resources/VaultCell.xcdatamodeld`; `VaultCell_v5.xcdatamodel` is the current version. Model changes must preserve the existing automatic migration path.
- The app and `AutoFillProvider` share credentials through the configured App Group and Keychain access group. Keep entitlements, target settings, and Keychain service/access-group values aligned across both targets.

## Conventions

- Follow the VaultCell-specific rules in `.codebuddy/rules.md`: MVVM separation, `async/await` for new asynchronous work, and `@MainActor` for UI state updates. Comments and project documentation are written in Chinese.
- Keep changes surgical. Avoid editing generated project files directly, and do not copy architecture or security claims from the design documents into implementation without checking the actual Swift code.
