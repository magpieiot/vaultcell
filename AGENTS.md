# VaultGo Agent Notes

## Project and Commands

- `project.yml` is the XcodeGen source of truth; run `xcodegen generate` after changing targets, packages, schemes, or build settings instead of hand-editing `VaultGo.xcodeproj/project.pbxproj`.
- The project contains two targets: the `VaultGo` app and the embedded `AutoFillProvider` app extension. Swift Package Manager dependencies are SnapKit and KeychainAccess.
- Build the default scheme without signing with `xcodebuild -project VaultGo.xcodeproj -scheme VaultGo -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/vaultgo-derived CODE_SIGNING_ALLOWED=NO build`.
- The Chinese variant is the `VaultGo-CN` scheme with `Debug-CN`/`Release-CN` configurations and the `CN` compilation condition. Preserve its separate bundle and App Group identifiers when changing target settings.
- There is currently no project-owned test target or test source. Use a focused simulator build for compile verification; do not assume `xcodebuild test` exercises repository tests.

## Structure

- `VaultGo/App/VaultGoApp.swift` is the SwiftUI entry point; `AppState` owns authentication, lock state, and app lifecycle behavior.
- UI belongs in `VaultGo/Presentation/Views`; view models belong in `VaultGo/Presentation/ViewModels`; business operations are in `VaultGo/Domain/Services`; persistence is in `VaultGo/Data`.
- `VaultGo/Core/Security` contains the encryption, PBKDF2, Keychain, biometric, TOTP, and encrypted-file code. Treat changes there as security-sensitive and verify both lock/unlock and encryption/decryption flows.
- The Core Data model is `VaultGo/Resources/VaultGo.xcdatamodeld`; `VaultGo_v5.xcdatamodel` is the current version. Model changes must preserve the existing automatic migration path.
- The app and `AutoFillProvider` share credentials through the configured App Group and Keychain access group. Keep entitlements, target settings, and Keychain service/access-group values aligned across both targets and both scheme variants.

## Conventions

- Follow the VaultGo-specific rules in `.codebuddy/rules.md`: MVVM separation, `async/await` for new asynchronous work, and `@MainActor` for UI state updates. Comments and project documentation are written in Chinese.
- Keep changes surgical. Avoid editing generated project files directly, and do not copy architecture or security claims from the design documents into implementation without checking the actual Swift code.
