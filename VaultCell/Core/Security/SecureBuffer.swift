/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// SecureBuffer.swift
/// created on: 03/06/2026
/// ------------------------------------------------------------------

import Foundation
import UIKit

class SecureBuffer {
    private var bytes: UnsafeMutableRawBufferPointer
    private let count: Int
    private(set) var isDestroyed: Bool = false
    private let pageSize = Int(getpagesize())
    
    init(count: Int) {
        self.count = count
        
        let alignedCount = (count + pageSize - 1) / pageSize * pageSize
        
        let allocationSize = alignedCount + 2 * pageSize
        
        let rawPtr = mmap(
            nil,
            allocationSize,
            PROT_NONE,
            MAP_PRIVATE | MAP_ANONYMOUS,
            -1,
            0
        )
        
        let baseAddr = Int(bitPattern: rawPtr)
        let alignedAddr = ((baseAddr + pageSize - 1) & ~(pageSize - 1))
        let dataStart = alignedAddr + pageSize
        
        let ptr = UnsafeMutableRawPointer(bitPattern: dataStart)!
        
        bytes = UnsafeMutableRawBufferPointer(start: ptr, count: count)
        
        mlock(ptr, count)
        
        memset(ptr, 0, count)
    }
    
    func write(_ data: Data, offset: Int = 0) {
        guard !isDestroyed else { return }
        guard offset + data.count <= count else { return }
        data.withUnsafeBytes { source in
            if let src = source.baseAddress, let dest = bytes.baseAddress?.advanced(by: offset) {
                memcpy(dest, src, data.count)
            }
        }
    }
    
    func read(offset: Int = 0, length: Int? = nil) -> Data {
        guard !isDestroyed else { return Data() }
        guard offset >= 0, offset < count else { return Data() }
        guard let base = bytes.baseAddress else { return Data() }
        
        let requestedLen = length ?? (count - offset)
        let len = max(0, min(requestedLen, count - offset))
        guard len > 0 else { return Data() }
        
        return Data(bytes: base.advanced(by: offset), count: len)
    }
    
    func destroy() {
        guard !isDestroyed else { return }
        
        let patterns: [UInt8] = [0x00, 0xFF, 0xAA, 0x55, 0x00]
        if let base = bytes.baseAddress {
            for pattern in patterns {
                memset(base, Int32(pattern), count)
            }
        }
        
        munlock(bytes.baseAddress, count)
        bytes.deallocate()
        
        isDestroyed = true
    }
    
    deinit {
        if !isDestroyed {
            destroy()
        }
    }
}

@MainActor
class ClipboardService {
    static let shared = ClipboardService()
    
    private var clearTimer: Timer?
    private var originalContent: String?
    
    private init() {}

    /// 按设置里的「剪贴板自动清理」时长复制文本，并返回实际倒计时秒数（0 表示不自动清除）。
    /// 视图层统一走这里，避免直写 UIPasteboard 绕过定时清理；返回值用于生成一致的复制反馈。
    @discardableResult
    func copy(_ text: String) -> TimeInterval {
        let seconds = UserDefaults.clipboardTimeout
        copyToClipboard(text, clearAfter: seconds)
        return seconds
    }

    func copyToClipboard(_ text: String, clearAfter seconds: TimeInterval = 60) {
        originalContent = UIPasteboard.general.string
        UIPasteboard.general.string = text
        
        clearTimer?.invalidate()
        
        if seconds > 0 {
            clearTimer = Timer.scheduledTimer(
                withTimeInterval: seconds,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.clearClipboard()
                }
            }
        }
    }
    
    func clearClipboard() {
        if let original = originalContent {
            UIPasteboard.general.string = original
        } else {
            UIPasteboard.general.items = []
        }
        clearTimer?.invalidate()
        clearTimer = nil
    }
}
