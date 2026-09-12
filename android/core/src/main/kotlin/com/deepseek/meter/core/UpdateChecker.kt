package com.deepseek.meter.core

import org.json.JSONArray
import org.json.JSONObject

/** GitHub Release 最新版本信息（应用内更新用） */
data class UpdateRelease(
    val version: String, // 去掉 v 前缀的语义版本
    val apkName: String, // APK 资源原始文件名（SHA256SUMS 校验按此名匹配行）
    val apkUrl: String,  // APK 下载地址
    val sumsUrl: String? // SHA256SUMS.txt 地址（可能缺失）
)

/**
 * releases/latest JSON 解析（org.json 手写映射，对齐 :core 既有风格）。
 * 网络请求本身由 :app 层 HttpURLConnection 完成，:core 保持纯逻辑可 JVM 单测。
 */
object UpdateChecker {
    /** 更新源仓库（GitHub Releases 提供 macOS ZIP / Windows ZIP / APK 与 SHA256SUMS.txt） */
    const val REPO_SLUG = "harmonarch/DSM"

    /**
     * 解析 GET /releases/latest 的响应体。
     * APK 资源按 `DSM-*-android.apk` 匹配；没有 Android 更新包时抛 IllegalArgumentException。
     */
    fun parseLatestRelease(json: String): UpdateRelease {
        val root = JSONObject(json)
        val tag = root.optString("tag_name").trim()
        var apkName: String? = null
        var apkUrl: String? = null
        var sumsUrl: String? = null
        val assets: JSONArray = root.optJSONArray("assets") ?: JSONArray()
        for (i in 0 until assets.length()) {
            val asset = assets.optJSONObject(i) ?: continue
            val name = asset.optString("name")
            val url = asset.optString("browser_download_url")
            if (url.isEmpty()) continue
            if (apkUrl == null && name.startsWith("DSM-") && name.endsWith("-android.apk")) {
                apkName = name
                apkUrl = url
            }
            if (sumsUrl == null && name == "SHA256SUMS.txt") {
                sumsUrl = url
            }
        }
        apkName ?: throw IllegalArgumentException("Release 中没有 Android 更新包")
        var version = tag
        if (version.startsWith("v") || version.startsWith("V")) version = version.substring(1)
        return UpdateRelease(version, apkName, apkUrl!!, sumsUrl)
    }

    /**
     * 从 GitHub 网页端 /releases/latest 的 302 Location 解析最新 tag（API 限流兜底用）。
     * Location 可能是绝对路径（/owner/repo/releases/tag/v0.1.0）或完整 URL，兼容两种形态；
     * 解析不到 tag 段返回 null。对齐 macOS latestTag(fromReleaseRedirectPath:)。
     */
    fun parseRedirectTag(location: String): String? {
        val marker = "/releases/tag/"
        val start = location.indexOf(marker)
        if (start < 0) return null
        var tag = location.substring(start + marker.length)
        val cut = tag.indexOfFirst { it == '?' || it == '#' }
        if (cut >= 0) tag = tag.substring(0, cut)
        return tag.ifEmpty { null }
    }

    /**
     * 按网页端 302 解析出的 tag 推导 Release（API 限流兜底用）。
     * 命名与 release.yml 固定流水线一致：tag 目录带 v，APK 资源名也带 v（DSM-v0.1.0-android.apk）。
     */
    fun releaseFromTag(tag: String): UpdateRelease {
        var version = tag
        if (version.startsWith("v") || version.startsWith("V")) version = version.substring(1)
        val apkName = "DSM-$tag-android.apk"
        val base = "https://github.com/$REPO_SLUG/releases/download/$tag"
        return UpdateRelease(
            version = version,
            apkName = apkName,
            apkUrl = "$base/$apkName",
            sumsUrl = "$base/SHA256SUMS.txt",
        )
    }
}
