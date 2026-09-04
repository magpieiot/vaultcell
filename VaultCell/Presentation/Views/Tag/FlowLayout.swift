//
//  FlowLayout.swift
//  VaultCell
//
//  Created by gavanwang on 2026/7/13.
//


import SwiftUI

// iOS 16+ 原生 Layout 协议实现
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            // 如果当前行放不下，换行
            if currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct TagListView : View {
    // 用 let 而非 @State：@State 的初始值只在视图首次出现时生效，
    // 父视图数据更新后重新初始化不会同步，导致编辑返回后标签不刷新
    let tags: [String]
    
    var body: some View {
        FlowLayout(spacing: 8)  {
            ForEach(tags, id: \.self) { tag in
                let tagTag   = Tag(name: tag)
                TagChipView(
                    tag: tagTag,
                    isEditing: false,
                    onDelete: {},
                    onLongPress: {}
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
