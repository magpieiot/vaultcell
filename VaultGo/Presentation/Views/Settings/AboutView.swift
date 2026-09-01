/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// AboutView.swift
/// created on: 25/08/2026
/// ------------------------------------------------------------------

import StoreKit
import SwiftUI

/// 关于子页：评分/评论、帮助与反馈、隐私政策、服务条款、版本信息
/// （帮助/隐私/条款为占位页面，正式版本接入实现）
struct AboutView: View {

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

                NavigationLink(destination: Text(String(localized: "Help & Feedback"))) {
                    CustomLabel(
                        leadingIcon: "questionmark.circle", leadingIconColor: .secondary,
                        text: "Help & Feedback")
                }

                NavigationLink(destination: Text(String(localized: "Privacy Policy"))) {
                    CustomLabel(
                        leadingIcon: "hand.raised.fill", leadingIconColor: .secondary,
                        text: "Privacy Policy")
                }

                NavigationLink(destination: Text(String(localized: "Terms of Service"))) {
                    CustomLabel(
                        leadingIcon: "doc.text.fill", leadingIconColor: .secondary,
                        text: "Terms of Service")
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
        .navigationTitle(String(localized: "About"))
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
}
