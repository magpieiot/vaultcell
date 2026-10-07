/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// IconPipelineTests.swift
/// 覆盖图标链路的纯逻辑：域名规范化（DomainKey）与图片安全校验（IconSafety）。
/// 两者决定「查表 key / 缓存键 / 失败集合键是否同源」以及「哪些远程数据会被拒收」，
/// 属于政策硬约束，回归成本高，因此单独加测。
/// ------------------------------------------------------------------

import CoreGraphics
import Foundation
import Testing

// MARK: - 域名规范化

@Suite("DomainKey.normalize")
struct DomainKeyNormalizeTests {
    @Test("去 scheme / www. / 端口 / 路径与查询")
    func keepsOnlyNormalizedHost() {
        #expect(DomainKey.normalize("https://www.Example.com:443/login?next=1") == "example.com")
        #expect(DomainKey.normalize("http://example.com/") == "example.com")
        #expect(DomainKey.normalize("example.com") == "example.com")
        #expect(DomainKey.normalize("WWW.EXAMPLE.COM") == "example.com")
    }

    @Test("只去掉一层 www. 前缀")
    func stripsSingleWWWPrefix() {
        #expect(DomainKey.normalize("www.www.example.com") == "www.example.com")
    }

    @Test("子域不做合并，只去 www.")
    func keepsOtherSubdomains() {
        #expect(DomainKey.normalize("https://music.163.com/song") == "music.163.com")
    }

    @Test("空输入 / 无 host 返回 nil")
    func returnsNilForInvalidInput() {
        #expect(DomainKey.normalize("") == nil)
        #expect(DomainKey.normalize("   ") == nil)
    }

    @Test("前后空白被裁掉")
    func trimsWhitespace() {
        #expect(DomainKey.normalize("  https://www.example.com  ") == "example.com")
    }
}

@Suite("DomainKey.fetchHosts")
struct DomainKeyFetchHostsTests {
    @Test("裸域补 www 变体")
    func appendsWWWVariant() {
        #expect(DomainKey.fetchHosts("https://meituan.com/x") == ["meituan.com", "www.meituan.com"])
    }

    @Test("www 主机保留原样并补裸域")
    func keepsOriginalWWWHostFirst() {
        #expect(DomainKey.fetchHosts("https://www.meituan.com/x") == [
            "www.meituan.com", "meituan.com",
        ])
    }

    @Test("非法输入返回空数组（不猜域名）")
    func returnsEmptyForInvalidInput() {
        #expect(DomainKey.fetchHosts("").isEmpty)
    }
}

@Suite("DomainKey.cacheKey")
struct DomainKeyCacheKeyTests {
    @Test("裸域与 www、不同写法归一到同一个键")
    func normalizesToSameKey() {
        let key = DomainKey.cacheKey("https://example.com/login")
        #expect(key != nil)
        #expect(DomainKey.cacheKey("https://www.example.com/") == key)
        #expect(DomainKey.cacheKey("EXAMPLE.com:8443") == key)
    }

    @Test("不同域名键不同")
    func differentDomainsHaveDifferentKeys() {
        #expect(DomainKey.cacheKey("example.com") != DomainKey.cacheKey("example.org"))
    }

    @Test("键为 64 位十六进制（sha256）")
    func keyIsHexDigest() {
        let key = DomainKey.cacheKey("example.com") ?? ""
        #expect(key.count == 64)
        #expect(key.allSatisfy { $0.isHexDigit })
        // 只落哈希不落明文域名
        #expect(!key.contains("example"))
    }

    @Test("无法规范化的输入返回 nil")
    func returnsNilForInvalidInput() {
        #expect(DomainKey.cacheKey("") == nil)
    }
}

// MARK: - 图片安全校验

@Suite("IconSafety.kind")
struct IconSafetyKindTests {
    @Test("识别 PNG / JPEG / ICO")
    func detectsSupportedFormats() {
        #expect(IconSafety.kind(of: Self.png(width: 32, height: 32)) == .png)
        #expect(IconSafety.kind(of: Self.jpeg(width: 32, height: 16)) == .jpeg)
        #expect(IconSafety.kind(of: Self.ico(width: 32, height: 32)) == .ico)
    }

