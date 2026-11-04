import Foundation

/// 仅表示真实同步引擎回执，不使用计时器推测云端是否完成。
enum SyncStatus: Equatable, Sendable {
    case idle
    case inProgress
    case completed
    case failed(message: String)
}
