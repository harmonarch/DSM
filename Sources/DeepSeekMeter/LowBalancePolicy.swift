import Foundation

// MARK: - 低余额通知决策（纯函数，可测；对齐 Android LowBalancePolicy.kt / iOS NotificationService）

/// 决策结果：是否应该弹通知 + 新的「已提醒」状态（持久化由调用方负责）
struct LowBalanceDecision: Equatable {
    let shouldNotify: Bool
    let alerted: Bool
}

/// 低余额决策状态机：
/// - balance <= 0：无有效低余额区间，不通知，alerted 保持
/// - balance >= threshold：余额恢复，不通知，alerted 重置（下次跌破可再次提醒）
/// - 0 < balance < threshold 且已提醒：同一低余额周期，不重复通知
/// - 0 < balance < threshold 且未提醒：首次低余额 -> 通知，alerted = true
///
/// - Parameters:
///   - balance: 当前钱包余额（调用方保证与 threshold 同一币种）
///   - threshold: 低余额阈值，默认 1.0（当前币种的一个单位，与移动端一致）
///   - alerted: 上次提醒状态（调用方从 UserDefaults 读入）
func lowBalanceDecision(balance: Double,
                        threshold: Double = 1.0,
                        alerted: Bool) -> LowBalanceDecision {
    if balance <= 0 { return LowBalanceDecision(shouldNotify: false, alerted: alerted) }
    if balance >= threshold { return LowBalanceDecision(shouldNotify: false, alerted: false) }
    if alerted { return LowBalanceDecision(shouldNotify: false, alerted: true) }
    return LowBalanceDecision(shouldNotify: true, alerted: true)
}
