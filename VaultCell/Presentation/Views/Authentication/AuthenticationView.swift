/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AuthenticationView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 认证页
///
/// 设计语言：清新、优雅 —— 与 Onboarding 共享浅色 airy 背景、渐变品牌图标与
/// 错峰入场动效；表单采用可见 label + 聚焦描边，失败原因（如主密码错误）以 toast 呈现；
/// 生物识别按钮改用品牌色线性图标 + 淡呼吸光效，避免与上方的品牌图标同构，呼应"安全且鲜活"的品牌感受。
struct AuthenticationView: View {
    @EnvironmentObject var appState: AppState
    /// 本页的 toast 中心：认证页没有 MainTabView 的环境对象，这里自行持有一份
    @StateObject private var toastCenter = ToastCenter()
    @State private var viewModel: AuthenticationViewModel?

    /// 冷启动接力：true 时品牌 Logo 先以系统启动屏姿态（180pt、屏幕居中）呈现，随后原地归位
    var launchRelay: Bool = false
    /// 接力归位完成回调（父级据此消耗一次性接力标记）
    var onRelayFinished: (() -> Void)? = nil

    /// 接力是否已归位；非接力模式恒为 true（不影响原有呈现）
    @State private var relaySettled: Bool

    init(launchRelay: Bool = false, onRelayFinished: (() -> Void)? = nil) {
        self.launchRelay = launchRelay
        self.onRelayFinished = onRelayFinished
        _relaySettled = State(initialValue: !launchRelay)
    }

    var body: some View {
        NavigationStack {
            AuthBackground()
                .overlay {
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 24)

                            AuthLogo(animate: true, relaySettled: launchRelay ? $relaySettled : nil)

                            Group {
                                if let viewModel {
                                    if viewModel.hasExistingVault {
                                        UnlockView(viewModel: viewModel)
                                    } else {
                                        CreateVaultView(viewModel: viewModel)
                                    }
                                } else {
                                    // 占位，避免首帧高度跳变
                                    Color.clear.frame(height: 280)
                                }
                            }
                            // 接力姿态下表单区保持布局但不可见，归位后淡入
                            .opacity(relaySettled ? 1 : 0)
                            .allowsHitTesting(relaySettled)

                            Spacer(minLength: 24)
                        }
                        .padding(.horizontal, 28)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: UIScreen.main.bounds.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if viewModel == nil {
                viewModel = AuthenticationViewModel(appState: appState, toastCenter: toastCenter)
            }
        }
        .onChange(of: relaySettled) { _, settled in
            if settled { onRelayFinished?() }
        }
        // 主密码错误等失败提示统一以 toast 呈现
        .toast($toastCenter.toast)
    }
}

// MARK: - 浅色柔和背景

/// 与 Onboarding 共享语言的浅色背景：近白底 + 品牌色顶部晕染
struct AuthBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.99, green: 0.995, blue: 1.0),
                Color.primaryBrandColor.opacity(0.18),
                Color.secondaryBrandColor.opacity(0.12),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - 品牌图标

/// 渐变圆 + 高光 + 柔光晕 + 浮动动画，复用 Onboarding 图标语言
struct AuthLogo: View {
    let animate: Bool
    /// 冷启动接力绑定：非 nil 时 Logo 先以系统启动屏姿态（180pt、屏幕居中、无光晕与文字）
    /// 呈现，绑定翻转为 true 后归位，光晕与文字淡入；nil 时行为与原先一致
    var relaySettled: Binding<Bool>? = nil

    @State private var floating: Bool = false
    @State private var appeared: Bool = false
    /// 接力模式下 Logo 布局中心的屏幕 y 坐标（用于计算平移到屏幕正中的偏移量）
    /// 初值取约 0.3 屏高（认证页 Logo 的典型位置），避免首帧大跳变
    @State private var logoMidY: CGFloat = UIScreen.main.bounds.height * 0.3
    @State private var relayScheduled: Bool = false

    private let accent = Color.primaryBrandColor
    private let accent2 = Color.secondaryBrandColor

    /// 系统启动屏 LaunchIcon 的固有尺寸
    private let launchLogoSide: CGFloat = 180
    private let logoSide: CGFloat = 108

