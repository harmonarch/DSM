import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var model = AppModel(settings: settings)
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(model: model)
        statusController = controller
        model.onLoginSucceeded = { [weak self] in
            self?.statusController?.showPopover()
        }
        model.startPolling()

        // 清理上次覆盖安装遗留的旧版本备份
        UpdateService.cleanupStaleBackups()

        // 启动时自动检查更新（设置可关）：延迟错开首屏的余额/用量拉取
        if settings.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.model.update.checkForUpdates()
            }
        }

        // 首次使用：自动弹出悬浮窗引导登录
        if settings.platformToken.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusController?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopPolling()
    }
}
