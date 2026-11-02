# Terms of Service — VaultCell

**Last Updated: November 2, 2026**
**Applies to: VaultCell for iOS, version 1.0 and later**

---

## 1. Acceptance

These Terms of Service ("Terms") are a legal agreement between you ("you," "your") and Gavan Wang ("we," "us," "our"), the developer of the VaultCell mobile application and its AutoFill extension (together, the "App").

By downloading, installing, or using the App, you agree to these Terms. If you do not agree, do not install the App, and if already installed, delete it and your data.

If you use the App on behalf of an organisation, you represent that you have authority to bind that organisation to these Terms.

---

## 2. The Service

VaultCell is a **local-first password manager**. It stores credentials, secure notes, bank card details, and two-factor secrets in an encrypted database on your device. It requires no account and no registration.

- **Core functionality works entirely offline.**
- **Optional iCloud sync** replicates encrypted records across your own devices through your private iCloud database. See Section 6.
- **AutoFill** lets you fill credentials in Safari and other apps through an iOS Credential Provider extension.

The App is provided **free of charge**, with no in-app purchases, no subscriptions, and no advertising. See Section 9.

We may release updates, change features, or discontinue the App. Features that depend on iOS or on Apple's iCloud service are also subject to Apple's availability.

---

## 3. Licence Grant

Subject to these Terms, we grant you a personal, non-exclusive, non-transferable, revocable, limited licence to install and use the App on Apple-branded devices that you own or control, as permitted by the App Store Usage Rules.

You may not:

- Copy, redistribute, sublicense, rent, lease, or lend the App;
- Reverse engineer, decompile, disassemble, or attempt to derive the source code, except to the extent such restriction is prohibited by applicable law;
- Remove or alter any proprietary notices;
- Use the App to build a competing product by extracting its designs, database schema, or encryption implementation.

This licence terminates automatically if you breach these Terms. Termination does not entitle you to a refund (the App is free), and does not restore access to a vault whose master password has been lost.

---

## 4. Your Master Password — Read This Section

**This is the single most important section of these Terms.**

- Your master password is the **only** key to your vault. It is used to derive your encryption key on your device (PBKDF2-SHA256, 600,000 iterations) and is **never stored, never transmitted, and never backed up by us**.
- **We cannot reset it, recover it, or bypass it.** There is no account recovery, no support override, no escrow key, and no backdoor. This is intentional: any mechanism that could recover your vault for you could also be used against you.
- **If you forget your master password, your data is permanently and irreversibly lost.** No party — including us, including Apple — can restore it.
- **You are solely responsible for:**
  - Choosing a strong, unique master password;
  - Remembering it, or recording it somewhere physically secure and separate from your device;
  - Creating and safeguarding encrypted backups (`.vgbackup`) if the data matters to you;
  - Keeping the backup password, which is separate from and not recoverable through your master password.

We will not be liable for data loss resulting from a forgotten master password, a lost or destroyed device, a corrupted backup, or the absence of a backup. This allocation of risk is a fundamental basis of the bargain and is reflected in the fact that the App is free.

---

## 5. Acceptable Use

You agree not to use the App to:

- Store or manage credentials you are not lawfully entitled to hold;
- Access systems without authorisation, or store another person's credentials without their consent;
- Violate any applicable law or regulation;
- Circumvent, disable, or interfere with security features of the App or of iOS;
- Distribute malware, or use the App as part of an unlawful service.

You are responsible for all activity that occurs within your vault.

---

## 6. iCloud Sync

Sync is **off by default** and requires your explicit consent plus an Apple ID signed in to the device.

When enabled:

- Only records **already encrypted on your device** are transmitted, using Apple's CloudKit framework, to a private database in **your own** iCloud account.
- We do not hold credentials to that database and cannot read, query, decrypt, or delete its contents.
- Apple provides the storage and transport. Your use of iCloud is governed by Apple's terms; Apple's role is described in our Privacy Policy.
- Silent push notifications are used to keep devices in step. They carry no credential content.
- Sync is best-effort. Conflict resolution prefers the most recent write. **Sync is not a backup**: a deletion propagates. Keep an independent encrypted backup.
- Disabling sync stops further replication but does not delete records already in iCloud. Remove those through iOS Settings if you want them gone.

