/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SettingsBackground.swift
/// created on: 23/09/2026
/// ------------------------------------------------------------------

import SwiftUI

/// 与 Onboarding/认证页共享语言的浅色背景
///
/// 设置页改造为工具中心后，这个背景仍被关于页、导出页、联系方式评审页共用，
/// 因此从原设置页文件中独立出来。
struct SettingsBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.99, green: 0.995, blue: 1.0),
                Color.primaryBrandColor.opacity(0.10),
                Color.secondaryBrandColor.opacity(0.06),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
