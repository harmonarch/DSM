import Foundation

// MARK: - 服务健康度

/// DeepSeek 官方服务状态页（status.deepseek.com）反映的服务健康度。
/// 与 `DataStatus`（数据可信度：余额/用量拉没拉到）是两个独立维度，不要混用。
enum ServiceHealth: Equatable {
    /// 运行正常
    case operational
    /// 性能下降
    case degraded
    /// 部分中断
    case partialOutage
    /// 完全中断
    case fullOutage
    /// 维护中（计划内）
    case maintenance
    /// 未取到或解析失败——不代表服务正常，UI 需如实呈现为「状态未知」
    case unknown

    /// 严重度，用于在多个受影响组件/事件之间取最差
    var severity: Int {
        switch self {
        case .unknown: return 0
        case .operational: return 1
        case .maintenance: return 2
        case .degraded: return 3
        case .partialOutage: return 4
        case .fullOutage: return 5
        }
    }

    /// UI 文案（与 Flashduty 状态页的四档影响状态 + 维护中一致）
    var label: String {
        switch self {
        case .operational: return "运行正常"
        case .degraded: return "性能下降"
        case .partialOutage: return "部分中断"
        case .fullOutage: return "完全中断"
        case .maintenance: return "维护中"
        case .unknown: return "状态未知"
        }
    }

    /// 是否处于故障/维护期（用于 UI 决定要不要展开事件详情）
    var isIncident: Bool {
        switch self {
        case .degraded, .partialOutage, .fullOutage, .maintenance: return true
        case .operational, .unknown: return false
        }
    }
}

/// 状态页的一次判定结果：健康度，外加进行中事件的标题与开始时间（无事件时为 nil）
struct ServiceStatusSnapshot: Equatable {
    var health: ServiceHealth
    var incidentTitle: String?
    var startedAt: Date?

    init(health: ServiceHealth, incidentTitle: String? = nil, startedAt: Date? = nil) {
        self.health = health
        self.incidentTitle = incidentTitle
        self.startedAt = startedAt
    }
}

// MARK: - 解析（纯函数，可测）

/// Flashduty 状态页的影响状态字面量 -> ServiceHealth；无法识别返回 nil。
/// 取值见 Flashduty 文档「影响状态」：operational / degraded(_performance) / partial_outage /
/// full_outage / under_maintenance（维护另有 maintenance 写法）
func serviceHealth(fromImpactStatus raw: String) -> ServiceHealth? {
    switch raw.lowercased() {
    case "operational":
        return .operational
    case "degraded", "degraded_performance":
        return .degraded
    case "partial_outage":
        return .partialOutage
    case "full_outage":
        return .fullOutage
    case "under_maintenance", "maintenance":
        return .maintenance
    default:
        return nil
    }
}

