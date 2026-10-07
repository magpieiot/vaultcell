/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IconSafety.swift
/// created on: 17/09/2026
/// ------------------------------------------------------------------
///
/// 远程图标的安全校验（纯逻辑：Foundation + CoreGraphics，可进单测 target）。
///
/// 三道闸门，任一不过即整份数据丢弃：
/// 1. 体积：单次响应体 ≤ 64KB（favicon 通常 < 100KB，主页 HTML 不再抓取，超限即异常响应）
/// 2. 类型：只认 PNG / JPEG / ICO 的魔数。**SVG / HTML 一律拒收**——
///    SVG 需要走 SVGKit 离屏渲染（曾因此引入外链同步请求与主线程阻塞），
///    HTML 则是「域名填错指向网页」的常见误命中
/// 3. 尺寸：从文件头解析宽高，≤ 512×512，防解压炸弹（解码后再用 `isAcceptable(size:)` 复核一次）

import Foundation
import CoreGraphics

enum IconSafety {
    /// 单次响应体上限：64KB
    static let maxBytes = 64 * 1024

    /// 像素尺寸上限：512×512
    static let maxPixelDimension: CGFloat = 512

    /// 允许的图片类型（按魔数识别）
    enum Kind: String {
        case png
        case jpeg
        case ico
    }

    // MARK: - 类型

    /// 按魔数识别图片类型；SVG / HTML / GIF / WebP 等返回 nil（拒收）
    static func kind(of data: Data) -> Kind? {
        guard data.count >= 8 else { return nil }
        let bytes = [UInt8](data.prefix(8))
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
            bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A
        {
            return .png
        }
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return .jpeg
        }
        // ICO: 00 00 01 00（ICONDIR）
        if bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x01, bytes[3] == 0x00 {
            return .ico
        }
        return nil
    }

    // MARK: - 尺寸

    /// 从文件头解析像素尺寸；解析失败返回 nil（非法或截断数据）
    static func pixelSize(of data: Data, kind: Kind) -> CGSize? {
        switch kind {
        case .png:
            // IHDR：offset 16 起为 width(4) + height(4)，大端
            guard data.count >= 24 else { return nil }
            let width = bigEndian32(data, at: 16)
            let height = bigEndian32(data, at: 20)
            guard width > 0, height > 0 else { return nil }
            return CGSize(width: CGFloat(width), height: CGFloat(height))

        case .jpeg:
            return jpegPixelSize(data)

        case .ico:
            // ICONDIR(6) + 首条目录项：width(1) height(1)，0 表示 256
            guard data.count >= 8 else { return nil }
            let width = data[6] == 0 ? 256 : Int(data[6])
            let height = data[7] == 0 ? 256 : Int(data[7])
            return CGSize(width: CGFloat(width), height: CGFloat(height))
        }
    }

    /// 整体校验：体积、类型、头部尺寸三道闸门
    static func isAcceptable(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maxBytes, let kind = kind(of: data),
              let size = pixelSize(of: data, kind: kind) else { return false }
        return isAcceptable(size: size)
    }

    /// 尺寸校验（解码后再复核一次，防「头部声明与真实解码尺寸不一致」）
    static func isAcceptable(size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return size.width <= maxPixelDimension && size.height <= maxPixelDimension
    }

    // MARK: - 内部

    private static func bigEndian32(_ data: Data, at offset: Int) -> Int {
        guard data.count >= offset + 4 else { return 0 }
        return Int(data[offset]) << 24 | Int(data[offset + 1]) << 16
            | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
    }

    /// 扫描 JPEG 的 SOF 段（FFC0~FFC3 / FFC5~FFC7 / FFC9~FFCB / FFCD~FFCF）取宽高。
    /// 跳过 DHT(C4)、JPG(C8)、DAC(CC) 这些同区间但结构不同的段。
    private static func jpegPixelSize(_ data: Data) -> CGSize? {
        var index = 2  // 跳过 SOI
        while index + 1 < data.count {
            guard data[index] == 0xFF else {
                index += 1
                continue
            }
            let marker = data[index + 1]
            if (0xC0...0xC3).contains(marker) || (0xC5...0xC7).contains(marker)
                || (0xC9...0xCB).contains(marker) || (0xCD...0xCF).contains(marker)
            {
                // 段内布局：length(2) precision(1) height(2) width(2)
                guard index + 8 < data.count else { return nil }
                let height = Int(data[index + 5]) << 8 | Int(data[index + 6])
                let width = Int(data[index + 7]) << 8 | Int(data[index + 8])
                guard width > 0, height > 0 else { return nil }
                return CGSize(width: CGFloat(width), height: CGFloat(height))
            }
            guard index + 3 < data.count else { return nil }
            let length = Int(data[index + 2]) << 8 | Int(data[index + 3])
            guard length >= 2 else { return nil }
            index += 2 + length
        }
        return nil
    }
}