We are not responsible for data loss, duplication, or delay caused by iCloud outages, Apple ID changes, storage limits, or conflict resolution.

---

## 7. AutoFill Extension

The AutoFill extension runs inside iOS's credential-request flow and accesses the same encrypted vault as the main App.

- It cannot expose plaintext without you unlocking the vault and selecting an entry.
- It declines requests it cannot satisfy (for example, passkey requests) so that iOS can fall back to your other credential providers.
- Its behaviour depends on iOS and on your enabling VaultCell in iOS Settings → General → AutoFill & Passwords.

We are not responsible for the security of third-party apps into which you choose to fill credentials, nor for iOS behaviour outside our control.

---

## 8. Intellectual Property

The App, including its source code, user interface, visual design, icon set, database schema, and documentation, is owned by us and protected by copyright and other laws. "VaultCell" and its logo are our marks.

These Terms grant you a licence to use the App; they do not transfer any ownership. All rights not expressly granted are reserved.

You retain all rights to the content you store in the App. We claim no licence to it — we cannot even read it.

---

## 9. Fees

The App is free. There are no in-app purchases, no subscriptions, no trials that convert to paid plans, and no advertising. If this ever changes, the change will apply only to future versions and will be disclosed in the App Store listing and in these Terms before any charge is introduced.

Apple may charge you for iCloud storage beyond the free tier. That transaction is between you and Apple; we receive nothing from it.

---

## 10. Apple App Store — Additional Terms

You acknowledge and agree that:

1. **These Terms are between you and us only, not with Apple.** Apple is not a party to them and bears no obligation to you regarding the App.
2. **Apple has no obligation to furnish maintenance or support** for the App. All support requests go to us at the address in Section 19.
3. **Warranty claims.** If the App fails to conform to any applicable warranty, you may notify Apple, and Apple may refund the purchase price to you (there being none, this is nominal). To the maximum extent permitted by law, Apple has no other warranty obligation with respect to the App.
4. **Claims.** We, not Apple, are responsible for addressing any claims by you or a third party relating to the App or your possession and use of it, including product liability, consumer protection, and intellectual property claims. This does not expand our liability beyond Section 12.
5. **Legal compliance.** You represent that you are not located in a country subject to a U.S. Government embargo or designated as a "terrorist supporting" country, and that you are not listed on any U.S. Government list of prohibited or restricted parties.
6. **Third-party beneficiary.** Apple and its subsidiaries are third-party beneficiaries of these Terms and, upon your acceptance, will have the right (and will be deemed to have accepted the right) to enforce them against you.

---

## 11. Export Control and Encryption

The App contains cryptographic functionality, including AES-256-GCM and PBKDF2-SHA256, and is subject to export control laws.

You agree to comply with all applicable export and re-export regulations, including those of the United States and of the jurisdiction in which you obtained the App. You may not export or re-export the App to any prohibited country, entity, or person.

---

## 12. Disclaimer of Warranties

> **THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTY OF ANY KIND. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT, ACCURACY, AND NON-INFRINGEMENT.**
>
> **WE DO NOT WARRANT THAT THE APP WILL BE ERROR-FREE, UNINTERRUPTED, OR FREE OF VULNERABILITIES; THAT DEFECTS WILL BE CORRECTED; THAT YOUR DATA WILL NEVER BE LOST, CORRUPTED, OR INADVERTENTLY DELETED; THAT SYNC WILL ALWAYS COMPLETE; OR THAT THE APP WILL BE COMPATIBLE WITH EVERY iOS VERSION OR DEVICE.**
>
> **NO SOFTWARE IS PERFECTLY SECURE. YOU ACCEPT THE RISK ASSOCIATED WITH USING A DEVICE THAT IS LOST, STOLEN, JAILBROKEN, INFECTED WITH MALWARE, SUBJECT TO PHYSICAL OR REMOTE COMPROMISE, OR ACCESSED BY SOMEONE WHO KNOWS YOUR MASTER PASSWORD OR DEVICE PASSCODE.**
>
> **SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION OF IMPLIED WARRANTIES, SO PARTS OF THIS SECTION MAY NOT APPLY TO YOU. NOTHING IN THIS SECTION LIMITS ANY STATUTORY WARRANTY THAT CANNOT BE EXCLUDED.**

---

## 13. Limitation of Liability