/// 解析 Next.js RSC 数据流（GET `/` 带 `RSC: 1`），判定当前服务健康度与进行中事件。
///
/// `active_changes` 是网页 UI 实际渲染的数据源：为空数组即当前无进行中事件。
/// 有进行中事件时，取其中受影响组件里最严重的影响状态，并带上**该条**事件的标题与开始时间；
/// 组件级影响缺失（字段结构变化）时退化为按事件类型推断，避免把「有故障」误判成「正常」。
/// 找不到 `active_changes`（页面结构变更）返回 nil，交给 RSS 兜底。
func serviceStatusFromRSC(_ payload: String) -> ServiceStatusSnapshot? {
    guard let array = jsonArray(after: "\"active_changes\":", in: payload),
          let json = try? JSONSerialization.jsonObject(with: Data(array.utf8)),
          let changes = json as? [[String: Any]] else { return nil }

    guard !changes.isEmpty else { return ServiceStatusSnapshot(health: .operational) }

    var worst: ServiceStatusSnapshot?
    for change in changes {
        var changeHealth: ServiceHealth?
        for component in (change["affected_components"] as? [[String: Any]]) ?? [] {
            guard let raw = component["status"] as? String,
                  let health = serviceHealth(fromImpactStatus: raw) else { continue }
            changeHealth = serviceStatusMoreSevere(changeHealth, health)
        }
        // 有进行中事件却读不到组件影响：维护按时段推断，其余至少记为性能下降
        let fallback: ServiceHealth = (change["type"] as? String) == "maintenance" ? .maintenance : .degraded
        let candidate = ServiceStatusSnapshot(
            health: changeHealth ?? fallback,
            incidentTitle: change["title"] as? String,
            startedAt: (change["start_at_seconds"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        )
        worst = serviceStatusMoreSevere(worst, candidate)
    }
    return worst ?? ServiceStatusSnapshot(health: .operational)
}

/// 解析 `/history.rss`（标准 RSS 2.0），判定当前服务健康度与进行中事件。
///
/// RSS 的条目状态（resolved / investigating / monitoring …）是**事件流转状态**而非影响程度，
/// 因此影响程度只能从标题 best-effort 推断。另外该 feed 是否收录「进行中」事件未经证实，
/// 所以它只作 RSC 的兜底，不作主数据源。解析不出任何条目返回 nil。
func serviceStatusFromRSS(_ xml: String) -> ServiceStatusSnapshot? {
    let items = serviceStatusCaptures("<item>(.*?)</item>", in: xml)
    guard !items.isEmpty else { return nil }

    var worst: ServiceStatusSnapshot?
    for item in items {
        guard let rawDescription = serviceStatusCaptures("<description>(.*?)</description>", in: item).first,
              let status = serviceStatusFirstCapture(
                  "Status:\\s*(?:</strong>)?\\s*([A-Za-z_]+)",
                  in: serviceStatusDecodeXMLEntities(rawDescription))
        else { continue }

        let normalized = status.lowercased()
        // resolved / completed 是终态，其余（investigating / identified / monitoring）为进行中
        if normalized == "resolved" || normalized == "completed" { continue }

        let title = serviceStatusCaptures("<title>(.*?)</title>", in: item).first ?? ""
        let pubDate = serviceStatusCaptures("<pubDate>(.*?)</pubDate>", in: item).first
        let candidate = ServiceStatusSnapshot(
            health: serviceHealthFromIncidentTitle(title),
            incidentTitle: title,
            // RSS 的 pubDate 实测等于事件开始时间（同一条 resolved 事件：pubDate == start_at_seconds）
            startedAt: pubDate.flatMap(serviceStatusDateFromRFC822)
        )
        worst = serviceStatusMoreSevere(worst, candidate)
    }
    return worst ?? ServiceStatusSnapshot(health: .operational)
}

/// 从事件标题推断影响程度（RSS 不携带结构化影响状态，仅用于兜底）
func serviceHealthFromIncidentTitle(_ title: String) -> ServiceHealth {
    let lowered = title.lowercased()
    if lowered.contains("完全中断") || lowered.contains("full outage") { return .fullOutage }
    if lowered.contains("部分中断") || lowered.contains("partial outage")
        || lowered.contains("partially unavailable") { return .partialOutage }
    if lowered.contains("维护") || lowered.contains("maintenance") { return .maintenance }
    // 有进行中事件但读不出程度，至少记为性能下降而不是正常
    return .degraded
}

/// 事件标题里的中英对照很长（如「DeepSeek 网页/API 性能下降（DeepSeek Web/API Degraded Performance）」），
/// 悬浮窗空间有限，截到中文名（括号前）即可
func serviceStatusShortTitle(_ title: String) -> String {
    for separator in ["（", "("] {
        if let range = title.range(of: separator) {
            let head = title[title.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { return head }
        }
    }
    return title.trimmingCharacters(in: .whitespaces)
}

/// 解析 RSS 的 RFC822 时间（如 `Wed, 23 Sep 2026 15:35:33 +0800`）
func serviceStatusDateFromRFC822(_ raw: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    return formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines))
}

// MARK: - 解析辅助

/// 取两者中更严重的一个用于展示；左侧为 nil 时返回右侧
private func serviceStatusMoreSevere(_ lhs: ServiceStatusSnapshot?, _ rhs: ServiceStatusSnapshot) -> ServiceStatusSnapshot {
    guard let lhs else { return rhs }
    return rhs.health.severity > lhs.health.severity ? rhs : lhs
}

/// 取两者中更严重的一个；左侧为 nil 时返回右侧
private func serviceStatusMoreSevere(_ lhs: ServiceHealth?, _ rhs: ServiceHealth) -> ServiceHealth {
    guard let lhs else { return rhs }
    return rhs.severity > lhs.severity ? rhs : lhs
}

/// 按正则取捕获组 1 的全部匹配（跨行匹配）
private func serviceStatusCaptures(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return []
    }
    let nsText = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
        guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
        return nsText.substring(with: match.range(at: 1))
    }
}

/// 按正则取捕获组 1 的第一个匹配
private func serviceStatusFirstCapture(_ pattern: String, in text: String) -> String? {
    serviceStatusCaptures(pattern, in: text).first
}

/// 解出 RSS description 里的 XML 实体（内容以 &lt;p&gt; 形式转义）
private func serviceStatusDecodeXMLEntities(_ text: String) -> String {
    var decoded = text
    decoded = decoded.replacingOccurrences(of: "&lt;", with: "<")
    decoded = decoded.replacingOccurrences(of: "&gt;", with: ">")
    decoded = decoded.replacingOccurrences(of: "&quot;", with: "\"")
    decoded = decoded.replacingOccurrences(of: "&#39;", with: "'")
    decoded = decoded.replacingOccurrences(of: "&apos;", with: "'")
    // &amp; 必须最后解，否则会把 &amp;lt; 二次解成 <
    decoded = decoded.replacingOccurrences(of: "&amp;", with: "&")
    return decoded
}

/// 从 JSON 文本中取出某个 key 之后的数组字面量（按括号配对，跳过字符串内的括号与转义）
private func jsonArray(after key: String, in text: String) -> String? {
    guard let keyRange = text.range(of: key) else { return nil }

    var index = keyRange.upperBound
    while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
    guard index < text.endIndex, text[index] == "[" else { return nil }

    let start = index
    var depth = 0
    var inString = false
    var escaped = false
    while index < text.endIndex {
        let character = text[index]
        if inString {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString = false
            }
        } else if character == "\"" {
            inString = true
        } else if character == "[" || character == "{" {
            depth += 1
        } else if character == "]" || character == "}" {
            depth -= 1
            if depth == 0 { return String(text[start...index]) }
        }
        index = text.index(after: index)
    }
    return nil
}
