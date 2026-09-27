import Foundation

// MARK: - 按 API Key 聚合（by_api_key 序列 -> 每个 Key 的本月用量）
// MonthUsage.aggregated 只按 model 归并，apiKey 元信息被丢弃；本文件补齐「按 Key」维度。
// 数据源同为已解码的 APIKeyAmountData / APIKeyCostData，聚合口径与 MonthUsage.aggregated 对齐

/// 单个 API Key 的本月用量
struct APIKeyUsage: Equatable, Identifiable {
    let trackingId: String
    let name: String
    /// 该 Key 下所有 series 是否均有效（官方 valid 字段取 AND，任一 false 即失效）
    let valid: Bool
    let requests: Int
    let responseTokens: Double
    let cacheHitTokens: Double
    let cacheMissTokens: Double
    let cost: Double

    var id: String { trackingId }

    /// 展示名：优先 name，为空回退 trackingId 前 8 位
    var displayName: String {
        name.isEmpty ? String(trackingId.prefix(8)) : name
    }
}

/// 把 by_api_key 的天桶序列按 apiKey 归并成每个 Key 的本月用量。
/// - startTs/endTs：查询窗口（Unix 秒），窗口外的桶忽略（与 MonthUsage.aggregated 同口径）
/// - 费用只取 costData.data 的第一个币种分组（与 MonthUsage.aggregated 一致，不混加多币种）
/// - 同一 key 跨多个 model 的 series 的请求/token/费用求和
/// - valid 取该 key 下所有 series 的 AND（任一 false 即视为失效）
/// - 结果按费用降序、名称升序排序（稳定）
func apiKeyBreakdown(startTs: Int, endTs: Int,
                     amountData: APIKeyAmountData?,
                     costData: APIKeyCostData?) -> [APIKeyUsage] {
    func inWindow(_ ts: Int) -> Bool { ts >= startTs && ts < endTs }

    /// 累加器：trackingId -> 展示用元信息与数值合计
    struct Accumulator {
        var info: APIKeyInfo
        var requests: Double = 0
        var response: Double = 0
        var cacheHit: Double = 0
        var cacheMiss: Double = 0
        var cost: Double = 0
        /// 是否有任一 series 报 valid=false
        var sawInvalid: Bool = false
    }

    var byKey: [String: Accumulator] = [:]

    /// 取（或新建）某个 key 的累加器；同一 key 的后续 series 只更新 valid 标记
    func accumulator(for info: APIKeyInfo) -> Accumulator {
        if var existing = byKey[info.trackingId] {
            if !info.valid { existing.sawInvalid = true }
            return existing
        }
        var fresh = Accumulator(info: info)
        fresh.sawInvalid = !info.valid
        return fresh
    }

    for series in amountData?.series ?? [] {
        for bucket in series.buckets where inWindow(bucket.time) {
            var entry = accumulator(for: series.apiKey)
            entry.requests += bucket.usage["REQUEST"] ?? 0
            entry.response += bucket.usage["RESPONSE_TOKEN"] ?? 0
            entry.cacheHit += bucket.usage["PROMPT_CACHE_HIT_TOKEN"] ?? 0
            entry.cacheMiss += bucket.usage["PROMPT_CACHE_MISS_TOKEN"] ?? 0
            byKey[series.apiKey.trackingId] = entry
        }
    }
    if let group = costData?.data.first {
        for series in group.series {
            for bucket in series.buckets where inWindow(bucket.time) {
                var entry = accumulator(for: series.apiKey)
                entry.cost += Double(bucket.cost) ?? 0
                byKey[series.apiKey.trackingId] = entry
            }
        }
    }

    return byKey.values.map { entry in
        APIKeyUsage(
            trackingId: entry.info.trackingId,
            name: entry.info.name,
            valid: !entry.sawInvalid,
            requests: Int(entry.requests.rounded()),
            responseTokens: entry.response,
            cacheHitTokens: entry.cacheHit,
            cacheMissTokens: entry.cacheMiss,
            cost: entry.cost
        )
    }
    .sorted {
        if $0.cost != $1.cost { return $0.cost > $1.cost }
        return $0.name < $1.name
    }
}

// MARK: - 缓存命中率（命中 / (命中 + 未命中)）

/// 缓存命中率；分母为 0（该区间无缓存相关用量）返回 nil，UI 显示「—」而不是 0%
func cacheHitRate(hit: Double, miss: Double) -> Double? {
    let total = hit + miss
    guard total > 0 else { return nil }
    return hit / total
}
