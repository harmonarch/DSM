// 应用内更新：GitHub Release 检查 → 自动下载 → SHA256 校验 → PackageInstaller 覆盖安装。
// 对齐 macOS UpdateService.swift / Windows UpdateService.cs；网络仅 GET api.github.com
// （限流 403/429 时兜底走 github.com 网页端 302）与 Release 资源，不上报任何本地数据。
// 安装走平台 PackageInstaller 会话（零第三方依赖），
// 同签名 APK（固定正式签名，见 docs/release-signing.md）覆盖安装后数据保留。
package com.deepseek.meter.app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.deepseek.meter.core.UpdateChecker
import com.deepseek.meter.core.UpdateRelease
import com.deepseek.meter.core.isVersion
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** 更新流程状态（UI 渲染依据） */
sealed class UpdateState {
    data object Idle : UpdateState()
    data object Checking : UpdateState()
    data object UpToDate : UpdateState()
    data class Downloading(val progress: Float) : UpdateState()
    data class ReadyToInstall(val apkFile: File, val version: String) : UpdateState()
    data object Installing : UpdateState()
    data class Failed(val message: String) : UpdateState()
}

/** 应用内更新管理器：检查/下载在独立线程执行，状态经 Compose State 桥接 UI */
class UpdateManager(private val context: Context) {

    /** 状态机（Compose 可观察） */
    var state by mutableStateOf<UpdateState>(UpdateState.Idle)
        private set

    private var stagedApk: File? = null

    private val prefs = context.getSharedPreferences("deepseek_meter_settings", Context.MODE_PRIVATE)

    /** 启动时自动检查更新（仅 GET 读取，不上传任何数据）；默认开启 */
    var autoCheck: Boolean
        get() = prefs.getBoolean(KEY_AUTO_CHECK, true)
        set(value) { prefs.edit().putBoolean(KEY_AUTO_CHECK, value).apply() }

    /** 已下载待安装的 APK 是否还在（失败后允许直接重装而不用重新下载） */
    val hasStagedApk: Boolean get() = stagedApk != null

    val isBusy: Boolean
        get() = state is UpdateState.Checking || state is UpdateState.Downloading || state is UpdateState.Installing

    /** 当前是否允许直接发起安装（26+ 需「安装未知应用」授权） */
    fun canInstall(): Boolean = context.packageManager.canRequestPackageInstalls()

    /** 引导到「允许安装未知应用」系统设置 */
    fun openInstallPermissionSettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    // MARK: - 检查 + 下载

    /** 检查更新；发现新版本自动下载并校验，完成后进入 ReadyToInstall（安装仍需用户确认） */
    fun checkForUpdate() {
        if (isBusy) return
        state = UpdateState.Checking
        Thread {
            try {
                val release = fetchLatestRelease()
                if (!isVersion(release.version, newerThan = BuildConfig.VERSION_NAME)) {
                    state = UpdateState.UpToDate
                    return@Thread
                }
                state = UpdateState.Downloading(0f)
                val apk = downloadApk(release)
                verifyChecksum(apk, release.sumsUrl)
                cleanupStagedApk()
                stagedApk = apk
                state = UpdateState.ReadyToInstall(apk, release.version)
            } catch (e: Exception) {
                state = UpdateState.Failed("更新失败：${e.message ?: e.javaClass.simpleName}")
            }
        }.start()
    }

    /** 非 2xx 响应（携带状态码，供限流兜底判定） */
    private class HttpCodeException(val code: Int) : RuntimeException("HTTP $code")

    /** 拉取最新 Release：优先走 API；被限流（403/429，未认证限额 60 次/小时/IP，共享代理出口易耗尽）时走网页端 302 兜底 */
    private fun fetchLatestRelease(): UpdateRelease {
        try {
            return fetchViaApi()
        } catch (e: HttpCodeException) {
            if (e.code != 403 && e.code != 429) throw e
            return fetchViaRedirect()
        }
    }