    /// 是否处于接力姿态（Logo 居中放大、无光晕、无文字）
    private var isRelaying: Bool {
        guard let relaySettled else { return false }
        return !relaySettled.wrappedValue
    }

    var body: some View {
        VStack(spacing: 14) {
            // 测量替身：占据布局位置但自身不做任何变换。
            // 对被 offset 的视图直接做 frame(in: .global) 测量会把偏移量计入结果，
            // 形成"偏移→测量→再偏移"的逐帧反馈循环，必须用替身隔离
            Color.clear
                .frame(width: 240, height: 240)
                .onGeometryChange(for: CGFloat.self, of: { proxy in
                    proxy.frame(in: .global).midY
                }, action: { newValue in
                    logoMidY = newValue
                })
                .overlay {
                    ZStack {
                        // 外层柔光晕

                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [accent.opacity(0.35), accent.opacity(0)]),
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 120
                                )
                            )
                            .frame(width: 240, height: 240)
                            .scaleEffect(floating ? 1.06 : 0.94)
                            // 接力姿态下隐藏光晕，与系统启动屏保持一致
                            .opacity(isRelaying ? 0 : 1)

                        // 渐变主圆
                        /*
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [accent, accent2]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 108, height: 108)
                            .shadow(color: accent.opacity(0.35), radius: 18, y: 12)
                         */

                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 108, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

                        // 顶部高光
                        /*
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.45), Color.white.opacity(0),
                                    ]),
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(width: 128, height: 128)
                            .mask(Circle().frame(width: 128, height: 128))
                         */

                    }
                    .scaleEffect(isRelaying ? launchLogoSide / logoSide : (appeared ? 1.0 : 0.85))
                    .opacity(appeared ? 1.0 : 0.0)
                    .offset(y: (isRelaying ? UIScreen.main.bounds.height / 2 - logoMidY : 0) + (floating ? -5 : 5))
                }

            VStack(spacing: 6) {
                Text("VaultCell")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(AppLocale.string("Securely store all your passwords"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .opacity(isRelaying ? 0 : (appeared ? 1.0 : 0.0))
            .offset(y: appeared ? 0 : 8)
        }
        .onAppear(perform: handleAppear)
    }

    private func handleAppear() {
        // 接力模式：Logo 直接以可见态出现（衔接系统启动屏），短暂停留后归位
        if relaySettled != nil {
            appeared = true
            guard !relayScheduled else { return }
            relayScheduled = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    relaySettled?.wrappedValue = true
                }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    floating = true
                }
            }
            return
        }
        guard animate else { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
            appeared = true
        }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            floating = true
        }
    }
}

// MARK: - 解锁视图

struct UnlockView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    /// 直接订阅 AppState：冷却倒计时每秒由它推送，
    /// 若改从 viewModel 转一手（VM 里只是普通强引用），就收不到刷新、只剩打字时才动
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedField: UnlockField?

    private enum UnlockField { case password }

    var body: some View {
        VStack(spacing: 22) {
            if viewModel.biometricType != .none {
                BiometricButton(biometricType: viewModel.biometricType) {
                    Task { await viewModel.authenticateWithBiometrics() }
                }

                DividerLabel(AppLocale.string("or use master password"))
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(AppLocale.string("Master Password"))
                AuthSecureField(
                    text: $viewModel.masterPassword,
                    placeholder: AppLocale.string("Enter master password"),
                    isFocused: focusedField == .password,
                    hasError: viewModel.errorMessage != nil
                )
                .focused($focusedField, equals: .password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { Task { await viewModel.unlock() } }
            }

            if appState.unlockCooldownRemaining > 0 {
                UnlockCooldownNotice(remaining: appState.unlockCooldownRemaining)
            }

            PrimaryActionButton(
                title: AppLocale.string("Unlock"),
                isLoading: viewModel.isLoading,
                isEnabled: viewModel.canUnlock
            ) {
                Task { await viewModel.unlock() }
            }
        }
        .padding(.top, 36)
        .onChange(of: viewModel.masterPassword) { _, _ in
            // 一旦重新输入就解除错误态：toast 消失后不该还留着红框
            viewModel.clearError()
        }
        .onAppear {
            // 有生物识别时不抢焦点；无生物识别时自动聚焦密码框
            if viewModel.biometricType == .none {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .password
                }
            }
        }
    }
}

