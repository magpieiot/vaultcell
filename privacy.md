# Privacy Policy — VaultCell

**Last Updated: November 2, 2026**
**Applies to: VaultCell for iOS, version 1.0 and later**

---

## 1. Who We Are

VaultCell is an iOS password manager developed and published by Gavan Wang ("we," "us," "our"), an independent developer. This policy explains what happens to information when you use the VaultCell app (the "App") and its AutoFill extension.

We do not operate any backend servers for the App. We have no user accounts, no sign-up, and no way to associate a vault with a person.

---

## 2. The Short Version

- **Your vault never reaches us.** Everything you enter is encrypted on your device before it is written to disk. We hold no copy and no key.
- **No accounts, no tracking, no analytics.** The App contains no analytics, advertising, or crash-reporting SDK.
- **iCloud sync is optional and off by default.** If you enable it, already-encrypted records go to *your own* private iCloud database, which we cannot read or access.
- **A forgotten master password cannot be recovered** — not by you, and not by us. This is a consequence of the design, not a policy choice.

---

## 3. Information Stored on Your Device

The App stores the following, entered by you, in an encrypted local database:

- Passwords and login credentials
- Secure notes
- Bank card details
- Two-factor authentication secrets (TOTP) and backup codes
- Tags, categories, and app preferences

This data is created by you and remains under your control. We do not receive it.

---

## 4. How Your Data Is Protected

| Layer | Implementation |
|---|---|
| Bulk encryption | AES-256-GCM via Apple CryptoKit, authenticated encryption |
| Key derivation | PBKDF2-SHA256, 600,000 iterations, 256-bit salt, 256-bit derived key |
| Master password | Never stored, never transmitted. It exists only in memory while the vault is unlocked |
| Unlocked key material | Device Keychain, protected by the Secure Enclave |
| Brute-force resistance | Progressive throttle on failed unlock attempts |

Because the master password is never stored or transmitted, there is no server-side reset, no recovery key held by us, and no backdoor. If you lose your master password and have no encrypted backup, your data is permanently inaccessible.

---

## 5. Biometric Unlock

If you enable Face ID or Touch ID, iOS unlocks a key stored in your device Keychain and protected by the Secure Enclave. Biometric data is handled entirely by iOS: it never leaves your device, is never copied by the App, and is never transmitted to us or anyone else. We receive only a success or failure result.

You can disable biometric unlock at any time in Settings; the master password continues to work.

---

## 6. Optional iCloud Sync

**Sync is off by default.** Nothing leaves your device until you deliberately turn it on in Settings.

When enabled:

- **What is uploaded:** only records that are *already encrypted* on your device. The App uses Apple's CloudKit framework (`CKSyncEngine`) to write these encrypted records to a private zone in *your* iCloud account, under the container `iCloud.com.magpie.vaultcell`.
- **Who can read it:** you, through your Apple ID. The database is a *private* CloudKit database. We have no credentials, no access grant, and no ability to query it.
- **Apple's role:** Apple Inc. provides the iCloud storage and transport. Apple's handling of data in your iCloud account is governed by Apple's terms and privacy policy, not this one. Encrypted payloads pass through Apple's infrastructure; Apple cannot decrypt them either.
- **Silent notifications:** to keep multiple devices in step, the App registers for silent push notifications from Apple. These wake the App so it can fetch changes. Notifications contain no credential content.
- **Turning it off:** disabling sync stops further syncing. Records already written to iCloud remain there until you delete them or delete the App's iCloud data through iOS settings.
- **No Apple ID:** every feature except multi-device sync continues to work locally.

If you never enable sync, the App's only outbound network request is the optional website-icon lookup described in Section 7.

---

## 7. The One Outbound Request: Website Icons

To display a recognizable icon for a saved login, the App may send a single HTTP request to the website address you stored for that entry, asking for its favicon or site manifest.

- The request goes **directly from your device to that website**. It does not pass through any server of ours.
- The operator of that website may therefore see your IP address and the fact that a request was made, exactly as if you had visited it in a browser.
- This is the only situation in which the App contacts a third-party server on your behalf.
- You can disable it at **Settings → Tools → Website Icons**. With that switch off, the App makes no network requests at all (unless you have enabled iCloud sync), and icons fall back to locally generated placeholders.

---

## 8. AutoFill Extension

VaultCell includes an AutoFill Credential Provider extension so you can fill passwords in Safari and other apps.

- The extension reads the same encrypted vault file as the main App, through a shared App Group container.
- It cannot read plaintext without the vault being unlocked by you.
- It supplies iOS with the *identity* of matching credentials (site, username) so the QuickType bar can offer them. Your passwords are handed to the requesting app only after you authenticate and explicitly select an entry.
- The extension does not read, capture, or transmit anything from other apps' contents.

---

## 9. Third-Party Code

The App links only two third-party open-source libraries:

- **SnapKit** — Auto Layout helpers. No networking, no data collection.
- **KeychainAccess** — a thin wrapper over the iOS Keychain. No networking, no data collection.

