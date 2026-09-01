//
//  AppHomeView.swift
//  VaultGo
//
//  Created by gavanwang on 2026/7/21.
//

import SwiftUI

// 封装通用圆角方形卡片组件
struct VCardView: View {
    let title: String
    let desc: String
    let height: CGFloat
    let backgroundColor: Color
    var titleColor: Color = .white
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .fontWeight(.heavy)
                .font(.system(size: height / 2 - 8))
                .foregroundColor(titleColor)
                
            Text(desc)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(
            GeometryReader { proxy in
                backgroundColor
                    .preference(key: CardHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .cornerRadius(16)
    }
}

// 封装通用圆角方形卡片组件
struct HCardView: View {
    let title: String
    let desc: String
    let height: CGFloat
    let backgroundColor: Color
    var titleColor: Color = .white
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .fontWeight(.heavy)
                .font(.system(size: height - 16))
                .foregroundColor(titleColor)
                
            Text(desc)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(
            GeometryReader { proxy in
                backgroundColor
                    .preference(key: CardHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .cornerRadius(16)
    }
}

struct SecretCardView: View {
    let secretScore: Int
    let note: String
    let height: CGFloat

    private var clampedScore: Int {
        min(max(secretScore, 0), 100)
    }

    private var hue: Double {
        0.33 * (Double(clampedScore) / 100)
    }

    private var backgroundColor: Color {
        Color(hue: hue, saturation: 0.22, brightness: 0.95)
    }

    private var titleColor: Color {
        Color(hue: hue, saturation: 0.72, brightness: 0.68)
    }

    var body: some View {
        VCardView(
            title: "\(clampedScore)",
            desc: note,
            height: height,
            backgroundColor: backgroundColor,
            titleColor: titleColor
        )
    }
}

private struct CardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 120

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
