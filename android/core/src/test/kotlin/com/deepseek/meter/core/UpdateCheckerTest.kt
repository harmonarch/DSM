package com.deepseek.meter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** 版本比较与 releases/latest 解析（对齐 macOS/iOS/Windows isVersion 用例） */
class UpdateCheckerTest {

    // MARK: - isVersion

    @Test
    fun `patch 位更新判定为更新`() = assertTrue(isVersion("0.0.6", newerThan = "0.0.5"))

    @Test
    fun `v 前缀剥离加 minor 位更新`() = assertTrue(isVersion("v0.1.0", newerThan = "0.0.9"))

    @Test
    fun `大写 V 前缀剥离`() = assertTrue(isVersion("V1.2.0", newerThan = "1.1.99"))

    @Test
    fun `相同版本不算更新`() {
        assertTrue(!isVersion("0.0.5", newerThan = "0.0.5"))
    }

    @Test
    fun `旧版本不算更新`() {
        assertTrue(!isVersion("0.0.4", newerThan = "0.0.5"))
    }

    @Test
    fun `段数不齐按 0 补齐后相等`() {
        assertTrue(!isVersion("1.0", newerThan = "1.0.0"))
    }

    @Test
    fun `缺段按 0 补齐可比较`() = assertTrue(isVersion("1.0.1", newerThan = "1.0"))

    @Test
    fun `按数值而非字符串比较`() = assertTrue(isVersion("10.0", newerThan = "9.9"))

    @Test
    fun `非法版本按 0 处理不算更新`() {
        assertTrue(!isVersion("abc", newerThan = "0.0.1"))
    }

    // MARK: - parseLatestRelease

    @Test
    fun `解析最新版本与资源地址`() {
        val json = """
            {"tag_name":"v0.0.6","assets":[
              {"name":"DSM-0.0.6-macOS.dmg","browser_download_url":"https://example.com/1"},
              {"name":"DSM-v0.0.6-android.apk","browser_download_url":"https://example.com/2"},
              {"name":"SHA256SUMS.txt","browser_download_url":"https://example.com/3"}]}
        """.trimIndent()
        val release = UpdateChecker.parseLatestRelease(json)
        assertEquals("0.0.6", release.version)
        assertEquals("DSM-v0.0.6-android.apk", release.apkName)
        assertEquals("https://example.com/2", release.apkUrl)
        assertEquals("https://example.com/3", release.sumsUrl)
    }

    @Test
    fun `没有安卓包时抛出`() {
        val json = """
            {"tag_name":"v0.0.6","assets":[
              {"name":"DSM-0.0.6-macOS.dmg","browser_download_url":"https://example.com/1"}]}
        """.trimIndent()
        try {
            UpdateChecker.parseLatestRelease(json)
            fail("应抛 IllegalArgumentException")
        } catch (expected: IllegalArgumentException) {
            assertEquals("Release 中没有 Android 更新包", expected.message)
        }
    }

    @Test
    fun `缺 SHA256SUMS 时 sumsUrl 为 null`() {
        val json = """
            {"tag_name":"0.0.7","assets":[
              {"name":"DSM-0.0.7-android.apk","browser_download_url":"https://example.com/2"}]}
        """.trimIndent()
        val release = UpdateChecker.parseLatestRelease(json)
        assertEquals(null, release.sumsUrl)
    }

    // MARK: - 网页端 302 兜底（API 限流 403/429 时走 github.com 网页端）

    @Test
    fun `302 绝对路径解析 tag`() =
        assertEquals("v0.1.0", UpdateChecker.parseRedirectTag("/harmonarch/DSM/releases/tag/v0.1.0"))

    @Test
    fun `302 完整 URL 解析 tag`() = assertEquals(
        "v1.2.3",
        UpdateChecker.parseRedirectTag("https://github.com/harmonarch/DSM/releases/tag/v1.2.3"),
    )

    @Test
    fun `302 剥离 query 参数`() =
        assertEquals("v0.1.0", UpdateChecker.parseRedirectTag("/harmonarch/DSM/releases/tag/v0.1.0?x=1"))

    @Test
    fun `无 tag 段返回 null`() = assertNull(UpdateChecker.parseRedirectTag("/harmonarch/DSM/releases/latest"))

    @Test
    fun `空串返回 null`() = assertNull(UpdateChecker.parseRedirectTag(""))

    @Test
    fun `按 tag 推导安卓资产命名`() {
        val release = UpdateChecker.releaseFromTag("v0.1.0")
        assertEquals("0.1.0", release.version)
        assertEquals("DSM-v0.1.0-android.apk", release.apkName)
        assertEquals(
            "https://github.com/harmonarch/DSM/releases/download/v0.1.0/DSM-v0.1.0-android.apk",
            release.apkUrl,
        )
        assertEquals(
            "https://github.com/harmonarch/DSM/releases/download/v0.1.0/SHA256SUMS.txt",
            release.sumsUrl,
        )
    }
}