// MARK: - 创建密码库视图

struct CreateVaultView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @FocusState private var focusedField: CreateField?

    private enum CreateField { case newPassword, confirmPassword }

    var body: some View {
        VStack(spacing: 22) {
            // 安抚文案 + 不可找回提示
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(
                        AppLocale.string("Your master password encrypts the entire vault and cannot be recovered. Please keep it safe."
                        )
                    )
                    .font(.subheadline)
                    .foregroundColor(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.warningColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.warningColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(AppLocale.string("Create Master Password"))
                AuthSecureField(
                    text: $viewModel.newPassword,
                    placeholder: AppLocale.string("At least 8 characters"),
                    isFocused: focusedField == .newPassword,
                    hasError: !viewModel.validationError.isEmpty
                )
                .focused($focusedField, equals: .newPassword)
                // 不使用 .newPassword：避免输入法键盘弹出强密码建议，主密码应由用户自行设定
                .textContentType(.oneTimeCode)
                .submitLabel(.next)
                .onSubmit { focusedField = .confirmPassword }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(AppLocale.string("Confirm Master Password"))
                AuthSecureField(
                    text: $viewModel.confirmPassword,
                    placeholder: AppLocale.string("Re-enter master password"),
                    isFocused: focusedField == .confirmPassword,
                    hasError: !viewModel.validationError.isEmpty
                )
                .focused($focusedField, equals: .confirmPassword)
                // 同创建密码框：禁用键盘密码建议
                .textContentType(.oneTimeCode)
                .submitLabel(.go)
                .onSubmit { Task { await viewModel.createVault() } }
            }

            // 密码强度：彩条 + 文字标签（非仅靠颜色）
            if !viewModel.newPassword.isEmpty {
                PasswordStrengthIndicator(strength: viewModel.passwordStrength)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !viewModel.passwordHint.isEmpty {
                InlineHint(viewModel.passwordHint)
            }

            PrimaryActionButton(
                title: AppLocale.string("Create Vault"),
                isLoading: viewModel.isLoading,
                isEnabled: viewModel.canCreateVault && !viewModel.isLoading
            ) {
                Task { await viewModel.createVault() }
            }

            Button {
                Task { await viewModel.restoreFromICloud() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "icloud.and.arrow.down")
                    }
                    Text(AppLocale.string("Restore from iCloud"))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.primaryBrandColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.primaryBrandColor.opacity(0.08))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            if !viewModel.validationError.isEmpty {
                InlineError(viewModel.validationError)
            }
        }
        .padding(.top, 28)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .newPassword
            }
        }
    }
}

// MARK: - 字段标签

private struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundColor(.secondary)
    }
}

// MARK: - 安全输入框

/// 带可见 label 与聚焦描边的安全输入框
struct AuthSecureField: View {
    @Binding var text: String
    let placeholder: String
    let isFocused: Bool
    let hasError: Bool

    var body: some View {
        SecureField(
            "", text: $text, prompt: Text(placeholder).foregroundColor(.secondary.opacity(0.6))
        )
        .font(.body)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
        }
        .foregroundStyle(.primary)
        .tint(.primaryBrandColor)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .animation(.easeInOut(duration: 0.2), value: hasError)
    }

    private var borderColor: Color {
        if hasError { return .errorColor }
        if isFocused { return .primaryBrandColor }
        return Color.secondary.opacity(0.2)
    }
}

// MARK: - 主操作按钮

/// 品牌色渐变主按钮，带柔和投影与可感知的禁用态
struct PrimaryActionButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.primaryBrandColor, .secondaryBrandColor]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: .primaryBrandColor.opacity(isEnabled ? 0.35 : 0), radius: 12, y: 8)
            .opacity(isEnabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.25), value: isEnabled)
        .animation(.easeInOut(duration: 0.25), value: isLoading)
    }
}

// MARK: - 生物识别按钮（signature：呼吸光效）