    /** 走 api.github.com 拉取（带资产列表，首选） */
    private fun fetchViaApi(): UpdateRelease {
        val connection = (URL("https://api.github.com/repos/${UpdateChecker.REPO_SLUG}/releases/latest")
            .openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "DeepSeekMeter")
        }
        try {
            val code = connection.responseCode
            if (code != 200) throw HttpCodeException(code)
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            return UpdateChecker.parseLatestRelease(body)
        } finally {
            connection.disconnect()
        }
    }

    /** 网页端兜底：github.com/<repo>/releases/latest 恒 302 到 /releases/tag/<tag>，不占 API 限额 */
    private fun fetchViaRedirect(): UpdateRelease {
        val connection = (URL("https://github.com/${UpdateChecker.REPO_SLUG}/releases/latest")
            .openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 15_000
            instanceFollowRedirects = false
            setRequestProperty("User-Agent", "DeepSeekMeter")
        }
        try {
            val code = connection.responseCode
            if (code !in 300..399) throw RuntimeException("更新源未返回最新版本（HTTP $code）")
            val tag = UpdateChecker.parseRedirectTag(connection.getHeaderField("Location") ?: "")
                ?: throw RuntimeException("更新源未返回最新版本（HTTP $code）")
            return UpdateChecker.releaseFromTag(tag)
        } finally {
            connection.disconnect()
        }
    }

    /** 流式下载 APK 到应用缓存目录（文件名沿用 Release 原始资源名，SHA256SUMS 按名匹配） */
    private fun downloadApk(release: UpdateRelease): File {
        val connection = URL(release.apkUrl).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        try {
            val total = connection.contentLengthLong
            val dir = File(context.cacheDir, "update").apply { mkdirs() }
            val target = File(dir, release.apkName)
            connection.inputStream.use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var written = 0L
                    var lastReported = 0f
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        written += read
                        if (total > 0) {
                            val progress = (written.toDouble() / total).toFloat().coerceIn(0f, 1f)
                            if (progress - lastReported >= 0.01f) {
                                lastReported = progress
                                state = UpdateState.Downloading(progress)
                            }
                        }
                    }
                }
            }
            return target
        } finally {
            connection.disconnect()
        }
    }

    /** Release 附带 SHA256SUMS.txt 时校验哈希；没有则跳过（不强依赖） */
    private fun verifyChecksum(file: File, sumsUrl: String?) {
        if (sumsUrl == null) return
        val text = URL(sumsUrl).openStream().bufferedReader().use { it.readText() }
        val expected = text.lineSequence()
            .map { it.trim().split(Regex("\\s+")) }
            .firstOrNull { it.size >= 2 && it[1] == file.name }
            ?.firstOrNull()
            ?: return
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (!actual.equals(expected, ignoreCase = true)) {
            throw RuntimeException("SHA256 校验不符，安装包可能已损坏")
        }
    }

    // MARK: - 覆盖安装

    /** 触发覆盖安装：PackageInstaller 会弹出系统安装确认（同签名下 Token 与设置保留） */
    fun installReadyApk() {
        val apk = stagedApk ?: return
        if (isBusy) return
        state = UpdateState.Installing
        try {
            val packageInstaller = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            val sessionId = packageInstaller.createSession(params)
            packageInstaller.openSession(sessionId).use { session ->
                session.openWrite("dsm-update.apk", 0, apk.length()).use { output ->
                    apk.inputStream().use { it.copyTo(output) }
                    session.fsync(output)
                }
                session.commit(createInstallStatusIntentSender(sessionId))
            }
        } catch (e: Exception) {
            state = UpdateState.Failed("发起安装失败：${e.message ?: e.javaClass.simpleName}")
        }
    }

    /** 安装结果回调（系统异步回报：可能先要求用户确认） */
    private val installStatusReceiver = object : BroadcastReceiver() {
        override fun onReceive(receiverContext: Context, intent: Intent) {
            when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    val confirm = userActionIntent(intent) ?: return
                    receiverContext.startActivity(confirm)
                }
                PackageInstaller.STATUS_SUCCESS -> {
                    // 新版本已就位（进程即将被系统接管重启）
                    cleanupStagedApk()
                    state = UpdateState.UpToDate
                }
                else -> {
                    val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    state = UpdateState.Failed("安装失败${message?.let { "：$it" } ?: ""}")
                }
            }
        }
    }

    init {
        val filter = IntentFilter(ACTION_INSTALL_STATUS)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(installStatusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(installStatusReceiver, filter)
        }
    }

    /** 释放运行时注册的接收器（AppController.close 调用） */
    fun release() {
        runCatching { context.unregisterReceiver(installStatusReceiver) }
    }

    private fun createInstallStatusIntentSender(sessionId: Int): android.content.IntentSender {
        val intent = Intent(ACTION_INSTALL_STATUS).setPackage(context.packageName)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            sessionId,
            intent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return pendingIntent.intentSender
    }

    private fun userActionIntent(intent: Intent): Intent? {
        val confirm = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
        return confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun cleanupStagedApk() {
        stagedApk?.parentFile?.let { dir -> runCatching { dir.deleteRecursively() } }
        stagedApk = null
    }

    companion object {
        private const val KEY_AUTO_CHECK = "autoCheckUpdates"
        private const val ACTION_INSTALL_STATUS = "com.deepseek.meter.app.INSTALL_STATUS"
    }
}
