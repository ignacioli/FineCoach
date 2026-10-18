import Foundation

public enum DomainError: Error, Equatable, LocalizedError, Sendable {
    case emptyText
    case textTooLong(maximumBytes: Int)
    case invalidDecimal
    case invalidNumber
    case invalidUnit
    case invalidMode
    case invalidState
    case invalidIdentifier
    case conflict
    case notFound
    case staleRevision
    case protectedDataUnavailable
    case persistenceFailed
    case randomSourceFailed
    case invalidFileOperation
    case incompatibleInput
    case recurrenceLimitExceeded
    case overlapConflict

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "输入内容。"
        case .textTooLong:
            return "内容过长，无法保存。"
        case .invalidDecimal, .invalidNumber:
            return "输入有效数字。"
        case .invalidUnit:
            return "单位不受支持。"
        case .invalidMode:
            return "记录模式不受支持。"
        case .invalidState:
            return "当前状态不允许此操作。"
        case .invalidIdentifier:
            return "标识无效。"
        case .conflict:
            return "内容与已有记录冲突。"
        case .notFound:
            return "记录不存在。"
        case .staleRevision:
            return "记录已更新，再试一次。"
        case .protectedDataUnavailable:
            return "受保护数据暂不可用。"
        case .persistenceFailed:
            return "本地保存没有成功，再试一次。"
        case .randomSourceFailed:
            return "安全随机源不可用。"
        case .invalidFileOperation:
            return "本地文件处理没有完成。"
        case .incompatibleInput:
            return "输入内容不兼容。"
        case .recurrenceLimitExceeded:
            return "周期安排超过可物化上限（最多 366 次）。"
        case .overlapConflict:
            return "与已有安排时间冲突。"
        }
    }
}
