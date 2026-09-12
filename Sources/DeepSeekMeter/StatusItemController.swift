import AppKit
import SwiftUI
import Combine

/// 弹窗宿主：每次出现时重新计算内容尺寸，避免顶部/底部裁剪
private final class PopoverHostViewController: NSViewController {
    var onViewDidAppear: (() -> Void)?
    override func viewDidAppear() {
        super.viewDidAppear()
        onViewDidAppear?()
    }
}

/// 菜单栏状态项 + 点击弹出的悬浮窗（NSPopover）
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private weak var model: AppModel?
    private var hostingView: NSHostingView<PopoverView>?
    private var cancellables: Set<AnyCancellable> = []

    /// 弹窗收起监视器（showPopover 时安装，didClose 时移除）
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var didCloseObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "DeepSeek Meter"
        }

        let width: CGFloat = 340
        let hosting = NSHostingView(rootView: PopoverView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 620)
        hosting.autoresizingMask = [.width, .height]
        self.hostingView = hosting

        // 玻璃质感底衬：SwiftUI 内容之下垫一层系统材质，半透明 UI 后面呈现磨砂玻璃观感。
        // NSGlassEffectView 是 macOS 26 新增 API，旧 SDK（如 CI 的 macos-15 镜像）没有该符号，
        // 不能直接引用——用 NSClassFromString 运行时查找：macOS 26+ 返回液态玻璃，
        // 其余环境自动回退 NSVisualEffectView
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 620))
        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassType.init(frame: container.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.setValue(hosting, forKey: "contentView")
            container.addSubview(glass)
        } else {
            let effect = NSVisualEffectView(frame: container.bounds)
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.autoresizingMask = [.width, .height]
            container.addSubview(effect)
            container.addSubview(hosting)
        }

        let contentVC = PopoverHostViewController()
        contentVC.view = container
        contentVC.onViewDidAppear = { [weak self] in
            Task { @MainActor [weak self] in self?.resizePopoverToFitContent() }
        }
        popover.contentViewController = contentVC
        popover.contentSize = NSSize(width: width, height: 620)
        // 收起时机由本地监视器统一管理（见 installDismissMonitors）：
        // 不用系统 .transient，是因为它会先于按钮动作收起弹窗，导致「点击状态栏图标关闭」
        // 变成先关后开，图标永远关不掉弹窗
        popover.behavior = .applicationDefined
        popover.animates = true

        // 弹窗关闭时移除收起监视器
        didCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            self?.removeDismissMonitors()
        }

        // 状态变化时刷新菜单栏文字/图标，并自适应弹窗尺寸
        model.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.render()
                    self?.resizePopoverToFitContent()
                }
            }
            .store(in: &cancellables)

        render()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// 根据内容重新计算弹窗尺寸（不超屏幕，超出部分由 ScrollView 滚动）
    private func resizePopoverToFitContent() {
        guard let hosting = hostingView else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let maxHeight = max(screenHeight - 80, 300)
        let target = min(max(fitting.height, 320), maxHeight)
        hosting.setFrameSize(NSSize(width: 340, height: target))
        popover.contentSize = NSSize(width: 340, height: target)
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate() // 让输入框可编辑
        installDismissMonitors()
    }

    // MARK: - 点击外部自动收起

    /// 安装收起监视器：点击弹窗外任意区域（其他 App、桌面、本 App 其他窗口）、按 Esc、
    /// 或应用失活（Cmd+Tab 切走）时收起弹窗
    private func installDismissMonitors() {
        let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // 其他应用的点击（桌面、别的 App 窗口）
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] _ in
            // 全局监视器回调可能不在主线程派发，收起动作回主线程执行
            DispatchQueue.main.async { self?.closePopover() }
        }

        // 本应用内的点击：弹窗外（其他窗口、无窗口区域）也收起
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            // 状态栏图标上的点击交给 toggle 逻辑处理（避免先收起又被重新打开）
            if event.window === self.statusItem.button?.window { return event }
            // 弹窗内容区域内的点击正常传递（按钮等控件仍可点击）
            if event.window === self.popover.contentViewController?.view.window { return event }
            self.popover.performClose(nil)
            return event
        }

        // Esc 键收起
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown, event.keyCode == 53 else { return event }
            self.popover.performClose(nil)
            return nil // 吞掉 Esc，避免触发其他快捷键
        }

        // 应用失活（Cmd+Tab 切走、点击其他 App）时收起
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func removeDismissMonitors() {
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = escapeKeyMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = resignActiveObserver { NotificationCenter.default.removeObserver(observer) }
        globalClickMonitor = nil
        localClickMonitor = nil
        escapeKeyMonitor = nil
        resignActiveObserver = nil
    }

    // MARK: - 菜单栏渲染

    func render() {
        guard let button = statusItem.button else { return }
        let model = self.model
        button.attributedTitle = Self.attributedTitle(for: model)
        button.image = Self.icon(for: model)
        button.toolTip = Self.tooltip(for: model)
    }

    private static func attributedTitle(for model: AppModel?) -> NSAttributedString {
        let text: String
        if let balance = model?.lastBalance {
            text = "\(currencySymbol(balance.currency))\(format(balance.total))"
        } else {
            text = "—"
        }
        return NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: titleColor(for: model),
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ]
        )
    }

    private static func titleColor(for model: AppModel?) -> NSColor {
        guard let model else { return .labelColor }
        switch model.status {
        case .fresh:
            if let balance = model.lastBalance {
                if balance.total < 1 { return .systemRed }
                if balance.total < 10 { return .systemOrange }
            }
            return .labelColor
        case .stale:
            return .systemOrange
        case .error, .tokenExpired:
            return .systemRed
        default:
            return .labelColor
        }
    }

    private static func icon(for model: AppModel?) -> NSImage? {
        // 鲸鱼娘托盘图标（与 Windows 版一致）；未随包分发时回退 SF Symbol
        if let path = Bundle.main.path(forResource: "whale-girl-tray", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        let name = model?.isFetching == true ? "arrow.triangle.2.circlepath" : "sparkles"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "DeepSeek Meter")
        image?.isTemplate = true
        return image
    }

    private static func tooltip(for model: AppModel?) -> String {
        guard let model else { return "DeepSeek Meter" }
        switch model.status {
        case .tokenExpired:
            return "登录已过期，点击重新登录"
        case .error:
            return model.lastError ?? "获取失败"
        case .stale:
            var stale = model.lastError ?? "数据可能已过期"
            if let lastUpdate = model.lastUpdate {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                stale += " · 最后成功 \(formatter.string(from: lastUpdate))"
            }
            return stale
        default:
            break
        }
        guard let lastUpdate = model.lastUpdate else {
            return model.lastError ?? "DeepSeek Meter"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "DeepSeek Meter · 最后更新 \(formatter.string(from: lastUpdate))"
    }
}
