import Foundation

// 轻量自测（不依赖 XCTest，命令行工具环境可直接运行）
var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("✅ \(name)")
    } else {
        failures += 1
        print("❌ \(name)")
    }
}

// 1. 格式化与币种符号
check(format(110.0) == "110.00", "format(110.0) -> 110.00")
check(format(0.35) == "0.35", "format(0.35) -> 0.35")
check(format(1234.5) == "1234.5", "format(1234.5) -> 1234.5")
check(currencySymbol("CNY") == "¥", "CNY -> ¥")
check(currencySymbol("USD") == "$", "USD -> $")
check(currencySymbol("EUR") == "€", "EUR -> €")
check(currencySymbol("HKD") == "HK$", "HKD -> HK$")
check(currencySymbol("GBP") == "£", "GBP -> £")
check(currencySymbol("XXX") == "XXX", "未知币种原样返回")

// 1.5 平台时区对齐：北京时间（UTC+8）计日，与 usage/cost、usage/amount 的 days 口径一致
// 用例 1（跨日边界）：UTC 8/14 16:30 即北京时间 8/15 00:30，必须归入 8/15（本地时区为 UTC 时会错位成 8/14）
let cnMidnight = Calendar(identifier: .gregorian)
    .date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 8, day: 14, hour: 16, minute: 30))!
check(MonthUsage.dayFormatter.string(from: cnMidnight) == "2026-08-15", "UTC 8/14 16:30 按北京时间归入 8/15")
// 用例 2（当日末尾）：北京 8/15 23:30 仍属 8/15（本地时区快于 UTC+8 时会错位成 8/16）
let shLate = Calendar(identifier: .gregorian)
    .date(from: DateComponents(timeZone: TimeZone(identifier: "Asia/Shanghai"), year: 2026, month: 8, day: 15, hour: 23, minute: 30))!
check(MonthUsage.dayFormatter.string(from: shLate) == "2026-08-15", "北京 8/15 23:30 仍归入 8/15")

func XCTUnwrapSafe<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "unwrap", code: 1) }
    return value
}

func PopoverViewHelpersCountString(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
}