/// 线性图标按钮：与品牌图标（蓝色填充块）形成层级区分
///
/// 页面里唯一的大面积品牌色应属于 `AuthLogo`，因此这里不再使用填充圆 + 白色图形，
/// 而是直接以品牌色渲染 SF Symbol，呼吸光效也压到极淡，只作为身份提示的 signature。
struct BiometricButton: View {
    let biometricType: BiometricType
    let action: () -> Void

    @State private var breathing: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    // 极淡的呼吸氛围光（保留 signature，不与 Logo 的光晕抢戏）
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    .primaryBrandColor.opacity(0.18),
                                    .primaryBrandColor.opacity(0),
                                ]),
                                center: .center,
                                startRadius: 20,
                                endRadius: 62
                            )
                        )
                        .frame(width: 124, height: 124)
                        .scaleEffect(breathing ? 1.08 : 0.94)
                        .opacity(breathing ? 0.9 : 0.45)

                    // 品牌色线性图形：与 Logo 的"填充 + 白色图形"明确区分
                    Image(systemName: biometricType.iconName)
                        .font(.system(size: 48, weight: .regular))
                        .foregroundColor(.primaryBrandColor)
                        .scaleEffect(breathing ? 1.04 : 1.0)
                }
                // 保证最小可点击区域不小于 44pt
                .frame(minWidth: 76, minHeight: 76)

                Text("Use \(biometricType.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BiometricButtonStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityLabel("Unlock with \(biometricType.displayName)")
    }
}

/// 按下时轻微缩放，提供可感知的点击反馈
private struct BiometricButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 分隔标签

private struct DividerLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 12) {
            line
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
            line
        }
        .padding(.vertical, 2)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: 1)
    }
}

// MARK: - 内联提示与错误

private struct InlineHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.caption)
            .foregroundColor(.warningColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineError: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.errorColor)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 解锁冷却提示：说明 + 倒计时
///
/// 倒计时单独成块，避开"数字插在句子中间"的语序问题（中文要说"30 秒后重试"，英文是"in 30s"）。
private struct UnlockCooldownNotice: View {
    let remaining: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.footnote)
            Text(AppLocale.string("Too many attempts"))
                .font(.footnote)
            Spacer(minLength: 0)
            Text(verbatim: Self.countdownText(remaining))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.warningColor.opacity(0.14))
                .clipShape(Capsule())
        }
        .foregroundColor(.warningColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 剩余时间：不足 1 分钟直接显示秒数，否则按 分:秒
    private static func countdownText(_ remaining: TimeInterval) -> String {
        let total = Int(ceil(remaining))
        guard total >= 60 else { return "\(total)s" }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 密码强度指示器（彩条 + 文字标签）

struct PasswordStrengthIndicator: View {
    let strength: PasswordStrength
    /// 是否可用：为 false 时（如密码为空）胶囊与文字全部置灰
    var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(
                            isEnabled
                                ? (index <= strength.rawValue
                                    ? strengthColor : Color.secondary.opacity(0.2))
                                : Color.secondary.opacity(0.2)
                        )
                        .frame(height: 6)
                }
            }
            HStack(spacing: 4) {
                Text(AppLocale.string("Strength"))
                    .foregroundColor(.secondary)
                Text(strength.localizedName)
                    .foregroundColor(isEnabled ? strengthColor : .secondary)
                    .fontWeight(.semibold)
            }
            .font(.caption)
        }
    }

    private var strengthColor: Color {
        switch strength {
        case .veryWeak, .weak: return .errorColor
        case .medium: return .warningColor
        case .strong, .veryStrong: return .successColor
        }
    }
}

// MARK: - PasswordStrength 本地化

extension PasswordStrength {
    fileprivate var localizedName: String {
        switch self {
        case .veryWeak: return AppLocale.string("Very Weak")
        case .weak: return AppLocale.string("Weak")
        case .medium: return AppLocale.string("Medium")
        case .strong: return AppLocale.string("Strong")
        case .veryStrong: return AppLocale.string("Very Strong")
        }
    }
}

// MARK: - 预览

#Preview("Unlock") {
    AuthenticationView()
        .environmentObject(AppState())
}

#Preview("Strength") {
    VStack {
        PasswordStrengthIndicator(strength: .weak)
        PasswordStrengthIndicator(strength: .medium)
        PasswordStrengthIndicator(strength: .veryStrong)
    }
    .padding()
}
