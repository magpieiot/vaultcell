/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// OnboardingView.swift
/// created on: 12/08/2026
/// ------------------------------------------------------------------

import SwiftUI

// MARK: - Onboarding 数据模型

/// 单页引导内容
struct OnboardingPage: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let subtitle: String
    let description: String
    let accent: Color
    let accentLight: Color
}

// MARK: - Onboarding 主视图

/// 首次启动引导界面
///
/// 设计语言：清新、优雅 —— 采用浅色 airy 背景、柔和渐变图标、精致排版与流畅动效，
/// 与后续深色认证页形成舒缓过渡。
struct OnboardingView: View {
    /// 引导完成回调，由父视图持久化标记并切换到认证页
    let onComplete: () -> Void
    /// 冷启动接力：welcome=首启长停留（含欢迎语），brief=短停留；nil=无接力直接显示引导
    var launchRelay: LaunchRelayKind? = nil
    /// 接力换场完成回调（父级据此消耗一次性接力标记）
    var onRelayFinished: (() -> Void)? = nil

    /// 接力阶段：0=启动屏姿态（纯色底 + 居中 Logo），1=正常引导内容
    @State private var relayStage: Int
    @State private var relayScheduled: Bool = false
    @State private var welcomeVisible: Bool = false

    init(launchRelay: LaunchRelayKind? = nil, onRelayFinished: (() -> Void)? = nil, onComplete: @escaping () -> Void) {
        self.launchRelay = launchRelay
        self.onRelayFinished = onRelayFinished
        self.onComplete = onComplete
        _relayStage = State(initialValue: launchRelay == nil ? 1 : 0)
    }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "lock.shield.fill",
            title: AppLocale.string("Welcome to VaultCell"),
            subtitle: AppLocale.string("Your Pocket Password Vault"),
            description: AppLocale.string("Keep your passwords, bank cards, secure notes and verification codes in one safe place."),
            accent: Color(red: 0.25, green: 0.60, blue: 1.00),
            accentLight: Color(red: 0.85, green: 0.93, blue: 1.00)
        ),
        OnboardingPage(
            symbol: "key.horizontal.fill",
            title: AppLocale.string("End-to-End Encryption"),
            subtitle: AppLocale.string("Zero-Knowledge · Local First"),
            description: AppLocale.string("AES-256-GCM authenticated encryption with Secure Enclave isolation. Your master key never touches disk."),
            accent: Color(red: 0.30, green: 0.78, blue: 0.68),
            accentLight: Color(red: 0.85, green: 0.96, blue: 0.93)
        ),
        OnboardingPage(
            symbol: "wand.and.stars",
            title: AppLocale.string("One-Tap Autofill & Generate"),
            subtitle: AppLocale.string("System-wide Autofill"),
            description: AppLocale.string("Autofill credentials in Safari and third-party apps, with a built-in strong password generator."),
            accent: Color(red: 0.55, green: 0.50, blue: 0.95),
            accentLight: Color(red: 0.92, green: 0.90, blue: 1.00)
        ),
        OnboardingPage(
            symbol: "badge.checkmark.fill",
            title: AppLocale.string("Verification Codes & Security Audit"),
            subtitle: AppLocale.string("TOTP · 2FA Health Check"),
            description: AppLocale.string("Scan and import TOTP codes, manage two-factor authentication, and get security audit reports anytime."),
            accent: Color(red: 0.98, green: 0.55, blue: 0.40),
            accentLight: Color(red: 1.00, green: 0.92, blue: 0.88)
        ),
    ]

    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            // 动态柔和背景：随当前页强调色微微晕染
            OnboardingBackground(accent: pages[currentIndex].accentLight)

            VStack(spacing: 0) {
                // 顶部跳过按钮
                HStack {
                    Spacer()
                    if currentIndex < pages.count - 1 {
                        Button {
                            complete()
                        } label: {
                            Text("Skip")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.top, 8)

                // 分页内容
                TabView(selection: $currentIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPageView(page: page, isActive: index == currentIndex)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // 底部控制区
                VStack(spacing: 28) {
                    OnboardingPageControl(
                        count: pages.count,
                        current: currentIndex,
                        tint: pages[currentIndex].accent
                    )

                    OnboardingActionButton(
                        isLast: currentIndex == pages.count - 1,
                        accent: pages[currentIndex].accent,
                        action: {
                            if currentIndex < pages.count - 1 {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                    currentIndex += 1
                                }
                            } else {
                                complete()
                            }
                        }
                    )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }
            // 接力姿态下引导内容保持布局但不可见，换场后淡入
            .opacity(relayStage == 1 ? 1 : 0)
            .allowsHitTesting(relayStage == 1)

            // 接力首帧：与系统启动屏一致的画面，welcome 模式追加欢迎语
            if relayStage == 0 {
                launchCard
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentIndex)
        .onAppear(perform: scheduleRelayIfNeeded)
    }

    /// 接力首帧：与系统启动屏逐像素一致（纯色底 + 居中 180pt Logo），
    /// welcome 模式下 Logo 下方淡入欢迎语与 Slogan；停留后整体溶解换场到引导内容
    private var launchCard: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 20) {
                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                if launchRelay == .welcome {
                    VStack(spacing: 8) {
                        Text("Welcome to VaultCell")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Securely store all your passwords")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .opacity(welcomeVisible ? 1 : 0)
                }
            }
        }
    }

    private func scheduleRelayIfNeeded() {
        guard launchRelay != nil, !relayScheduled else { return }
        relayScheduled = true
        let holdNanoseconds: UInt64 = launchRelay == .welcome ? 2_000_000_000 : 120_000_000
        if launchRelay == .welcome {
            withAnimation(.easeIn(duration: 0.5).delay(0.2)) {
                welcomeVisible = true
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: holdNanoseconds)
            withAnimation(.easeInOut(duration: 0.5)) {
                relayStage = 1
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            onRelayFinished?()
        }
    }

    private func complete() {
        withAnimation(.easeInOut(duration: 0.4)) {
            onComplete()
        }
    }
}

