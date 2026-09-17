//
//  CachedIconView.swift
//  VaultCell
//
//  带本地缓存的远程图标视图。显示优先级：
//  1. 本地缓存图片（IconCacheService，离线可用）
//  2. 远程加载并自动写入缓存（首次访问时）
//  3. 失败回退到 SF Symbol 占位
//
//  刷新策略：除了按图源地址触发的首次加载外，还订阅 IconCacheService 的
//  缓存更新通知。详情页下载成功后列表行的 @State 仍是旧值（nil），
//  若不在此时重新读取缓存，返回列表会一直停留在占位图。
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
    /// 缓存版本号：收到同一图源地址的缓存更新通知后自增，触发重新读盘
    @State private var cacheVersion = 0

    /// 当前使用的图源地址（空串表示无可用地址）
    private var cacheKey: String {
        guard let urlString, !urlString.isEmpty else { return "" }
        return urlString
    }

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: IconCacheService.iconCacheDidUpdateNotification)) { notification in
                guard let key = notification.userInfo?[IconCacheService.cacheKeyUserInfoKey] as? String,
                      key == cacheKey else { return }
                cacheVersion += 1
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if !cacheKey.isEmpty {
            placeholderImage
                .task(id: "\(cacheKey)#\(cacheVersion)") {
                    await load(cacheKey)
                }
        } else {
            placeholderImage
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
