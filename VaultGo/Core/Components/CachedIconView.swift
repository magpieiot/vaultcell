//
//  CachedIconView.swift
//  VaultGo
//
//  带本地缓存的远程图标视图。显示优先级：
//  1. 本地缓存图片（IconCacheService，离线可用）
//  2. 远程加载并自动写入缓存（首次访问时）
//  3. 失败回退到 SF Symbol 占位
//

import SwiftUI
import UIKit

struct CachedIconView: View {
    /// 远程图标地址（nil / 空串时直接显示占位）
    let urlString: String?
    /// 占位 SF Symbol 名称
    var placeholderSystemName = "folder.fill"
    var placeholderColor: Color = .blue
    var placeholderFont: Font = .title2

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let urlString, !urlString.isEmpty {
                placeholderImage
                    .task(id: urlString) {
                        await load(urlString)
                    }
            } else {
                placeholderImage
            }
        }
    }

    private var placeholderImage: some View {
        Image(systemName: placeholderSystemName)
            .font(placeholderFont)
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(placeholderColor)
    }

    private func load(_ urlString: String) async {
        // 缓存优先，无缓存则下载（同源 favicon 失败自动兜底），统一由 IconCacheService 处理
        image = await IconCacheService.loadIcon(urlString: urlString)
    }
}
