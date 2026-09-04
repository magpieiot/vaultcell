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

    init() {
        // 启动时安装 Bundle swizzling
        AppLanguage.bootstrap()
    }
    
    var body: some Scene {
        WindowGroup {
            MainEntranceView()
                .applyAppLanguage()
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

struct MainEntranceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var languageManager: AppLanguageManager
    @AppStorage(VaultKey.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @AppStorage(VaultKey.hasSeenVaultSetupGuide) private var hasSeenVaultSetupGuide: Bool = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
                .transition(.opacity)
            } else if appState.isAuthenticated && !appState.isLocked {
                if !hasSeenVaultSetupGuide && VaultSetupGate.isVaultEmpty {
                    // 密码库就绪引导：创建密码库后的一次性决策点（新建 / 导入 / 恢复备份）
                    VaultSetupView {
                        hasSeenVaultSetupGuide = true
                    }
                    .transition(.opacity)
                } else {
                    MainTabView()
                }
            } else {
                AuthenticationView()
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
        .animation(.easeInOut(duration: 0.2), value: appState.shouldShowPrivacyOverlay)
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
