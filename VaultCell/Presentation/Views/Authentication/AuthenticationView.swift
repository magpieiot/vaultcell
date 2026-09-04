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
/// 错峰入场动效；表单采用可见 label + 聚焦描边 + 内联错误；生物识别按钮以
/// 呼吸光效作为本页的 signature 元素，呼应"安全且鲜活"的品牌感受。
struct AuthenticationView: View {
    @EnvironmentObject var appState: AppState
    @State private var viewModel: AuthenticationViewModel?

    var body: some View {
        NavigationStack {
            AuthBackground()
                .overlay {
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 24)

                            AuthLogo(animate: true)

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
                viewModel = AuthenticationViewModel(appState: appState)
            }
        }
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

    @State private var floating: Bool = false
    @State private var appeared: Bool = false

    private let accent = Color.primaryBrandColor
    private let accent2 = Color.secondaryBrandColor

    var body: some View {
        VStack(spacing: 14) {
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
                    .frame(width: 180, height: 180)
                    .scaleEffect(floating ? 1.06 : 0.94)

                // 渐变主圆
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

                // 顶部高光
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)]),
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: 108, height: 108)
                    .mask(Circle().frame(width: 108, height: 108))

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            }
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: floating ? -5 : 5)

            VStack(spacing: 6) {
                Text("VaultCell")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(String(localized: "Securely store all your passwords"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: appeared ? 0 : 8)
        }
        .onAppear {
            guard animate else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }
}

// MARK: - 解锁视图

struct UnlockView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @FocusState private var focusedField: UnlockField?

    private enum UnlockField { case password }

    var body: some View {
        VStack(spacing: 22) {
            if viewModel.biometricType != .none {
                BiometricButton(biometricType: viewModel.biometricType) {
                    Task { await viewModel.authenticateWithBiometrics() }
                }

                DividerLabel(String(localized: "or use master password"))
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(String(localized: "Master Password"))
                AuthSecureField(
                    text: $viewModel.masterPassword,
                    placeholder: String(localized: "Enter master password"),
                    isFocused: focusedField == .password,
                    hasError: viewModel.errorMessage != nil
                )
                .focused($focusedField, equals: .password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { Task { await viewModel.unlock() } }
            }

            PrimaryActionButton(
                title: String(localized: "Unlock"),
                isLoading: viewModel.isLoading,
                isEnabled: viewModel.canUnlock
            ) {
                Task { await viewModel.unlock() }
            }

            if let error = viewModel.errorMessage {
                InlineError(error)
            }
        }
        .padding(.top, 36)
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

// MARK: - 创建保险库视图

struct CreateVaultView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @FocusState private var focusedField: CreateField?

    private enum CreateField { case newPassword, confirmPassword }

    var body: some View {
        VStack(spacing: 22) {
            // 安抚文案 + 不可找回提示
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(String(localized: "Your master password encrypts the entire vault and cannot be recovered. Please keep it safe."))
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
                FieldLabel(String(localized: "Create Master Password"))
                AuthSecureField(
                    text: $viewModel.newPassword,
                    placeholder: String(localized: "At least 8 characters"),
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
                FieldLabel(String(localized: "Confirm Master Password"))
                AuthSecureField(
                    text: $viewModel.confirmPassword,
                    placeholder: String(localized: "Re-enter master password"),
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
                title: String(localized: "Create Vault"),
                isLoading: viewModel.isLoading,
                isEnabled: viewModel.canCreateVault
            ) {
                Task { await viewModel.createVault() }
            }

            if !viewModel.validationError.isEmpty {
                InlineError(viewModel.validationError)
            }
            if let error = viewModel.errorMessage {
                InlineError(error)
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
        SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(.secondary.opacity(0.6)))
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

struct BiometricButton: View {
    let biometricType: BiometricType
    let action: () -> Void

    @State private var breathing: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    // 呼吸柔光晕
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    .primaryBrandColor.opacity(0.35),
                                    .primaryBrandColor.opacity(0)
                                ]),
                                center: .center,
                                startRadius: 24,
                                endRadius: 56
                            )
                        )
                        .frame(width: 112, height: 112)
                        .scaleEffect(breathing ? 1.12 : 0.92)
                        .opacity(breathing ? 0.9 : 0.4)

                    // 主圆
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.primaryBrandColor, .secondaryBrandColor]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .shadow(color: .primaryBrandColor.opacity(0.35), radius: 12, y: 8)

                    Image(systemName: biometricType.iconName)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("Use \(biometricType.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityLabel("Unlock with \(biometricType.displayName)")
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
                        .fill(isEnabled ? (index <= strength.rawValue ? strengthColor : Color.secondary.opacity(0.2)) : Color.secondary.opacity(0.2))
                        .frame(height: 6)
                }
            }
            HStack(spacing: 4) {
                Text(String(localized: "Strength"))
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

private extension PasswordStrength {
    var localizedName: String {
        switch self {
        case .veryWeak: return String(localized: "Very Weak")
        case .weak: return String(localized: "Weak")
        case .medium: return String(localized: "Medium")
        case .strong: return String(localized: "Strong")
        case .veryStrong: return String(localized: "Very Strong")
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