> **TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, PUNITIVE, OR EXEMPLARY DAMAGES, OR FOR ANY LOSS OF PROFITS, REVENUE, BUSINESS, GOODWILL, DATA, OR DATA ACCESS, ARISING OUT OF OR RELATING TO THE APP, EVEN IF WE HAVE BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.**
>
> **WHERE LIABILITY CANNOT LAWFULLY BE EXCLUDED, OUR TOTAL AGGREGATE LIABILITY ARISING OUT OF OR RELATING TO THE APP SHALL NOT EXCEED TEN U.S. DOLLARS (USD 10), REFLECTING THE FACT THAT THE APP IS PROVIDED FREE OF CHARGE.**
>
> **THESE LIMITS APPLY REGARDLESS OF THE THEORY OF LIABILITY (CONTRACT, TORT, NEGLIGENCE, STRICT LIABILITY, OR OTHERWISE) AND SURVIVE ANY FAILURE OF ESSENTIAL PURPOSE.**

**Nothing in these Terms excludes or limits our liability for:**

- Death or personal injury caused by our negligence;
- Fraud or fraudulent misrepresentation;
- Gross negligence or wilful misconduct;
- Any other liability that cannot be excluded or limited under applicable law.

**If you are a consumer resident in the European Economic Area, the United Kingdom, or Switzerland**, you benefit from mandatory provisions of the law of your country of residence, and nothing in these Terms affects your statutory rights. In particular, clauses that would unfairly exclude liability toward a consumer may not be enforceable against you.

---

## 14. Indemnity

To the extent permitted by law, you agree to indemnify and hold us harmless from claims, damages, and reasonable legal costs arising from your unlawful use of the App or your breach of Section 5. This does not apply to claims caused by our own breach, negligence, or wilful misconduct, and does not apply to consumers in jurisdictions where such indemnities are unenforceable.

---

## 15. Termination

You may stop using the App at any time and delete it and your data.

We may suspend or terminate this licence if you materially breach these Terms, or if we discontinue the App. Where practical, we will give notice through the App Store listing or the App's release notes.

Sections 4, 8, 10, 11, 12, 13, 14, 17, and 18 survive termination.

---

## 16. Changes to These Terms

We may revise these Terms as the App evolves. The revised version will be published with a new "Last Updated" date, and material changes will be surfaced in the App's release notes. Continued use after a revision takes effect constitutes acceptance. If you do not accept a revision, stop using the App.

Because we hold no account or contact record for you, we cannot send you individual notice. The published version is the binding one.

---

## 17. Governing Law and Disputes

- **Consumers in the EU/UK/EEA:** these Terms are governed by the laws of the country in which you reside, and you may bring proceedings in the courts of that country. Nothing here deprives you of the protection of mandatory consumer law in your place of residence.
- **All other users:** these Terms are governed by the laws of the State of Delaware, United States, without regard to its conflict-of-laws rules. You agree to the exclusive jurisdiction of the state and federal courts located in Delaware, except that either party may seek injunctive relief in any competent court to protect intellectual property or prevent misuse.

Before filing a claim, please contact us at the address in Section 19 and give us 30 days to resolve the matter informally. This is a request, not a condition that limits any right you have under mandatory law.

The United Nations Convention on Contracts for the International Sale of Goods does not apply.

---

## 18. General

**Entire agreement.** These Terms, together with the Privacy Policy, are the complete agreement between you and us regarding the App.

**Severability.** If any provision is held invalid or unenforceable, it will be limited to the minimum extent necessary and the remaining provisions stay in force. If a limitation of liability is unenforceable, the parties intend that a lesser enforceable limitation apply.

**No waiver.** Our failure to enforce a provision is not a waiver of it.

**Assignment.** You may not assign these Terms. We may assign them to a successor in connection with a merger, acquisition, or sale of the App, provided the successor honours them.

**No third-party beneficiaries.** Except for Apple under Section 10, no third party has rights under these Terms.

**Force majeure.** We are not liable for delay or failure caused by events beyond our reasonable control, including Apple service outages.

**Language.** These Terms are drafted in English. Any translation is provided for convenience; the English version controls.

---

## 19. Contact

**Email:** [magpieiot@gmail.com](mailto:magpieiot@gmail.com)
**Website:** [www.magpieai.app](https://www.magpieai.app)

---

© 2026 Gavan Wang. All rights reserved.
