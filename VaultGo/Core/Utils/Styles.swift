/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultGo
/// Styles.swift
/// created on: 08/06/2026
/// ------------------------------------------------------------------

//
//  LeadingIconTextFieldStyle.swift
//  VaultGo
//
//  Created by gavanwang on 2026/6/8.
//

import SwiftUI


struct LeadingIconTextFieldStyle: TextFieldStyle {
    var systemName: String
    var iconColor: Color = .blue
    var backgroundColor: Color = .clear

    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24, alignment: .center)
            configuration // 这就是原始的 TextField
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(backgroundColor))
    }
}

