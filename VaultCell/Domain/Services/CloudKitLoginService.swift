/// ------------------------------------------------------------------
/// 版权所有 © 2026 Gavan Wang  保留所有权利。
/// Project: VaultCell
/// CloudKitLoginService.swift
/// created on: 08/23/2026
/// ------------------------------------------------------------------

import CloudKit
import Foundation

/// CloudKit 登录上报服务协议
protocol CloudKitLoginServiceProtocol {
    /// 将登录事件写入 CloudKit
    /// - Parameter event: 包含时间、iOS 版本、设备型号、用户 ID 的登录事件
    func reportLogin(event: LoginEvent) async
}

/// 默认实现：将登录事件写入 CloudKit 公共数据库
///
/// 标记为 @unchecked Sendable：CKContainer 与 CKDatabase 未声明 Sendable，
/// 但 CloudKit API 自身线程安全，服务内部仅读取这些不可变成员。
final class CloudKitLoginService: CloudKitLoginServiceProtocol, @unchecked Sendable {

    /// CloudKit Record 类型名称
    private let recordType = "LoginEvent"

    /// CloudKit 容器，默认使用应用默认容器
    private let container: CKContainer

    /// 公共数据库，登录事件对开发者可见且不包含敏感凭据
    private let database: CKDatabase

    init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.publicCloudDatabase
    }

    /// 上报登录事件
    ///
    /// 失败时仅打印日志，不影响登录流程与用户体验。
    /// - Parameter event: 登录事件
    func reportLogin(event: LoginEvent) async {
        let record = CKRecord(recordType: recordType)
        record["timestamp"] = event.timestamp
        record["iosVersion"] = event.iosVersion
        record["deviceModel"] = event.deviceModel
        record["userID"] = event.userID

        do {
            try await database.save(record)
        } catch {
            print("CloudKit login report failed: \(error)")
        }
    }
}
