import Foundation

/// DeepSeek 官方服务状态页（status.deepseek.com）客户端：只读、无鉴权、无账户信息。
///
/// 该页由 Flashduty 托管，**没有公开 JSON API**——原 Atlassian Statuspage 的 `/api/v2/*`
/// 随迁移失效（实测返回 `{"code":"RouteNotFound"}`）。因此改读页面自身的两个公开只读数据源：
/// 1. 主：GET `/` 带 `RSC: 1` 头，取 Next.js 服务端数据流里的 `active_changes`
///    （网页 UI 实际渲染的状态，含受影响组件与精确影响状态）
/// 2. 备：GET `/history.rss`，标准 RSS 2.0（Flashduty 声明兼容 Atlassian 的 history.rss 格式），
///    RSC 内部结构变更时兜底
///
/// 与 PlatformService（platform.deepseek.com 私有接口 + Token 鉴权）分属两个独立网络入口；
/// 与 UpdateService（GitHub Release）同理，只读且不上报任何本地数据（红线 5）。
struct ServiceStatusService {
    private static let statusPageURL = "https://status.deepseek.com/"
    private static let rssURL = "https://status.deepseek.com/history.rss"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    /// 取当前服务状态。两个数据源都拿不到时返回 `.unknown`（不抛错——
    /// 状态页不可用不该让整个悬浮窗报错，也不该被误显示成「运行正常」）。
    func fetchStatus() async -> ServiceStatusSnapshot {
        if let payload = await get(Self.statusPageURL, rsc: true),
           let status = serviceStatusFromRSC(payload) {
            return status
        }
        if let xml = await get(Self.rssURL),
           let status = serviceStatusFromRSS(xml) {
            return status
        }
        return ServiceStatusSnapshot(health: .unknown)
    }

    /// GET 文本响应；失败（网络错误 / 非 200 / 编码失败）返回 nil
    private func get(_ urlString: String, rsc: Bool = false) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        // Next.js App Router：带 RSC 头时只回服务端数据流（未转义的 JSON），省去解析 HTML 外壳
        if rsc {
            request.setValue("1", forHTTPHeaderField: "RSC")
        }
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }

        return String(data: data, encoding: .utf8)
    }
}
