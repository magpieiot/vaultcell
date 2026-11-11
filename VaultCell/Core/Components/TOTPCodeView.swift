/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// TOTPCodeView.swift
/// created on: 27/06/2026
/// ------------------------------------------------------------------

import SwiftUI

/// TOTP 验证码显示控件
/// 根据 TwoFactorConfig 中的密钥、算法、位数与周期实时生成验证码，并显示倒计时进度环。
/// 验证码按配置的 period（默认 30 秒）刷新，最后一 5 秒内进度环变红提醒。
///
/// 用法：
/// ```swift
/// if let totpConfig = entry.twoFactorConfigs.first(where: { $0.type == .totp }) {
///     TOTPCodeView(config: totpConfig)
/// }
/// ```
struct TOTPCodeView: View {
    let config: TwoFactorConfig

    @State private var result: TOTPResult?
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            codeDisplay
            progressRing
            
            /*
            if let result {
                Text("\(result.remainingSeconds) 秒后刷新")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            */
        }
        //.padding(8)
        /*
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        */
        .onAppear(perform: startTimer)
        .onDisappear(perform: stopTimer)
    }

    // MARK: - 子视图

    private var issuerHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: TwoFactorType.totp.icon)
                .font(.title3)
                .foregroundColor(Color.primaryBrandColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.issuer ?? "TOTP")
                    .font(.headline)
                if let account = config.boundValue, !account.isEmpty {
                    Text(account)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button {
                let seconds = ClipboardService.shared.copy(result?.code ?? "")
                ToastCenter.shared.toast = .copied(clearAfter: seconds)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.body)
                    .foregroundColor(Color.primaryBrandColor)
            }
            .buttonStyle(.plain)
            .disabled(result == nil)
        }
    }

    private var codeDisplay: some View {
        Group {
            if let result {
                PasswordText(result.code, size: 28)
                    .letterColor(Color.primaryBrandColor)
                    .digitColor(Color.secondaryBrandColor)
                    .symbolColor(Color.successColor)
            } else {
                Text("------")
                    .font(.appNumber(.title2))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 4)

            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(
                    AngularGradient(
                        colors: ringColors,
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: result?.progress)

            Text("\(result?.remainingSeconds ?? 0)")
                .font(.system(.headline, design: .monospaced).bold())
                .foregroundColor(ringTextColor)
        }
        .frame(width: 40, height: 40)
    }

    private var progressValue: CGFloat {
        guard let result else { return 0 }
        return 1.0 - CGFloat(result.progress)
    }

    private var ringColors: [Color] {
        guard let result else { return [Color.appAccent] }
        // 最后 5 秒用语义色提醒，其余时间保持单一强调色
        return result.remainingSeconds <= 5 ? [Color.errorColor] : [Color.appAccent]
    }

    private var ringTextColor: Color {
        guard let result else { return .secondary }
        return result.remainingSeconds <= 5 ? Color.errorColor : .primary
    }

    // MARK: - 定时器

    private func startTimer() {
        refreshCode()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            refreshCode()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshCode() {
        guard let secret = config.secret, !secret.isEmpty else {
            result = nil
            return
        }

        let totpConfig = TOTPConfig(
            secret: secret,
            algorithm: TOTPAlgorithm(rawValue: config.algorithm.uppercased()) ?? .sha1,
            digits: config.digits,
            period: config.period
        )
        let newResult = TOTPService.shared.generate(config: totpConfig)

        if result?.code != newResult.code {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }

        result = newResult
    }
}

// MARK: - 预览

#Preview("正常状态") {
    TOTPCodeView(config: TwoFactorConfig(
        type: .totp,
        secret: "JBSWY3DPEHPK3PXP",
        issuer: "GitHub",
        boundValue: "octocat@example.com"
    ))
    .padding()
}

#Preview("无密钥") {
    TOTPCodeView(config: TwoFactorConfig(
        type: .totp,
        secret: nil,
        issuer: "GitHub",
        boundValue: "octocat@example.com"
    ))
    .padding()
}

#Preview("暗色模式") {
    VStack(spacing: 16) {
        TOTPCodeView(config: TwoFactorConfig(
            type: .totp,
            secret: "JBSWY3DPEHPK3PXP",
            issuer: "Google",
            boundValue: "user@gmail.com"
        ))
        TOTPCodeView(config: TwoFactorConfig(
            type: .totp,
            secret: "KRSXG5BAONUGC4TFFY",
            issuer: "Microsoft",
            boundValue: "user@outlook.com"
        ))
    }
    .padding()
    .preferredColorScheme(.dark)
}