// 2. usage/amount 解码（真实返回结构）
let amountJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"total":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_TOKEN","amount":"0"},{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"311932800"},{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"1584089"},{"type":"RESPONSE_TOKEN","amount":"950284"},{"type":"REQUEST","amount":"1130"}]}],"days":[{"date":"2026-08-01","data":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"100"},{"type":"RESPONSE_TOKEN","amount":"50"},{"type":"REQUEST","amount":"2"}]}]}]}}}
"""
do {
    struct AmountBiz: Decodable { let bizData: UsageData }
    struct AmountResp: Decodable { let code: Int; let data: AmountBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(AmountResp.self, from: Data(amountJSON.utf8))
    check(resp.code == 0, "amount 外层 code")
    let usage = try XCTUnwrapSafe(resp.data?.bizData)
    check(usage.total.count == 1, "amount 模型数")
    let model = usage.total[0]
    check(model.model == "deepseek-v4-pro", "amount 模型名")
    check(abs(model.value(for: "PROMPT_CACHE_HIT_TOKEN") - 311932800) < 1, "amount 缓存命中")
    check(abs(model.value(for: "RESPONSE_TOKEN") - 950284) < 1, "amount 输出 token")
    check(model.requests == 1130, "amount 请求数")
    check(usage.days?.count == 1, "amount days")
    if let day = usage.days?.first {
        check(day.date == "2026-08-01", "amount 日期")
        check(day.data[0].requests == 2, "amount 当日请求")
    }
} catch {
    check(false, "amount 解码抛错：\(error)")
}

// 3. usage/cost 解码（biz_data 是数组）
let costJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":[{"total":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"7.7983200000000000"},{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"4.7522670000000000"},{"type":"RESPONSE_TOKEN","amount":"5.7017040000000000"}]}],"days":[]}]}}
"""
do {
    struct CostBiz: Decodable { let bizData: [UsageData] }
    struct CostResp: Decodable { let code: Int; let data: CostBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(CostResp.self, from: Data(costJSON.utf8))
    let data = try XCTUnwrapSafe(resp.data?.bizData.first)
    let total = data.total[0].usage.reduce(0) { $0 + $1.value }
    check(abs(total - 18.252291) < 0.001, "cost 费用合计 18.252291")
} catch {
    check(false, "cost 解码抛错：\(error)")
}

// 4. get_user_summary 解码（snake_case）
let summaryJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"normal_wallets":[{"currency":"CNY","balance":"40.2492316400000000","token_estimation":"0"}],"bonus_wallets":[{"currency":"CNY","balance":"0","token_estimation":"0"}],"total_costs":[{"currency":"CNY","amount":"19.7507683600000000"}]}}}
"""
do {
    struct SummaryBiz: Decodable { let bizData: UserSummary }
    struct SummaryResp: Decodable { let code: Int; let data: SummaryBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(SummaryResp.self, from: Data(summaryJSON.utf8))
    let summary = try XCTUnwrapSafe(resp.data?.bizData)
    check(abs(summary.normalWallets[0].value - 40.24923164) < 0.0001, "summary 余额 40.25")
    check(abs(summary.totalCosts[0].value - 19.75076836) < 0.0001, "summary 累计消费 19.75")
} catch {
    check(false, "summary 解码抛错：\(error)")
}

// 5. 格式化工具
check(format(311932800.0) == "311932800.0", "大数格式化")
check(PopoverViewHelpersCountString(1130) == "1,130", "千分位")

// 6. biz_code != 0 解码（业务错误识别）
let bizErrJSON = """
{"code":0,"msg":"","data":{"biz_code":10001,"biz_msg":"业务错误","biz_data":null}}
"""
do {
    struct BizErrBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: UsageData? }
    struct BizErrResp: Decodable { let code: Int; let data: BizErrBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(BizErrResp.self, from: Data(bizErrJSON.utf8))
    check(resp.data?.bizCode == 10001, "biz_code 非 0 正确解码")
} catch {
    check(false, "biz_code 解码抛错：\(error)")
}

// 7. 空 data / 空 biz_data
let emptyDataJSON = """
{"code":0,"msg":"","data":null}
"""
do {
    struct EmptyBiz: Decodable { let bizData: UsageData? }
    struct EmptyResp: Decodable { let code: Int; let data: EmptyBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(EmptyResp.self, from: Data(emptyDataJSON.utf8))
    check(resp.data == nil, "空 data 解码为 nil")
} catch {
    check(false, "空 data 解码抛错：\(error)")
}

let emptyBizDataJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":null}}
"""
do {
    struct EmptyBiz2: Decodable { let bizData: UsageData? }
    struct EmptyResp2: Decodable { let code: Int; let data: EmptyBiz2? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(EmptyResp2.self, from: Data(emptyBizDataJSON.utf8))
    check(resp.data != nil && resp.data?.bizData == nil, "空 biz_data 解码为 nil")
} catch {
    check(false, "空 biz_data 解码抛错：\(error)")
}

// 8. 数据可信度状态判定
check(dataStatus(token: "", tokenExpired: false, hasData: false, hasError: false) == .notLoggedIn, "空 token 未登录")
check(dataStatus(token: "tok", tokenExpired: true, hasData: true, hasError: false) == .tokenExpired, "登录过期优先于旧数据")
check(dataStatus(token: "tok", tokenExpired: false, hasData: true, hasError: true) == .stale, "有数据有错误为 stale")
check(dataStatus(token: "tok", tokenExpired: false, hasData: true, hasError: false) == .fresh, "有数据无错误为 fresh")
check(dataStatus(token: "tok", tokenExpired: false, hasData: false, hasError: true) == .error, "无数据有错误为 error")
check(dataStatus(token: "tok", tokenExpired: false, hasData: false, hasError: false) == .loading, "已登录无数据为 loading")

// 9. 空钱包（UserSummary normal_wallets 为空）
let emptyWalletJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"normal_wallets":[],"bonus_wallets":[],"total_costs":[]}}}
"""
do {
    struct SummaryBiz2: Decodable { let bizData: UserSummary }
    struct SummaryResp2: Decodable { let code: Int; let data: SummaryBiz2? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(SummaryResp2.self, from: Data(emptyWalletJSON.utf8))
    check(resp.data?.bizData.normalWallets.isEmpty == true, "空钱包正确解码")
} catch {
    check(false, "空钱包解码抛错：\(error)")
}

// 10. by_api_key 实时接口：解码 + 聚合（start/end 为 Unix 秒，tz=28800，bucket=86400 按天）
// 时间戳：1785513600 = 北京 8/1 00:00，1785600000 = 北京 8/2 00:00
let byKeyAmountJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"usage":{"REQUEST":2,"RESPONSE_TOKEN":100}},{"time":1785600000,"usage":{"REQUEST":5,"RESPONSE_TOKEN":200}}]}]}}}
"""
let byKeyCostJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"data":[{"currency":"CNY","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"1.5"},{"time":1785600000,"cost":"2.5"}]}]}]}}}
"""
do {
    struct AKBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: APIKeyAmountData }
    struct AKResp: Decodable { let code: Int; let data: AKBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let amountResp = try decoder.decode(AKResp.self, from: Data(byKeyAmountJSON.utf8))
    let amountData = amountResp.data?.bizData
    check(amountData?.series.count == 1, "by_api_key amount series 数")
    check(amountData?.series.first?.buckets.count == 2, "by_api_key amount 桶数")
    check(amountData?.series.first?.apiKey.name == "test-key" && amountData?.series.first?.apiKey.trackingId == "test-tracking", "by_api_key api_key 元信息（占位符）")

    struct CKBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: APIKeyCostData }
    struct CKResp: Decodable { let code: Int; let data: CKBiz? }
    let costResp = try decoder.decode(CKResp.self, from: Data(byKeyCostJSON.utf8))
    let costData = costResp.data?.bizData
    check(costData?.data.first?.currency == "CNY", "by_api_key cost 币种")

    // 聚合：按天 + 按模型
    let usage = MonthUsage.aggregated(startTs: 1785513600, endTs: 1788192000, tzSeconds: 28800, amountData: amountData, costData: costData)
    check(usage.year == 2026 && usage.month == 8, "聚合年月（北京时间）")
    check(usage.amountDays.count == 2, "聚合 amount 天数")
    check(usage.amountDays.first?.date == "2026-08-01", "聚合 amount 首日")
    check(usage.amountDays.last?.date == "2026-08-02", "聚合 amount 末日")
    check(usage.amountModels.first?.requests == 7, "聚合本月请求 2+5")
    check(abs((usage.amountModels.first?.value(for: "RESPONSE_TOKEN") ?? 0) - 300) < 0.001, "聚合本月输出 100+200")
    check(usage.costDays.count == 2, "聚合 cost 天数")
    check(abs(usage.cost(on: Date(timeIntervalSince1970: 1785513600)) - 1.5) < 0.001, "聚合 8/1 费用 1.5")
    check(abs(usage.totalCost - 4.0) < 0.001, "聚合本月费用 1.5+2.5")
    // 空数据聚合不崩溃
    let emptyUsage = MonthUsage.aggregated(startTs: 1785513600, endTs: 1788192000, tzSeconds: 28800, amountData: nil, costData: nil)
    check(emptyUsage.amountDays.isEmpty && emptyUsage.totalCost == 0, "空数据聚合为 0")
    // 边界 1：窗口外（下月）的桶被忽略；窗口内 8/31 的桶正常计入
    // 1788105600 = 北京 8/31 00:00，1788192000 = 北京 9/1 00:00（= endTs，窗口外）
    let monthEdgeJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1788105600,"usage":{"REQUEST":3}},{"time":1788192000,"usage":{"REQUEST":99}}]}]}}}
"""
    struct EdgeBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: APIKeyAmountData }
    struct EdgeResp: Decodable { let code: Int; let data: EdgeBiz? }
    let edge = try decoder.decode(EdgeResp.self, from: Data(monthEdgeJSON.utf8)).data?.bizData
    let edgeUsage = MonthUsage.aggregated(startTs: 1785513600, endTs: 1788192000, tzSeconds: 28800, amountData: edge, costData: nil)
    check(edgeUsage.amountDays.count == 1 && edgeUsage.amountDays.first?.date == "2026-08-31", "窗口内 8/31 桶计入")
    check(edgeUsage.amountModels.first?.requests == 3, "窗口外 9/1 桶被忽略（99 不计入）")
    // 边界 2：多币种分组只聚合第一个（CNY），USD 组不混加
    let multiCurrencyJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"data":[{"currency":"CNY","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"1.0"}]}]},{"currency":"USD","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"5.0"}]}]}]}}}