    @Test("拒收 SVG")
    func rejectsSVG() {
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><rect/></svg>".utf8)
        #expect(IconSafety.kind(of: svg) == nil)
        #expect(!IconSafety.isAcceptable(svg))
    }

    @Test("拒收 HTML（域名填错指向网页）")
    func rejectsHTML() {
        let html = Data("<!DOCTYPE html><html><body>hi</body></html>".utf8)
        #expect(IconSafety.kind(of: html) == nil)
        #expect(!IconSafety.isAcceptable(html))
    }

    @Test("拒收 GIF")
    func rejectsGIF() {
        var bytes: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00]
        bytes.append(contentsOf: [0x00, 0x00])
        #expect(IconSafety.kind(of: Data(bytes)) == nil)
    }

    @Test("过短的数据不足以判定")
    func rejectsTooShortData() {
        #expect(IconSafety.kind(of: Data([0x89, 0x50])) == nil)
        #expect(IconSafety.kind(of: Data()) == nil)
    }

    // MARK: 构造最小合法头部

    static func png(width: UInt32, height: UInt32) -> Data {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        bytes.append(contentsOf: [0x00, 0x00, 0x00, 0x0D])  // IHDR 长度
        bytes.append(contentsOf: Array("IHDR".utf8))  // 段类型
        bytes.append(contentsOf: bigEndian(width))  // 宽
        bytes.append(contentsOf: bigEndian(height))  // 高
        return Data(bytes)
    }

    static func jpeg(width: UInt16, height: UInt16) -> Data {
        // SOI + SOF0（长度 0x0011、精度 8、高、宽）
        var bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08]
        bytes.append(contentsOf: [UInt8(height >> 8), UInt8(height & 0xFF)])
        bytes.append(contentsOf: [UInt8(width >> 8), UInt8(width & 0xFF)])
        return Data(bytes)
    }

    static func ico(width: UInt8, height: UInt8) -> Data {
        Data([0x00, 0x00, 0x01, 0x00, 0x01, 0x00, width, height])
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }
}

@Suite("IconSafety 尺寸与体积")
struct IconSafetyLimitTests {
    @Test("从文件头解析尺寸（含 ICO 的 0 表示 256）")
    func parsesPixelSize() {
        let png = IconSafetyKindTests.png(width: 180, height: 180)
        #expect(IconSafety.pixelSize(of: png, kind: .png) == CGSize(width: 180, height: 180))

        let jpeg = IconSafetyKindTests.jpeg(width: 32, height: 16)
        #expect(IconSafety.pixelSize(of: jpeg, kind: .jpeg) == CGSize(width: 32, height: 16))

        let ico = IconSafetyKindTests.ico(width: 0, height: 0)
        #expect(IconSafety.pixelSize(of: ico, kind: .ico) == CGSize(width: 256, height: 256))
    }

    @Test("尺寸上限 512×512")
    func enforcesPixelLimit() {
        #expect(IconSafety.isAcceptable(size: CGSize(width: 512, height: 512)))
        #expect(!IconSafety.isAcceptable(size: CGSize(width: 513, height: 512)))
        #expect(!IconSafety.isAcceptable(size: CGSize(width: 0, height: 32)))
    }

    @Test("超限尺寸的整体校验不通过")
    func rejectsOversizedImage() {
        let png = IconSafetyKindTests.png(width: 1024, height: 1024)
        #expect(!IconSafety.isAcceptable(png))
    }

    @Test("体积上限 64KB")
    func enforcesByteLimit() {
        var data = IconSafetyKindTests.png(width: 32, height: 32)
        data.append(Data(repeating: 0, count: IconSafety.maxBytes))
        #expect(data.count > IconSafety.maxBytes)
        #expect(!IconSafety.isAcceptable(data))
    }

    @Test("刚好在体积上限内的合法数据通过")
    func acceptsWithinByteLimit() {
        #expect(IconSafety.isAcceptable(IconSafetyKindTests.png(width: 32, height: 32)))
    }
}
