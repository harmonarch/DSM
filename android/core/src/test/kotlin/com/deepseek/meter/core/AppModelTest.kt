package com.deepseek.meter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * AppModel 状态机测试（移植 iOS 自测第 12 节）：内存 TokenStore + stub 路由 4 个接口。
 */
class AppModelTest {

    private class MemoryTokenStore : TokenStore {
        private var stored: String? = null
        override fun loadToken(): String? = stored
        override fun saveToken(token: String) { stored = token }
        override fun clearToken() { stored = null }
    }

    private class RouterHttp(private val expiredAmount: Boolean = false) : PlatformHttp {
        override fun get(url: String, headers: Map<String, String>): PlatformHttpResponse {
            val body = when {
                url.contains("/auth-api/v0/users/current") -> CURRENT_USER
                url.contains("/api/v0/users/get_user_summary") -> SUMMARY
                url.contains("/usage/by_api_key/amount") -> if (expiredAmount) EXPIRED else BY_KEY_AMOUNT
                url.contains("/usage/by_api_key/cost") -> BY_KEY_COST
                else -> """{"code":404,"msg":"not found"}"""
            }
            return PlatformHttpResponse(200, body)
        }
    }

    private fun assertClose(expected: Double, actual: Double, delta: Double) {
        assertTrue("expect $expected, got $actual", abs(expected - actual) < delta)
    }

    @Test
    fun fullStateMachine() {
        val store = MemoryTokenStore()
        val model = AppModel(PlatformService(RouterHttp()), store)
        assertEquals(DataStatus.NOT_LOGGED_IN, model.state.status)
        assertNull(model.state.token)

        val ok = model.savePlatformToken("test-token-abc")
        assertTrue(ok)
        assertEquals("test-token-abc", model.state.token)
        assertEquals("test-token-abc", store.loadToken())
        assertEquals("dev@example.com", model.state.userName)
        assertEquals("CNY", model.state.currency) // 余额接口覆盖用户接口的币种
        assertEquals(DataStatus.FRESH, model.state.status)
        assertClose(40.24923164, model.state.lastBalance!!.total, 0.0001)
        assertClose(4.0, model.state.monthUsage!!.totalCost, 0.001)
        assertEquals(7, model.state.monthUsage!!.totalRequests)

        // 间隔选项与 iOS 对齐
        assertEquals(listOf(15L, 30L, 60L, 300L, 600L), AppModel.INTERVAL_OPTIONS)

        // Token 过期：amount 返回 biz_code 40002
        val expiredModel = AppModel(PlatformService(RouterHttp(expiredAmount = true)), store)
        expiredModel.refresh()
        assertTrue(expiredModel.state.tokenExpired)
        assertEquals(DataStatus.TOKEN_EXPIRED, expiredModel.state.status)

        // 退出登录
        model.clearPlatformToken()
        assertNull(model.state.token)
        assertNull(store.loadToken())
        assertEquals(DataStatus.NOT_LOGGED_IN, model.state.status)
    }

    companion object {
        const val CURRENT_USER = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"id":"u_1","email":"dev@example.com","currency":"USD"}}}"""
        const val EXPIRED = """{"code":0,"msg":"","data":{"biz_code":40002,"biz_msg":"token 失效","biz_data":null}}"""
        const val SUMMARY = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"normal_wallets":[{"currency":"CNY","balance":"40.2492316400000000","token_estimation":"0"}],"bonus_wallets":[{"currency":"CNY","balance":"0","token_estimation":"0"}],"total_costs":[{"currency":"CNY","amount":"19.7507683600000000"}]}}}}"""

        // AppModel 用例的桶时间按「当前月」动态生成：fetchUsage 按真实当月窗口聚合，
        // 固定时间戳的样例跨月后会落在窗口外被过滤，聚合断言随之失效（跨月时间炸弹）
        private val MONTH_START_TS: Long = run {
            val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Shanghai"))
            cal.set(java.util.Calendar.DAY_OF_MONTH, 1)
            cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
            cal.set(java.util.Calendar.MINUTE, 0)
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
            cal.timeInMillis / 1000
        }
        private val SECOND_DAY_TS: Long = MONTH_START_TS + 86400

        val BY_KEY_AMOUNT = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":$MONTH_START_TS,"end":${MONTH_START_TS + 86400 * 31},"bucket":86400,"models":["deepseek-v4-pro"],"series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":$MONTH_START_TS,"usage":{"REQUEST":2,"RESPONSE_TOKEN":100}},{"time":$SECOND_DAY_TS,"usage":{"REQUEST":5,"RESPONSE_TOKEN":200}}]}]}}}"""
        val BY_KEY_COST = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":$MONTH_START_TS,"end":${MONTH_START_TS + 86400 * 31},"bucket":86400,"models":["deepseek-v4-pro"],"data":[{"currency":"CNY","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":$MONTH_START_TS,"cost":"1.5"},{"time":$SECOND_DAY_TS,"cost":"2.5"}]}]}]}}}"""
    }
}
