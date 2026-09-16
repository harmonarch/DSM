import Foundation

/// 平台前置风控（AWS WAF）适配：macOS 27 起，原生 URLSession 发出的请求会被判定为
/// "未经浏览器验证的客户端"，拿到 HTTP 202 + `x-amzn-waf-action: challenge` 的空响应；
/// 而登录窗里的 WKWebView 是浏览器上下文，会自动解答挑战并把 `aws-waf-token` 写进 cookie。
/// 因此登录校验这一类必须走原生请求的调用，把该票据附到请求的 Cookie 头即可放行。
/// 实测（macOS 27.0）：同一请求 curl 通过、原生被挑战、附上浏览器解出的票据后恢复 200。
enum WAFGuard {
    /// WAF 干预标识响应头：值为 challenge / captcha / block 等
    static let actionHeader = "x-amzn-waf-action"
    /// 挑战票据 cookie 名
    static let tokenCookieName = "aws-waf-token"

    /// 是否为 WAF 风控响应：202（challenge 约定状态码）或带风控标识头
    static func isChallenge(status: Int, headers: [AnyHashable: Any]?) -> Bool {
        if status == 202 { return true }
        guard let action = headers?[actionHeader] as? String else { return false }
        return !action.isEmpty
    }

    /// 从浏览器上下文的 cookie 里挑出 DeepSeek 域的 WAF 票据，拼成 Cookie 头值；找不到返回 nil
    static func cookieHeader(from cookies: [HTTPCookie]) -> String? {
        let picked = cookies.filter { $0.name == tokenCookieName && isDeepSeekHost($0.domain) }
        guard !picked.isEmpty else { return nil }
        return picked.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// 仅允许 DeepSeek 官方域名（*.deepseek.com，含带前导点的 cookie 域写法）
    static func isDeepSeekHost(_ host: String) -> Bool {
        let normalized = host.hasPrefix(".") ? String(host.dropFirst()) : host
        return normalized == "deepseek.com" || normalized.hasSuffix(".deepseek.com")
    }
}
