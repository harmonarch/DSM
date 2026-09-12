import SwiftUI
import AppKit

/// 悬浮窗主界面
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @State private var trendMetric: TrendMetric = .output

    private var balance: BalanceInfo? { model.lastBalance }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                balanceSection
                usageSection
                tokenTrendSection
                if let error = model.lastError {
                    errorBanner(error)
                }
                Divider()
                settingsSection
                footer
            }
            .padding(14)
            .frame(width: 340)
        }
        .frame(width: 340)
        .scrollIndicators(.hidden)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
            Text("DeepSeek Meter")
                .font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 4)
            statusPill
            if let lastUpdate = model.lastUpdate {
                Text(lastUpdate.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 服务状态胶囊：点击打开官方服务状态页（status.deepseek.com）查看可用性
    private var statusPill: some View {
        Button {
            if let url = URL(string: "https://status.deepseek.com/") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("点击打开 status.deepseek.com 查看 DeepSeek 服务可用性")
    }

    private var statusColor: Color {
        switch model.status {
        case .fresh: return .green
        case .stale: return .orange
        case .error, .tokenExpired: return .red
        default: return .gray
        }
    }

    private var statusText: String {
        switch model.status {
        case .fresh: return "可用"
        case .stale: return "数据可能过期"
        case .error: return "异常"
        case .tokenExpired: return "已过期"
        case .loading: return "加载中"
        case .notLoggedIn: return "未登录"
        }
    }

    // MARK: - 余额

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("总余额")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                tariffPill
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(currencySymbol(balance?.currency ?? "CNY"))
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(format(balance?.total ?? 0))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy, value: balance?.total)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    miniStat(title: "赠送余额", value: balance?.granted, currency: balance?.currency)
                    miniStat(title: "充值余额", value: balance?.toppedUp, currency: balance?.currency)
                }
            }
            runwayRow
            HStack(spacing: 8) {
                rechargeButton
                Spacer()
                if let currency = balance?.currency {
                    Text("币种：\(currency)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(GlassCardBackground())
    }

    /// 一键打开 DeepSeek 官方充值页（platform.deepseek.com/top_up）
    private var rechargeButton: some View {
        Button {
            if let url = URL(string: "https://platform.deepseek.com/top_up") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("前往充值", systemImage: "creditcard.fill")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .help("打开 DeepSeek 官方充值页")
    }

    /// 当前峰谷时段徽章：按官方定价每 30 秒自动重判，悬停可看规则说明
    private var tariffPill: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let isPeak = tariffPeriod(on: context.date) == .peak
            let tint: Color = isPeak ? .orange : .teal
            HStack(spacing: 4) {
                Image(systemName: isPeak ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(isPeak ? "高峰时段" : "低谷时段")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .help(isPeak
                  ? "高峰时段（北京时间周一至周五 9:00–12:00、14:00–18:00），单价为低谷时段的两倍"
                  : "低谷时段（高峰以外全部时间，周末全天），价格为高峰的一半")
        }
    }

    private func miniStat(title: String, value: Double?, currency: String?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { "\(currencySymbol(currency ?? "CNY"))\(format($0))" } ?? "—")
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
    }

    // MARK: - 续航（余额 ÷ 近 7 日日均费用，满格 = 30 天；与 Android 端仪表同口径）

    /// 续航读数行：文字读数在左、细余量条在右——油表的平面化，容量一眼可读
    private var runwayRow: some View {
        let readout = runwayReadout(balance: balance?.total ?? 0, usage: model.monthUsage)
        return HStack(spacing: 8) {
            Text(readout.label)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(runwayTint(readout.level))
            Spacer()
            RunwayBar(ratio: readout.ratio, level: readout.level)
        }
        .animation(.snappy, value: readout)
    }

    /// 读数配色：正常态保持中性（强调色留给余量条），警示态沿用状态色语义
    private func runwayTint(_ level: RunwayLevel) -> Color {
        switch level {
        case .healthy: return .secondary
        case .warning: return .orange
        case .exhausted: return .red
        case .unknown: return .secondary.opacity(0.55)
        }
    }

    // MARK: - 本月用量

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.platformTokenExpired {
                // Token 过期最优先：不能被已有 monthUsage 遮住
                expiredOrErrorPrompt
            } else if let usage = model.monthUsage {
                let symbol = currencySymbol(model.currency)
                HStack(spacing: 6) {
                    Text("\(usage.year)年\(usage.month)月用量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("累计 \(symbol)\(format(usage.totalCost))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                HStack(spacing: 10) {
                    statCell(title: "今日费用", value: "\(symbol)\(format(usage.cost(on: Date())))")
                    let today = usage.tokens(on: Date())
                    statCell(title: "今日请求", value: Self.countString(today.requests))
                    statCell(title: "今日输出", value: Self.tokenString(today.response))
                }
                HStack(spacing: 10) {
                    statCell(title: "本月请求", value: Self.countString(usage.totalRequests))
                    statCell(title: "本月输出", value: Self.tokenString(usage.responseTokens))
                    statCell(title: "缓存命中", value: Self.tokenString(usage.cacheHitTokens))
                }
                ForEach(usage.amountModels.filter { $0.requests > 0 }) { item in
                    HStack {
                        Text(Self.modelDisplayName(item.model))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let cost = usage.costModels.first(where: { $0.model == item.model })?
                            .usage.reduce(0) { $0 + $1.value } ?? 0
                        Text("\(Self.countString(item.requests)) 次 · \(symbol)\(format(cost))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else if model.usageError != nil {
                expiredOrErrorPrompt
            } else if model.isFetching {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("加载用量…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                loginPrompt
            }
        }
        .padding(12)
        .background(GlassCardBackground())
    }

    private var loginPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.key")
                    .foregroundStyle(.secondary)
                Text("登录后显示余额与用量明细")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Button {
                model.beginPlatformLogin()
            } label: {
                Label("一键登录", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var expiredOrErrorPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(model.platformTokenExpired ? "平台登录已过期，请重新登录" : (model.usageError ?? "用量获取失败"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Button {
                model.beginPlatformLogin()
            } label: {
                Label("重新登录", systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Token 用量趋势（本月按天）

    private var tokenTrendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Token 用量趋势")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $trendMetric) {
                    ForEach(TrendMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 138)
            }

            if let usage = model.monthUsage {
                let entries = tokenDailyEntries(usage: usage, metric: trendMetric)
                if entries.isEmpty {
                    Text("本月暂无用量数据")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    TokenDailyChart(entries: entries)
                        .frame(height: 42)
                    HStack(spacing: 4) {
                        Text("今日 \(Self.tokenString(dailyValue(usage: usage, on: Date(), metric: trendMetric)))")
                        Spacer()
                        if let peak = entries.max(by: { $0.value < $1.value }) {
                            Text("峰值 \(Self.tokenString(peak.value))（\(Self.dayLabel(peak.date))）")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else if model.usageError == nil && !model.isFetching {
                Text("登录后查看 Token 用量趋势")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(GlassCardBackground())
    }

    // MARK: - 错误提示

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 设置

    private var settingsSection: some View {
        VStack(spacing: 12) {
            // 平台 Token（一键登录）
            HStack(spacing: 8) {
                Text("平台账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                if model.settings.platformToken.isEmpty {
                    Text("未登录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("登录") { model.beginPlatformLogin() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Text("已登录 ✓")
                        .font(.caption)
                        .foregroundStyle(.green)
                    if !model.settings.platformUserName.isEmpty {
                        Text(model.settings.platformUserName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("重新登录") { model.beginPlatformLogin() }
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
            }

            // 刷新间隔
            HStack(spacing: 8) {
                Text("刷新间隔")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Picker("", selection: intervalBinding) {
                    ForEach(SettingsStore.intervalOptions, id: \.self) { interval in
                        Text(Self.intervalLabel(interval)).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                Spacer(minLength: 0)
            }

            // 开机自启：开关右对齐
            HStack(spacing: 8) {
                Text("开机自启")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Spacer(minLength: 0)
                Toggle("", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            // 检查更新（GitHub Release 检查 / 下载 / 覆盖安装）：左版本号，右按钮与状态
            updateRow
        }
    }

    /// 更新行：左边当前版本号，右边检查更新按钮 / 下载进度 / 重启提示
    private var updateRow: some View {
        HStack(spacing: 8) {
            Text(versionText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            updateStatusControl
        }
    }

    /// 当前版本号（swift run 等非 .app 环境没有版本信息）
    private var versionText: String {
        UpdateService.currentVersion.map { "v\($0)" } ?? "开发构建"
    }

    /// 检查更新按钮：非开发构建下常驻可点，检查完成后仍可再次检查
    private var checkUpdatesButton: some View {
        Button("检查更新") { model.update.checkForUpdates() }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    @ViewBuilder
    private var updateStatusControl: some View {
        switch model.update.state {
        case .idle:
            if !model.update.isDevBuild {
                checkUpdatesButton
            }
        case .checking:
            // 检查中：loading 在更新行原位展示
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("检查中…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        case .upToDate:
            HStack(spacing: 10) {
                Text("暂无更新✅")
                    .font(.caption)
                    .foregroundStyle(.green)
                checkUpdatesButton
            }
        case .downloading(let progress):
            // 下载进度替代检查更新按钮的原位展示
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 130)
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, alignment: .trailing)
            }
            .help("正在下载 v\(model.update.pendingVersion ?? "")")
        case .readyToInstall:
            Button("重启生效") {
                model.update.installDownloadedUpdate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("新版本 v\(model.update.pendingVersion ?? "") 已下载完成，重启后覆盖安装（余额、设置自动保留）")
        case .installing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("正在替换应用…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重试") { model.update.checkForUpdates() }
                    .buttonStyle(.link)
                    .controlSize(.small)
            }
        }
    }

    private var intervalBinding: Binding<TimeInterval> {
        Binding(
            get: { model.settings.refreshInterval },
            set: { model.setRefreshInterval($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.settings.launchAtLogin },
            set: { model.settings.launchAtLogin = $0 }
        )
    }

    private static func intervalLabel(_ interval: TimeInterval) -> String {
        switch interval {
        case 15: return "15秒"
        case 30: return "30秒"
        case 60: return "1分"
        case 300: return "5分"
        case 600: return "10分"
        default: return "\(Int(interval))s"
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack {
            if !model.settings.platformToken.isEmpty {
                Button("退出登录") { model.clearPlatformToken() }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - 格式化工具

    private static func countString(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func tokenString(_ n: Double) -> String {
        if n >= 1e8 { return String(format: "%.2f亿", n / 1e8) }
        if n >= 1e4 { return String(format: "%.1f万", n / 1e4) }
        return format(n)
    }

    private static func modelDisplayName(_ model: String) -> String {
        model.replacingOccurrences(of: "deepseek-", with: "")
    }

    // MARK: - Token 趋势工具

    private func tokenDailyEntries(usage: MonthUsage, metric: TrendMetric) -> [TokenDailyEntry] {
        let todayKey = Self.dayParser.string(from: Date())
        return usage.amountDays.compactMap { day -> TokenDailyEntry? in
            guard day.date <= todayKey, let date = Self.dayParser.date(from: day.date) else { return nil }
            return TokenDailyEntry(date: date, value: dailyValue(day: day, metric: metric))
        }
    }

    private func dailyValue(usage: MonthUsage, on date: Date, metric: TrendMetric) -> Double {
        let key = Self.dayParser.string(from: date)
        guard let day = usage.amountDays.first(where: { $0.date == key }) else { return 0 }
        return dailyValue(day: day, metric: metric)
    }

    private func dailyValue(day: UsageDay, metric: TrendMetric) -> Double {
        let resp = day.data.reduce(0) { $0 + $1.value(for: "RESPONSE_TOKEN") }
        let hit = day.data.reduce(0) { $0 + $1.value(for: "PROMPT_CACHE_HIT_TOKEN") }
        let miss = day.data.reduce(0) { $0 + $1.value(for: "PROMPT_CACHE_MISS_TOKEN") }
        switch metric {
        case .output: return resp
        case .cacheHit: return hit
        case .total: return resp + hit + miss
        }
    }

    private static var dayParser: DateFormatter {
        MonthUsage.dayFormatter
    }

    private static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        return "\(cal.component(.month, from: date))月\(cal.component(.day, from: date))日"
    }
}

/// Token 趋势指标
enum TrendMetric: String, CaseIterable, Identifiable {
    case output = "输出"
    case cacheHit = "缓存命中"
    case total = "总量"
    var id: String { rawValue }
}


/// 续航余量条：满格 = 30 天（与 Android 端仪表满弧同语义的平面版）；
/// 正常态品牌蓝填充，警示/耗尽沿用状态色，数据未就绪只留轨道
private struct RunwayBar: View {
    let ratio: Double
    let level: RunwayLevel

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 64, height: 4)
            .overlay(alignment: .leading) {
                if fillWidth > 0 {
                    Capsule()
                        .fill(fillColor)
                        .frame(width: fillWidth)
                }
            }
            .clipShape(Capsule())
    }

    /// 比率极小（不足 1 天）时保留 3pt 最小可见宽度，让「快见底」仍然可读
    private var fillWidth: CGFloat {
        guard level != .unknown, ratio > 0 else { return 0 }
        return min(64, max(3, 64 * ratio))
    }

    private var fillColor: Color {
        switch level {
        case .healthy: return .blue
        case .warning: return .orange
        case .exhausted: return .red
        case .unknown: return .clear
        }
    }
}

/// 玻璃卡片底衬：极淡的自适应填充 + 发丝描边，让底层 vibrancy 材质透出来
private struct GlassCardBackground: View {
    var cornerRadius: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}
