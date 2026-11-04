/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AboutView.swift
/// created on: 25/08/2026
/// ------------------------------------------------------------------

import StoreKit
import SwiftUI

/// 关于子页：评分/评论、帮助与反馈、隐私政策、服务条款、版本信息
///
/// 帮助与反馈仍是 App 内的本地文档页（`Settings/Legal/`）；
/// 隐私政策与服务条款只在线上维护，点击直接用系统浏览器打开 `Legal.*URL`，
/// 避免同一份条款在 App 内和线上各存一份、改一处漏一处。
struct AboutView: View {

    @Environment(\.openURL) private var openURL

    /// 离线时点击线上条款的提示（条款只在线上维护，离线读不到）
    @State private var showingOfflineAlert = false

    var body: some View {
        List {
            Section {
                // 评分与评论
                Button {
                    requestAppReview()
                } label: {
                    CustomLabel(
                        leadingIcon: "star.fill", leadingIconColor: .yellow,
                        text: "Rate the App")
                }

                // 写评论
                /*
                Button {
                    openWriteReview()
                } label: {
                    CustomLabel(
                        leadingIcon: "square.and.pencil", leadingIconColor: .secondary,
                        trailingIcon: "chevron.right", text: "Write a Review")
                }
                */

                NavigationLink(destination: HelpFeedbackView()) {
                    CustomLabel(
                        leadingIcon: "questionmark.circle", leadingIconColor: .secondary,
                        text: "Help & Feedback")
                }

                // 隐私政策 / 服务条款：只维护线上版本，点击交给系统浏览器
                Button {
                    openOnline(Legal.privacyPolicyURL)
                } label: {
                    CustomLabel(
                        leadingIcon: "hand.raised.fill", leadingIconColor: .secondary,
                        trailingIcon: "arrow.up.right", text: "Privacy Policy")
                }

                Button {
                    openOnline(Legal.termsOfServiceURL)
                } label: {
                    CustomLabel(
                        leadingIcon: "doc.text.fill", leadingIconColor: .secondary,
                        trailingIcon: "arrow.up.right", text: "Terms of Service")
                }

                HStack {
                    CustomLabel(
                        leadingIcon: "info.circle", leadingIconColor: .secondary, text: "Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SettingsBackground())
        .alert("You're Offline", isPresented: $showingOfflineAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This document opens in your browser, so it needs a network connection. Connect to the internet and try again.")
        }
        .navigationTitle(AppLocale.string("About"))
        .navigationBarTitleDisplayMode(.inline)
        // 二级页面隐藏底部 TabBar
        .preference(key: TabBarVisibilityKey.self, value: true)
    }

    /// 从 Bundle 读取营销版本号，避免硬编码
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        return "\(short) (\(build))"
    }

    /// 触发系统应用内评分弹窗（iOS 14+ 使用当前窗口场景）
    private func requestAppReview() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        SKStoreReviewController.requestReview(in: scene)
    }

    /// 打开 App Store 写评论页面
    private func openWriteReview() {
        guard let url = AppStore.writeReviewURL else { return }
        UIApplication.shared.open(url)
    }

    /// 用系统浏览器打开线上条款页。
    ///
    /// 条款只在线上维护，离线时无法阅读，因此先做一次可达性判断：
    /// 离线给 App 内提示，而不是把用户丢到 Safari 的错误页；
    /// `Legal.*URL` 未配置时什么也不做。
    private func openOnline(_ url: URL?) {
        guard let url else { return }
        Task { @MainActor in
            guard await NetworkReachability.isOnline() else {
                showingOfflineAlert = true
                return
            }
            openURL(url)
        }
    }
}