There are no analytics SDKs, no advertising SDKs, no crash-reporting SDKs, no attribution SDKs, and no social-media SDKs. No third-party code in the App receives your data.

Consequently, the App Store privacy questionnaire for VaultCell declares that **no data is collected**.

---

## 10. What We Do Not Collect

We do not collect, and have no technical means of obtaining:

- Your name, email address, phone number, or postal address
- Account credentials of any kind
- Device identifiers (IDFA, IDFV), advertising identifiers, or fingerprinting signals
- IP addresses
- Location data (precise or coarse)
- Contacts, calendars, photos, or health data
- Usage analytics, session recordings, or behavioural profiles
- Crash logs or diagnostics sent to us (iOS may offer to share these with Apple; that is between you and Apple)

---

## 11. Exports and Backups

You can export your vault at any time.

- **Encrypted backup (`.vgbackup`):** protected by a backup password you choose. The file goes exactly where you save it — Files, AirDrop, another app. It never passes through a server of ours. Anyone with the file *and* the password can read it, so store both carefully.
- **Plaintext export (CSV / JSON):** produces an unencrypted file for migration to another password manager. It contains your credentials in the clear. Delete it once migration is complete.

We cannot access, recover, or restore either kind of file for you.

---

## 12. Retention and Deletion

- **Delete items:** remove any entry at any time inside the App.
- **Erase the vault:** Settings → Reset Vault destroys the local vault and its key material. If sync is enabled, the deletion propagates to your CloudKit zone.
- **Uninstall:** removing the App deletes its container and the encrypted vault file inside it. Note two exceptions that iOS controls: Keychain entries may survive an uninstall and reappear on reinstall (cleared only by Reset Vault or by erasing the device), and iCloud data may persist under your Apple ID until you remove it via iOS Settings → Apple ID → iCloud → Manage Account Storage.
- **Retention by us:** zero. We hold no copy of your vault, so there is nothing for us to retain or delete.

Because deletion is immediate and cryptographic, erased data cannot be restored by us. Export an encrypted backup first if you might need the data later.

---

## 13. Your Privacy Rights

Even though we hold no vault data, privacy laws such as the EU/UK General Data Protection Regulation ("GDPR") and the California Consumer Privacy Act as amended by the CPRA ("CCPA/CPRA") grant you rights that we respect:

| Right | How it applies here |
|---|---|
| Access / portability | Your data is on your device and exportable at any time via Settings → Export Data. That is the complete record — there is no shadow copy held by us. |
| Rectification | Edit any entry directly in the App. |
| Erasure | Delete individual items or reset the vault. See Section 12. |
| Objection / restriction | Disable iCloud sync and Website Icons to eliminate all network activity. |
| Non-discrimination | Exercising any of these rights has no effect on your use of the App. |
| Opt out of sale/sharing | We have never sold or shared personal information, and have no data to sell. |

**Data controller.** We do not act as a controller or processor of your vault contents, because those contents never reach us in readable or attributable form. Where you contact us by email, we process your email address and message solely to respond, and delete it when the matter is closed.

**Exercising your rights.** Write to the address in Section 17. We respond within 30 days. If you are unsatisfied, you may lodge a complaint with your local supervisory authority (in the EU/UK) or the California Privacy Protection Agency.

---

## 14. Children's Privacy

The App is not directed at children under 13. We do not knowingly collect personal information from anyone, including children, because we do not collect personal information at all. A parent or guardian who lets a minor use the App should understand that the vault is protected solely by its master password, and that a forgotten master password means permanent loss of the data. See the COPPA and GDPR provisions above; our compliance rests on the absence of collection, not on age gating.

---

## 15. International Transfers

We do not transfer your vault data anywhere, because we never receive it. If you enable iCloud sync, Apple stores and moves your encrypted records according to your Apple ID's region and Apple's own terms. Encrypted payloads remain unreadable in transit and at rest.

---

## 16. Security Incidents

If we ever learn of a vulnerability or incident that could affect the confidentiality of vault data, we will publish details and remediation guidance at our website and in the App's release notes as soon as practicable. Note the structural limit of the risk: we hold no keys and no ciphertext, so an incident on our side cannot expose vault contents. Risks that matter in practice are device-level (malware, jailbreak, shoulder-surfing, weak master passwords) and are addressed in the Terms.

---

## 17. Contact

Questions about this policy or about how VaultCell handles data:

**Email:** [magpieiot@gmail.com](mailto:magpieiot@gmail.com)
**Website:** [www.magpieai.app](https://www.magpieai.app)

---

## 18. Changes to This Policy

We may update this policy as the App evolves. Material changes will be reflected in the "Last Updated" date above and, for significant changes, noted in the App's release notes. The copy shipped inside the App (Settings → About → Privacy Policy) always describes what the installed version actually does. If the App ever gains a capability this policy does not describe, the policy will be updated before that capability ships.

---

© 2026 Gavan Wang. All rights reserved.