"""
    struct MCBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: APIKeyCostData }
    struct MCResp: Decodable { let code: Int; let data: MCBiz? }
    let mc = try decoder.decode(MCResp.self, from: Data(multiCurrencyJSON.utf8)).data?.bizData
    let mcUsage = MonthUsage.aggregated(startTs: 1785513600, endTs: 1788192000, tzSeconds: 28800, amountData: nil, costData: mc)
    check(abs(mcUsage.totalCost - 1.0) < 0.001, "多币种只聚合第一个分组（CNY 1.0，USD 5.0 不混加）")
} catch {
    check(false, "by_api_key 解码抛错：\(error)")
}

// 11. 峰谷时段判定（官方：北京时间周一至五 9:00–12:00、14:00–18:00 为高峰，其余为低谷，周末全天低谷）
let cnTariffCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}()
func cnTariffDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    cnTariffCal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}
// 2026-09-14 为周一
check(tariffPeriod(on: cnTariffDate(2026, 9, 14, 8, 59)) == .offPeak, "周一 8:59 早间为低谷")
check(tariffPeriod(on: cnTariffDate(2026, 9, 14, 9, 0)) == .peak, "周一 9:00 进入上午高峰")
check(tariffPeriod(on: cnTariffDate(2026, 9, 14, 11, 59)) == .peak, "周一 11:59 仍为高峰")
check(tariffPeriod(on: cnTariffDate(2026, 9, 14, 12, 0)) == .offPeak, "周一 12:00 午间休市为低谷")
check(tariffPeriod(on: cnTariffDate(2026, 9, 14, 14, 0)) == .peak, "周一 14:00 进入下午高峰")
check(tariffPeriod(on: cnTariffDate(2026, 9, 14, 17, 59)) == .peak, "周一 17:59 仍为高峰")
check(tariffPeriod(on: cnTariffDate(2026, 9, 14, 18, 0)) == .offPeak, "周一 18:00 高峰结束为低谷")
check(tariffPeriod(on: cnTariffDate(2026, 9, 14, 0, 30)) == .offPeak, "周一 0:30 凌晨为低谷")
check(tariffPeriod(on: cnTariffDate(2026, 9, 19, 10, 0)) == .offPeak, "周六 10:00 全天低谷")
check(tariffPeriod(on: cnTariffDate(2026, 9, 20, 15, 0)) == .offPeak, "周日 15:00 全天低谷")
// 跨时区不漂移：UTC 周日 21:00 = 北京周一 05:00（低谷）；UTC 周一 01:30 = 北京周一 09:30（高峰）
let utcSunNight = Calendar(identifier: .gregorian)
    .date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 9, day: 13, hour: 21, minute: 0))!
check(tariffPeriod(on: utcSunNight) == .offPeak, "UTC 周日 21:00（北京周一 05:00）为低谷")
let utcMonMorning = Calendar(identifier: .gregorian)
    .date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 9, day: 14, hour: 1, minute: 30))!
check(tariffPeriod(on: utcMonMorning) == .peak, "UTC 周一 01:30（北京周一 09:30）为高峰")

// 12. 续航读数（油表语义：余额 ÷ 近 7 日日均费用，满格 = 30 天；与 Android 端 GaugeHero 同口径）
func runwayBjDate(_ y: Int, _ mo: Int, _ d: Int) -> Date {
    MonthUsage.platformCalendar.date(from: DateComponents(year: y, month: mo, day: d, hour: 12))!
}
func runwayCostDay(_ date: String, _ cost: Double) -> UsageDay {
    UsageDay(date: date, data: [ModelUsage(model: "deepseek-chat", usage: [UsageItem(type: "COST", amount: "\(cost)")])])
}
// 8/1–8/5 每日费用 1..5：验证窗口收缩（月初）、封顶 7 天、无用量日按 0 计
let runwayUsage = MonthUsage(
    year: 2026, month: 8, amountModels: [], costModels: [],
    costDays: [
        runwayCostDay("2026-08-01", 1.0),
        runwayCostDay("2026-08-02", 2.0),
        runwayCostDay("2026-08-03", 3.0),
        runwayCostDay("2026-08-04", 4.0),
        runwayCostDay("2026-08-05", 5.0),
    ],
    amountDays: []
)
check(abs(runwayUsage.recentDailyCost(on: runwayBjDate(2026, 8, 1)) - 1.0) < 0.001, "日均窗口：月初第 1 天只看当天")
check(abs(runwayUsage.recentDailyCost(on: runwayBjDate(2026, 8, 2)) - 1.5) < 0.001, "日均窗口：月初第 2 天为 2 天（(1+2)/2）")
check(abs(runwayUsage.recentDailyCost(on: runwayBjDate(2026, 8, 5)) - 3.0) < 0.001, "日均窗口：本月已过 5 天窗口收缩为 5（15/5=3）")
check(abs(runwayUsage.recentDailyCost(on: runwayBjDate(2026, 8, 8)) - 2.0) < 0.001, "日均窗口：封顶 7 天且无用量日按 0 计（14/7=2）")
check(abs(runwayUsage.recentDailyCost(on: runwayBjDate(2026, 8, 20))) < 0.001, "日均窗口：窗口滑出有数据区间后为 0")
// 四态读数（8/5 的日均 = 3 元）
check(runwayReadout(balance: 9, usage: nil, on: runwayBjDate(2026, 8, 5)).level == .unknown, "用量未就绪：中性「预计可用 —」")
check(runwayReadout(balance: 0, usage: runwayUsage, on: runwayBjDate(2026, 8, 5)).label == "余额已耗尽", "余额 0：耗尽判定优先于无消耗")
check(runwayReadout(balance: 9, usage: runwayUsage, on: runwayBjDate(2026, 8, 20)).label == "近期无消耗", "近 7 日无消耗：满格中性")
let runway10 = runwayReadout(balance: 30, usage: runwayUsage, on: runwayBjDate(2026, 8, 5))
check(runway10.label == "预计可用 10 天" && abs(runway10.ratio - 1.0 / 3.0) < 0.001 && runway10.level == .healthy, "余额 30 日均 3：预计可用 10 天（占比 1/3）")
check(runwayReadout(balance: 90, usage: runwayUsage, on: runwayBjDate(2026, 8, 5)).label == "预计可用 30 天以上", "满 30 天封顶文案")
check(runwayReadout(balance: 90, usage: runwayUsage, on: runwayBjDate(2026, 8, 5)).ratio == 1, "满 30 天占比封顶为 1")
let runwayHalf = runwayReadout(balance: 1.5, usage: runwayUsage, on: runwayBjDate(2026, 8, 5))
check(runwayHalf.label == "预计可用不足 1 天" && runwayHalf.level == .warning, "不足 1 天：警示态")
let runwayFloor = runwayReadout(balance: 89.9, usage: runwayUsage, on: runwayBjDate(2026, 8, 5))
check(runwayFloor.label == "预计可用 29 天" && runwayFloor.level == .healthy, "天数向下取整（29.96…→29）")

// 13. 版本号比较（应用内更新判断：GitHub tag 与本地版本比较）
check(isVersion("0.0.6", newerThan: "0.0.5"), "patch 位更新判定为更新")
check(isVersion("v0.1.0", newerThan: "0.0.9"), "v 前缀剥离 + minor 位更新")
check(isVersion("V1.2.0", newerThan: "1.1.99"), "大写 V 前缀剥离")
check(!isVersion("0.0.5", newerThan: "0.0.5"), "相同版本不算更新")
check(!isVersion("0.0.4", newerThan: "0.0.5"), "旧版本不算更新")
check(!isVersion("1.0", newerThan: "1.0.0"), "段数不齐按 0 补齐后相等")
check(isVersion("1.0.1", newerThan: "1.0"), "缺段按 0 补齐可比较")
check(isVersion("10.0", newerThan: "9.9"), "按数值而非字符串比较（10 > 9）")
check(!isVersion("abc", newerThan: "0.0.1"), "非法版本按 0 处理不算更新")

if failures > 0 {
    print("\n❌ \(failures) 项未通过")
    exit(1)
}
print("\n✅ 全部通过")