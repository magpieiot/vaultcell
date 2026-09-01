//
//  CusomLabel.swift
//  VaultGo
//
//  Created by gavanwang on 2026/7/16.
//

import SwiftUI

// 自定义标签组件
struct CustomLabel: View {
    let leadingIcon: String
    var leadingIconSize: CGFloat
    var leadingIconColor: Color
    
    var trailingIcon: String?
    var trailingIconSize: CGFloat
    var trailingIconColor: Color
    
    var text: LocalizedStringKey
    var value: String?

    /// 原始全参初始化器
    init(leadingIcon: String,
         leadingIconSize: CGFloat = 24.0,
         leadingIconColor: Color = .blue,
         trailingIcon: String? = nil,
         trailingIconSize: CGFloat = 24.0,
         trailingIconColor: Color = .primary,
         text: LocalizedStringKey,
         value: String? = nil) {
        self.leadingIcon = leadingIcon
        self.leadingIconSize = leadingIconSize
        self.leadingIconColor = leadingIconColor
        self.trailingIcon = trailingIcon
        self.trailingIconSize = trailingIconSize
        self.trailingIconColor = trailingIconColor
        self.text = text
        self.value = value
    }
}

extension CustomLabel {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: leadingIcon)
                .foregroundColor(leadingIconColor)
                .frame(width: leadingIconSize, height: leadingIconSize)
            
            if let value = value {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(value)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                }
            } else {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
            }

            Spacer()
            if let trailingIcon = trailingIcon {
                Image(systemName: trailingIcon)
                    .foregroundColor(trailingIconColor)
                    .frame(width: trailingIconSize, height: trailingIconSize)
            }
        }
    }
}

/// 分类标签
/// 
struct CategoryLabel : View {
    var category: PasswordCategory

    var body: some View {
        Text(category.name)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .symbolRenderingMode(.hierarchical)
            .background(category.backgroundColor ?? Color.secondary.opacity(0.12))
            .foregroundColor(category.tintColor ?? Color.secondary)
            .clipShape(Capsule())
    }
}
