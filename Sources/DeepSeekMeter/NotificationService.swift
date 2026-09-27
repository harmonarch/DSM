import Foundation
import UserNotifications

/// 低余额本地通知（纯本地计算，无第三方推送、不联网、不上报任何数据；与 iOS NotificationService 同语义）。
/// 去重标志沿用 iOS 约定 notified.lowBalance.<threshold>，阈值固定 1.0（当前币种 1 个单位）。
enum NotificationService {
    /// 低余额提醒阈值（对齐 iOS / Android 固定值）
    static let lowBalanceThreshold = 1.0

    /// 去重标志 key：同一低余额周期只提醒一次
    private static var flagKey: String { "notified.lowBalance.\(Int(lowBalanceThreshold))" }

    /// 请求通知权限（首次打开开关时调用）
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 刷新成功后调用：余额跌破阈值且本档未提醒过则弹本地通知（避免每次轮询都重复弹）。
    /// 决策统一走 lowBalanceDecision（纯函数）；余额回升时 alerted 随之复位，下次跌破可再提醒。
    /// - Parameter enabled: 设置开关，关闭时不提示
    static func notifyLowBalanceIfNeeded(balance: Double, currency: String, enabled: Bool) {
        guard enabled else { return }
        let alerted = UserDefaults.standard.bool(forKey: flagKey)
        let decision = lowBalanceDecision(balance: balance,
                                          threshold: lowBalanceThreshold,
                                          alerted: alerted)
        // 先持久化决策状态：余额已回升时这里会写回 false，等价于自动重置标记
        UserDefaults.standard.set(decision.alerted, forKey: flagKey)
        guard decision.shouldNotify else { return }

        let content = UNMutableNotificationContent()
        content.title = "余额不足提醒"
        content.body = "当前余额 \(currencySymbol(currency))\(format(balance))，低于 \(format(lowBalanceThreshold))"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "low-balance", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 重置提醒标记（退出登录时调用，重新登录后余额低于阈值可再次提醒）
    static func resetLowBalanceFlag() {
        UserDefaults.standard.removeObject(forKey: flagKey)
    }
}

/// 前台展示通知横幅：App 是常驻菜单栏的 .accessory 进程，没有它前台收到通知会静默丢弃
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
