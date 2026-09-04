/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// MainTabView.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import SwiftUI

/// TabBar 可见性 PreferenceKey
/// 子页面设置 `true` 时隐藏 TabBar，视图消失后自动恢复默认值 `false`
struct TabBarVisibilityKey: PreferenceKey {
    static var defaultValue: Bool { false }
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// 主页 Tab 枚举
enum MainTab: String, CaseIterable {

    case totp = "totp"
    case vault = "vault"
    case notes = "notes"
    case people = "people"

    var icon: String {
        switch self {
        case .totp: return "key.viewfinder"
        case .vault: return "lock.shield"
        case .notes: return "document"
        case .people: return "gearshape"
        }
    }

    var title: LocalizedStringKey? {
        switch self {
        case .totp: return nil
        case .vault: return "Vault"
        case .notes: return "Notes"
        case .people: return nil
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var referenceData: ReferenceDataService
    @StateObject private var vaultListViewModel: VaultListViewModel
    @StateObject private var passwordGeneratorService = PasswordGeneratorService()
    @StateObject private var twoFactorService = TwoFactorService()
    @StateObject private var toastCenter = ToastCenter()
    @StateObject private var safeNoteService = SafeNoteVaultService()

    @State private var activeTab: MainTab = .vault
    @State private var isPresentingNoteEditor: Bool = false
    @State private var isTabBarHidden: Bool = false

    init() {
        let referenceData = ReferenceDataService()
        self._referenceData = StateObject(wrappedValue: referenceData)
        self._vaultListViewModel = StateObject(
            wrappedValue: VaultListViewModel(referenceData: referenceData)
        )
    }

    var body: some View {
        TabView(selection: $activeTab) {
            VaultListView()  //viewModel: vaultListViewModel)
                /*
                .tabItem {
                    Label("Vault", systemImage: "lock.fill")
                }
                */
            .tag(MainTab.vault)
                .toolbar(.hidden, for: .tabBar)

            SafeNotesListView(service: safeNoteService)
                /*
                .tabItem {
                    Label("Notes", systemImage: "document")
                }
                */
            .tag(MainTab.notes)
                .toolbar(.hidden, for: .tabBar)

            TwoFactorListView(viewModel: vaultListViewModel, twoFactorService: twoFactorService)
                /*
                .tabItem {
                    Label("TOTP", systemImage: "key.viewfinder")
                }
                */
            .tag(MainTab.totp)
                .toolbar(.hidden, for: .tabBar)

            //CustomDrawerView(hidesTabBar: false)
            SettingsView()
                /*
                .tabItem {
                    Label("Generator", systemImage: "sparkles")
                }
                */
            .tag(MainTab.people)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom) {
            if !isTabBarHidden {
                CustomTabBar(activeTab: $activeTab) {
                    // Add 按钮点击：根据当前 tab 跳转对应的新增页面
                    switch activeTab {
                    case .totp, .vault, .people:
                        vaultListViewModel.isPresentingAddFlow = true
                    case .notes:
                        isPresentingNoteEditor = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, -12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(TabBarVisibilityKey.self) { isHidden in
            withAnimation(.easeInOut(duration: 0.25)) {
                isTabBarHidden = isHidden
            }
        }
        .fullScreenCover(isPresented: $vaultListViewModel.isPresentingAddFlow) {
            NavigationStack {
                CreateNewItemView(viewModel: vaultListViewModel, toastCenter: toastCenter)
            }
        }
        .sheet(isPresented: $isPresentingNoteEditor) {
            EditSafeNoteView(
                viewModel: SafeNoteEditorViewModel(
                    service: safeNoteService
                )
            )
        }
        .onChange(of: isPresentingNoteEditor) { _, isPresented in
            // 编辑页关闭后刷新安全笔记列表
            if !isPresented {
                Task {
                    await safeNoteService.reloadAll()
                }
            }
        }
        .environmentObject(appState)
        .environmentObject(toastCenter)
        .environmentObject(vaultListViewModel)
        .environmentObject(safeNoteService)
        .toast($toastCenter.toast)
        .tint(.blue)
        .onAppear {
            Task {
                // 启动时执行懒清理：物理删除超过 30 天保留期的回收站条目
                await vaultListViewModel.purgeExpired()
                _ = await safeNoteService.purgeExpiredNotes(retentionDays: 30)
                await vaultListViewModel.loadItems()
            }
        }
    }
}

struct CustomTabBar: View {
    @Binding var activeTab: MainTab
    let onAddTap: () -> Void
    @EnvironmentObject private var languageManager: AppLanguageManager

    var body: some View {
        HStack(spacing: 12) {

            // 让语言状态变化触发 TabBar 重新计算标题。
            let _ = languageManager.current

            tabButton(for: MainTab.totp)
            tabButton(for: MainTab.vault)
            // 中间的 Add 按钮（FAB 风格）
            Button(action: onAddTap) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isAddButtonVisible ? Color.blue : Color.gray.opacity(0.5))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                            )
                    )
            }
            .disabled(!isAddButtonVisible)
            .opacity(isAddButtonVisible ? 1 : 0.6)
            .animation(.easeInOut(duration: 0.2), value: activeTab)

            tabButton(for: MainTab.notes)
            tabButton(for: MainTab.people)

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            // Liquid Glass 浮动容器
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        )
    }

    @ViewBuilder
    private func tabButton(for tab: MainTab) -> some View {
        let isActive = activeTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeTab = tab
            }
        } label: {
            if let title = tab.title {
                HStack(spacing: 4) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 20, weight: isActive ? .semibold : .regular))
                        .frame(width: 24, height: 24)
                        .scaleEffect(isActive ? 1.1 : 1.0)

                    Text(title)
                        .font(.system(size: 12))
                }
                .foregroundColor(isActive ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isActive ? Color.blue : Color.clear)
                        .animation(.easeInOut(duration: 0.2), value: isActive)
                )
            } else {
                Image(systemName: tab.icon)
                    .foregroundColor(isActive ? .white : .secondary)
                    .font(.system(size: 20, weight: isActive ? .semibold : .regular))
                    .frame(width: 24, height: 24)
                    .scaleEffect(isActive ? 1.1 : 1.0)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule()
                            .fill(isActive ? Color.blue : Color.clear)
                            .animation(.easeInOut(duration: 0.2), value: isActive)
                    )
            }
        }
    }

    /// A description
    private var isAddButtonVisible: Bool {
        activeTab == .vault || activeTab == .notes
    }
}

#Preview("CustomTabBar") {
    @Previewable @State var activeTab: MainTab = .vault

    VStack {
        Spacer()
        CustomTabBar(activeTab: $activeTab) {
            // Add 按钮点击占位
        }
        .padding(.horizontal, 16)
    }
    .padding(.bottom, 24)
}
