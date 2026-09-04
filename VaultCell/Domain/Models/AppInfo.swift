/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// AppInfo.swift
/// created on: 08/23/2026
/// ------------------------------------------------------------------

import Foundation

/// 应用元数据，对应 bundle 中 `apps_500_min.json` 的条目
struct AppInfo: Codable, Identifiable, Hashable {
    
    /// App Store 曲目 ID
    let trackId: Int
    
    /// App Store 显示名称
    let trackName: String
    
    /// Bundle 标识符
    let bundleId: String
    
    /// 全拼
    let pinyin: String
    
    /// 拼音首字母
    let pinyinInitials: String
    
    /// 简称/标题
    let title: String
    
    /// 官网域名
    let url: String
    
    /// 唯一标识，直接使用 trackId
    var id: Int { trackId }
}