// MARK: - 单页内容

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool

    @State private var iconAppeared: Bool = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)

            // 渐变图标
            OnboardingIcon(
                symbol: page.symbol,
                accent: page.accent,
                accentLight: page.accentLight,
                animate: isActive
            )
            .scaleEffect(iconAppeared ? 1.0 : 0.8)
            .opacity(iconAppeared ? 1.0 : 0.0)

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(page.accent)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 8)
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .onChange(of: isActive) { _, active in
            if active {
                iconAppeared = false
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    iconAppeared = true
                }
            }
        }
        .onAppear {
            if isActive {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15)) {
                    iconAppeared = true
                }
            }
        }
    }
}

// MARK: - 渐变图标

private struct OnboardingIcon: View {
    let symbol: String
    let accent: Color
    let accentLight: Color
    let animate: Bool

    @State private var floating: Bool = false

    var body: some View {
        ZStack {
            // 外层柔光晕
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [accentLight, accentLight.opacity(0)]),
                        center: .center,
                        startRadius: 60,
                        endRadius: 150
                    )
                )
                .frame(width: 220, height: 220)
                .scaleEffect(floating ? 1.05 : 0.95)

            // 渐变主圆
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [accent, accent.opacity(0.82)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .shadow(color: accent.opacity(0.35), radius: 20, y: 12)

            // 高光
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)]),
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: 140, height: 140)
                .mask(Circle().frame(width: 140, height: 140))

            Image(systemName: symbol)
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .offset(y: floating ? -6 : 6)
        .onAppear {
            guard animate else { return }
            startFloating()
        }
        .onChange(of: animate) { _, active in
            if active { startFloating() }
        }
    }

    private func startFloating() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            floating = true
        }
    }
}

// MARK: - 页面指示器

private struct OnboardingPageControl: View {
    let count: Int
    let current: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? tint : Color.secondary.opacity(0.25))
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

// MARK: - 操作按钮

private struct OnboardingActionButton: View {
    let isLast: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLast {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(isLast ? "Get Started" : "Continue")
                    .font(.headline)
                if !isLast {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [accent, accent.opacity(0.85)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: accent.opacity(0.4), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isLast)
    }
}

// MARK: - 柔和背景

private struct OnboardingBackground: View {
    let accent: Color

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.99, green: 0.995, blue: 1.0),
                accent.opacity(0.55),
                accent.opacity(0.25),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: accent)
    }
}

// MARK: - 预览

#Preview("Onboarding") {
    OnboardingView(onComplete: {})
}
