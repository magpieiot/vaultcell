/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CachedIconView.swift
/// created on: 17/09/2026
/// ------------------------------------------------------------------
///
/// 站点图标视图：只负责把 `IconResolver` 的解析结果画出来，不自己决定要不要联网。
///
/// 显示优先级（永不空白）：
/// 1. 内置图标资产——命中即零请求
/// 2. 本地缓存 / 抓取到的图片（淡入）
/// 3. 字母图块（首字母 + 分类 tint）
/// 4. 兜底 SF Symbol（标题拿不出首字母时）
///
/// 刷新策略：订阅 `IconStore.cacheDidUpdateNotification`。详情页抓取成功后，
/// 列表行的 @State 仍是旧值（nil），不重新读缓存的话返回列表会一直停留在占位态。
/// 通知按**缓存键**匹配：`www.x.com` 与 `x.com` 归一后是同一个键，两处会一起刷新。

import SwiftUI
import UIKit

struct CachedIconView: View {
    /// 解析请求（标题 / 站点地址 / 用户手动指定的图源）
    let request: IconRequest
    /// 是否允许发起远程抓取。建议列表等「尚未落库」的场景传 false：
    /// 只显示内置图标 / 缓存 / 字母图块，不发请求，等条目保存后由列表与详情页触发抓取
    var allowsRemoteFetch = true
    /// 首字母无法得出时的兜底 SF Symbol
    var fallbackSystemName = "folder.fill"
    var placeholderColor: Color = .blue
    var placeholderFont: Font = .title2

    @Environment(\.colorScheme) private var colorScheme
    @State private var builtinAsset: String?
    @State private var image: UIImage?
    @State private var initial: String = ""
    /// 缓存版本号：收到同一缓存键的更新通知后自增，触发重新解析
    @State private var cacheVersion = 0

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: IconStore.cacheDidUpdateNotification)) {
                notification in
                guard let key = notification.userInfo?[IconStore.cacheKeyUserInfoKey] as? String,
                    key == request.cacheKey
                else { return }
                cacheVersion += 1
            }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let builtinAsset {
                Image(builtinAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
                    .modifier(RemoteIconDarkPlate(active: colorScheme == .dark))
            } else if !initial.isEmpty {
                LetterTile(initial: initial, tint: placeholderColor, font: placeholderFont)
            } else {
                Image(systemName: fallbackSystemName)
                    .font(placeholderFont)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(placeholderColor)
            }
        }
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: "\(request.taskID)#\(cacheVersion)") {
            await load()
        }
    }

    /// 内置图标 / 缓存 → 字母图块（同步，永不空白）；必要时再补一次远程抓取
    private func load() async {
        let resolution = IconResolver.resolve(request)
        // 资产名必须真实存在，否则 `Image(asset)` 会渲染成空白（表与 Assets 漂移时的兜底）
        builtinAsset = resolution.builtinAsset.flatMap { UIImage(named: $0) == nil ? nil : $0 }
        initial = resolution.initial

        if let cached = resolution.cachedImage {
            image = cached
            return
        }
        guard allowsRemoteFetch else { return }
        image = await IconResolver.fetchRemote(request)
    }
}

/// 深色模式下为远程位图图标垫浅色底板。
///
/// 远程抓取的 favicon / apple-touch-icon 颜色完全不可控，深色位图在深色背景上会隐形；
/// 内置 SVG 图标不套用本底板——它们已通过资产目录的深色外观变体单独适配。
/// 底板画在调用方给定的尺寸内部（内缩 padding），不改变外部布局。
private struct RemoteIconDarkPlate: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .padding(4)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        } else {
            content
        }
    }
}
