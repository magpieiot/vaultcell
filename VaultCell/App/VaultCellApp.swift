/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// VaultCellApp.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI

@main
struct VaultCellApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var languageManager = AppLanguageManager.shared
    /// 外观模式：设置页写入，这里应用到整棵视图树（.system 时 colorScheme 为 nil，回退系统设置）
    @AppStorage(VaultKey.appearanceMode) private var appearanceMode: AppAppearance = .system

    init() {
        // 启动时安装 Bundle swizzling
        AppLanguage.bootstrap()
    }
    
    var body: some Scene {
        WindowGroup {
            MainEntranceView()
                .applyAppLanguage()
                // 外观模式在根视图统一施加：切换浅色 / 深色 / 跟随系统时整窗即时刷新
                .preferredColorScheme(appearanceMode.colorScheme)
                .environmentObject(appState)
                .environmentObject(languageManager)
                .onContinueUserActivity("ASCredentialExchangeActivity") { activity in
                    // Credential Exchange 导入入口：仅 iOS 26+ 系统会将
                    // ASCredentialExchangeActivity 路由到本 App；
                    // 部署目标为 iOS 17 时该分支在运行时不会真正执行。
                    Task {
                        guard #available(iOS 26, *) else { return }
                        do {
                            let token = try CredentialExchangeService.importToken(from: activity)
                            let data = try await CredentialExchangeService.importCredentials(token: token)
                            // data.accounts 即导入的凭据集合，映射为 PasswordEntry 入库
                            let result = try await CredentialExchangeService.ingest(data)
                            print("Credential Exchange 导入完成：新建 \(result.created) 条，更新 \(result.updated) 条")
                            // 通知密码列表重新加载（列表视图监听该通知名即可刷新）
                            await MainActor.run {
                                NotificationCenter.default.post(
                                    name: .credentialExchangeDidImport,
                                    object: nil
                                )
                            }
                        } catch {
                            // TODO: 接入统一的错误上报/提示
                            print("Credential Exchange 导入失败: \(error.localizedDescription)")
                        }
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }
    
    @Environment(\.scenePhase) private var scenePhase
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            appState.handleAppBecameActive()
        case .inactive:
            appState.handleAppBecameInactive()
        case .background:
            appState.handleAppEnteredBackground()
        @unknown default:
            break
        }
    }
}

/// 冷启动接力类型：welcome=首次运行（1#，欢迎语长停留），brief=之后运行（2#，Logo 快速归位）
enum LaunchRelayKind {
    case welcome
    case brief
}


struct MainEntranceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var languageManager: AppLanguageManager
    @AppStorage(VaultKey.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @AppStorage(VaultKey.hasSeenVaultSetupGuide) private var hasSeenVaultSetupGuide: Bool = false
    @AppStorage(VaultKey.hasSeenIconDisclosure) private var hasSeenIconDisclosure: Bool = false
    /// 冷启动一次性接力标记，由真实首屏（引导页/认证页）消费；接力完成后置 nil 防重复触发
    @State private var launchRelay: LaunchRelayKind? = UserDefaults.hasSeenWelcomeSplash ? .brief : .welcome

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView(launchRelay: launchRelay, onRelayFinished: finishLaunchRelay) {
                    hasCompletedOnboarding = true
                }
                .transition(.opacity)
            } else if appState.isAuthenticated && !appState.isLocked {
                if appState.showsCloudRestoreFlow {
                    CloudVaultRestoreView()
                        .transition(.opacity)
                } else if !hasSeenVaultSetupGuide && VaultSetupGate.isVaultEmpty {
                    // 密码库就绪引导：创建密码库后的一次性决策点（新建 / 导入 / 恢复备份）
                    VaultSetupView {
                        hasSeenVaultSetupGuide = true
                    }
                    .transition(.opacity)
                } else {
                    MainTabView()
                }
            } else {
                AuthenticationView(launchRelay: launchRelay != nil, onRelayFinished: finishLaunchRelay)
            }
        }
        // 快照保护：App 进入非活跃状态时覆盖半透明遮罩，防止后台快照泄露敏感信息
        .overlay(alignment: .center) {
            if appState.shouldShowPrivacyOverlay {
                PrivacyOverlayView()
            } else {
                EmptyView()
            }
        }
        // 冷启动接力由真实首屏自行呈现（单视图接力，无双份渲染，几何天然正确）
        // 首启一次性告知：远程图标会直连目标站点，先把事实讲清楚
        // 开关已关闭时不再打扰——不抓取就没有请求，也就没有告知的必要
        .alert(
            AppLocale.string("Website Icons"),
            isPresented: Binding(
                get: { !hasSeenIconDisclosure && IconPreferences.isAutoFetchEnabled },
                set: { presented in
                    if !presented { hasSeenIconDisclosure = true }
                }
            )
        ) {
            Button(AppLocale.string("OK")) {
                hasSeenIconDisclosure = true
            }
            Button(AppLocale.string("Turn Off Icons"), role: .destructive) {
                IconPreferences.isAutoFetchEnabled = false
                hasSeenIconDisclosure = true
            }
        } message: {
            Text(
                AppLocale.string("VaultCell shows a site icon by requesting apple-touch-icon.png or favicon.ico directly from that site. That request reveals your IP address and the site you are visiting. Built-in icons for common apps send no request, and you can turn this off anytime in Settings."
                ))
        }
        .animation(.easeInOut(duration: 0.2), value: appState.shouldShowPrivacyOverlay)
    }

    /// 接力完成回调：欢迎接力（1#）落盘一次性标记，并消耗接力状态防止后续页面重复触发
    private func finishLaunchRelay() {
        if launchRelay == .welcome {
            UserDefaults.hasSeenWelcomeSplash = true
        }
        launchRelay = nil
    }
}

/// 根据当前选择为视图树注入语言环境；切换语言时 SwiftUI 会重算 modifier 并刷新整棵子树。
struct AppLanguageEnvironmentModifier: ViewModifier {
    @EnvironmentObject var languageManager: AppLanguageManager

    func body(content: Content) -> some View {
        if let id = languageManager.current.bcp47 {
            content.environment(\.locale, Locale(identifier: id))
        } else {
            content
        }
    }
}

extension View {
    func applyAppLanguage() -> some View {
        modifier(AppLanguageEnvironmentModifier())
    }
}
