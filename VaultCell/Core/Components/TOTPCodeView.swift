/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// TOTPCodeView.swift
/// created on: 27/06/2026
/// ------------------------------------------------------------------

import SwiftUI

/// TOTP 验证码显示控件
/// 根据 TwoFactorConfig 中的密钥、算法、位数与周期实时生成验证码。
/// 默认显示倒计时进度环；列表中多个条目共用指示器时可传 `showsProgressRing: false` 关闭。
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

    /// 是否显示倒计时进度环；列表中所有验证码共用一个指示器时传 false
    var showsProgressRing: Bool = true

    @State private var result: TOTPResult?
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            codeDisplay
            if showsProgressRing {
                progressRing
            }
            
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
        TOTPProgressRing(
            progress: progressValue,
            remainingSeconds: result?.remainingSeconds ?? 0
        )
    }

    private var progressValue: CGFloat {
        guard let result else { return 0 }
        return 1.0 - CGFloat(result.progress)
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

// MARK: - 可复用的倒计时进度环

/// TOTP 倒计时环：既可由单条验证码使用，也可由列表顶部的共享指示器复用。
/// - `progress`：已过去的周期比例（0 ~ 1）
/// - `remainingSeconds`：距下次刷新的秒数；0 表示尚无有效数据
struct TOTPProgressRing: View {
    let progress: CGFloat
    let remainingSeconds: Int
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: ringColors, center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)

            Text("\(remainingSeconds)")
                .font(.system(.headline, design: .monospaced).bold())
                .foregroundColor(ringTextColor)
        }
        .frame(width: size, height: size)
    }

    private var ringColors: [Color] {
        guard remainingSeconds > 0 else { return [Color.appAccent] }
        // 最后 5 秒用语义色提醒，其余时间保持单一强调色
        return remainingSeconds <= 5 ? [Color.errorColor] : [Color.appAccent]
    }

    private var ringTextColor: Color {
        guard remainingSeconds > 0 else { return .secondary }
        return remainingSeconds <= 5 ? Color.errorColor : .primary
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
