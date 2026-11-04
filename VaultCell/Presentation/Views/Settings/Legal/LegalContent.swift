/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// LegalContent.swift
/// ------------------------------------------------------------------
///
/// 「帮助与反馈」的文档内容。
///
/// 隐私政策与服务条款**不在 App 内保存副本**：条款只维护线上唯一一份，
/// 关于页点击后用系统浏览器打开 `Legal.privacyPolicyURL` / `Legal.termsOfServiceURL`。
/// 这样避免同一份条款在 App 内与线上各存一份、改一处漏一处，
/// 也避免审核员在 App 内看到与 App Store Connect 声明不一致的旧版本。
///
/// ⚠️ 维护要求：帮助文案涉及的每一项能力都必须与代码实现一致。
/// 加密口径见 `Core/Security/EncryptionService.swift`（AES-GCM + PBKDF2-SHA256）；
/// 同步口径见 `Domain/Services/Sync/CloudSyncService.swift`（CKSyncEngine + 私有库）。
/// ------------------------------------------------------------------

import Foundation

/// 文档中的一个小节（heading 同时作为 ForEach 的 id）
struct LegalSection: Identifiable {
    let heading: String
    let body: String

    var id: String { heading }
}

enum LegalContent {

    // MARK: - 帮助与反馈

    static let help: [LegalSection] = [
        LegalSection(
            heading: "How to enable AutoFill",
            body:
                "Open iOS Settings → General → AutoFill & Passwords and enable VaultCell. Then open any login page in Safari, tap the username field and choose VaultCell above the keyboard; unlock with Face ID or your master password and tap the credential to fill it in."
        ),
        LegalSection(
            heading: "How iCloud sync works",
            body:
                "Sync is optional. Sign in to your Apple ID on the device and turn sync on in the vault's cloud settings. Changes arrive on your other devices through Apple's silent notifications, so allow notifications when iOS asks. Without an Apple ID, everything except multi-device sync still works."
        ),
        LegalSection(
            heading: "I forgot my master password",
            body:
                "For your protection nobody can recover it, including us. Reset the vault in Settings → Reset Vault, then restore from an encrypted backup if you made one when the vault was unlocked."
        ),
        LegalSection(
            heading: "How to move my data",
            body:
                "Use Export Data in Settings to create one encrypted backup file, move it to the new device, and use Import to restore everything — including tags and two-factor secrets."
        ),
        LegalSection(
            heading: "How to stay offline",
            body:
                "Turn off \"Website Icons\" in Settings → Tools and VaultCell makes no network requests at all. Everything else already works offline."
        ),
        LegalSection(
            heading: "Contacting us",
            body:
                "Bug reports and feature requests are welcome by email, and an App Store review helps other people find VaultCell."
        ),
    ]
}
