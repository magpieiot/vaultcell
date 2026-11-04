/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// LegalDocumentView.swift
/// ------------------------------------------------------------------
///
/// 文档阅读页：目前只有「帮助与反馈」使用。
///
/// 隐私政策与服务条款不再在 App 内保存副本——关于页直接用系统浏览器打开
/// `Legal.privacyPolicyURL` / `Legal.termsOfServiceURL`，条款只维护线上唯一一份。
///
/// 文案使用 SwiftUI 字面量经 `LocalizedStringKey` 解析：
/// English 是 String Catalog 的源语言，直接写在 `LegalContent` 里即可命中，
/// 其余语言由 `Resources/Localizable.xcstrings` 提供，且随应用内语言切换即时生效。
/// ------------------------------------------------------------------

import SwiftUI

struct LegalDocumentView: View {
    /// 导航标题（English 原文，catalog 里已有六语译文）
    let title: String
    let sections: [LegalSection]
    /// 官网上线后配置的在线版本地址；nil 时不显示
    var onlineURL: URL? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sections) { section in
                    sectionView(section)
                }
                footerView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(SettingsBackground())
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        // 二级页面隐藏底部 TabBar
        .preference(key: TabBarVisibilityKey.self, value: true)
    }

    private func sectionView(_ section: LegalSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(section.heading))
                .font(.system(size: 16, weight: .semibold))
            Text(LocalizedStringKey(section.body))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let onlineURL {
                Link(destination: onlineURL) {
                    Label(LocalizedStringKey("Open the online version"), systemImage: "safari")
                }
                .font(.system(size: 14, weight: .medium))
            }
            if let emailURL = Legal.supportEmailURL {
                Link(destination: emailURL) {
                    Label(LocalizedStringKey("Email support"), systemImage: "envelope")
                }
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 文档页面

/// 帮助与反馈：唯一保留在 App 内的本地文档（隐私政策 / 服务条款只在线上维护）
struct HelpFeedbackView: View {
    var body: some View {
        LegalDocumentView(
            title: "Help & Feedback",
            sections: LegalContent.help,
            onlineURL: Legal.helpCenterURL)
    }
}

#Preview("Help & Feedback") {
    HelpFeedbackView()
}
