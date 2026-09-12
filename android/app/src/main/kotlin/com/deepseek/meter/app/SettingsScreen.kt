// 设置：账号（登录/退出）、自动刷新、低余额通知、隐私说明（Material 3）。
// 通知开关与后台 Worker 生命周期闭环（Issue #15）：
//  OFF→ON：权限通过后保存 enabled=true 并注册唯一周期任务（UPDATE）；
//  ON→OFF：保存 enabled=false、取消唯一任务、重置 alerted 状态；
//  Worker 每次执行前还会二次检查开关（双重保障）。
// 滚动与边距由根布局（DeepSeekMeterApp）提供，这里只负责内容本身。
package com.deepseek.meter.app

import android.Manifest
import android.content.Context
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.deepseek.meter.app.background.BackgroundRefreshScheduler
import com.deepseek.meter.app.background.BackgroundRefreshWorker
import com.deepseek.meter.app.notification.LowBalanceNotifier
import com.deepseek.meter.core.AppModel
import com.deepseek.meter.core.DataStatus
import com.deepseek.meter.core.LowBalancePolicy
import com.deepseek.meter.core.currencySymbol
import com.deepseek.meter.core.format

@Composable
internal fun SettingsScreen(state: AppModel.State, controller: AppController, onLogin: () -> Unit) {
    val context = LocalContext.current

    // ---- 低余额通知状态（Issue #15） ----
    val notifier = remember { LowBalanceNotifier(context) }
    val bgPrefs = remember {
        context.getSharedPreferences(BackgroundRefreshWorker.PREFS_NAME, Context.MODE_PRIVATE)
    }
    var alertsEnabled by remember { mutableStateOf(bgPrefs.getBoolean(BackgroundRefreshWorker.KEY_ALERTS_ENABLED, false)) }
    var showPermissionNote by remember { mutableStateOf(false) }
    // 拒绝计数（权限三态）：0=未请求；1=曾拒绝，可再次点击重试；≥2=引导系统设置，不再弹框
    var permissionDenialCount by remember { mutableStateOf(bgPrefs.getInt(BackgroundRefreshWorker.KEY_DENIAL_COUNT, 0)) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted && notifier.areNotificationsEnabled()) {
            bgPrefs.edit().putBoolean(BackgroundRefreshWorker.KEY_ALERTS_ENABLED, true).apply()
            alertsEnabled = true
            showPermissionNote = false
            permissionDenialCount = 0
            bgPrefs.edit().putInt(BackgroundRefreshWorker.KEY_DENIAL_COUNT, 0).apply()
            BackgroundRefreshScheduler.schedule(context)
        } else {
            // 拒绝（或渠道在系统设置中被关闭）：保持关闭，记录拒绝次数（持久化，重启后不重置），展示系统设置入口
            permissionDenialCount += 1
            bgPrefs.edit().putInt(BackgroundRefreshWorker.KEY_DENIAL_COUNT, permissionDenialCount).apply()
            showPermissionNote = true
        }
    }

    fun enableAlerts() {
        notifier.createChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notifier.areNotificationsEnabled()) {
            // Android 13+ 未授予：首次点击请求；拒绝一次允许再次点击重试；
            // 拒绝两次以上直接引导系统设置，不再骚扰式弹框（系统对多次拒绝通常也不再展示对话框）
            if (permissionDenialCount >= 2) {
                showPermissionNote = true
            } else {
                permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        } else {
            // 已授权（或 <13 无运行时权限）：启用并注册唯一周期任务
            bgPrefs.edit().putBoolean(BackgroundRefreshWorker.KEY_ALERTS_ENABLED, true).apply()
            alertsEnabled = true
            showPermissionNote = false
            BackgroundRefreshScheduler.schedule(context)
        }
    }

    fun disableAlerts() {
        bgPrefs.edit()
            .putBoolean(BackgroundRefreshWorker.KEY_ALERTS_ENABLED, false)
            .remove(BackgroundRefreshWorker.KEY_ALERTED) // 重置提醒状态
            .apply()
        alertsEnabled = false
        showPermissionNote = false
        BackgroundRefreshScheduler.cancel(context)
    }

    Column(Modifier.fillMaxWidth()) {
        Text("设置", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(3.dp))
        Text(
            "DeepSeekMeter · v" + BuildConfig.VERSION_NAME,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(18.dp))

        AccountCard(state, onLogin, onLogout = { controller.clearToken() })
        Spacer(Modifier.height(14.dp))
        RefreshIntervalCard(controller)
        Spacer(Modifier.height(14.dp))
        NotificationCard(
            alertsEnabled = alertsEnabled,
            showPermissionNote = showPermissionNote,
            permissionDenialCount = permissionDenialCount,
            onToggle = { on -> if (on) enableAlerts() else disableAlerts() },
            onOpenSettings = { notifier.openNotificationSettings() },
            onSendTest = { notifier.notifyLowBalance(0.5, "CNY") }
        )
        Spacer(Modifier.height(14.dp))
        UpdateCard(updateManager = controller.updateManager)
        Spacer(Modifier.height(14.dp))
        PrivacyCard()
    }
}

// MARK: - 账号卡（鲸鱼娘头像 + 登录态）

@Composable
private fun AccountCard(state: AppModel.State, onLogin: () -> Unit, onLogout: () -> Unit) {
    MeterCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(54.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer)
            ) {
                Image(
                    painter = painterResource(R.drawable.whale_girl),
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(4.dp)
                )
            }
            Spacer(Modifier.width(13.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    state.userName?.takeIf { it.isNotEmpty() } ?: "未登录",
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    when (state.status) {
                        DataStatus.NOT_LOGGED_IN -> "登录后开始记录用量"
                        DataStatus.TOKEN_EXPIRED -> "登录已过期，请重新登录"
                        else -> "已连接 DeepSeek 平台"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        if (state.status == DataStatus.NOT_LOGGED_IN) {
            Button(
                onClick = onLogin,
                modifier = Modifier.fillMaxWidth().height(44.dp)
            ) {
                Text("登录 DeepSeek 平台", style = MaterialTheme.typography.labelLarge)
            }
        } else {
            Row {
                FilledTonalButton(onClick = onLogin, modifier = Modifier.weight(1f).height(44.dp)) {
                    Text("重新登录")
                }
                Spacer(Modifier.width(10.dp))
                OutlinedButton(onClick = onLogout, modifier = Modifier.weight(1f).height(44.dp)) {
                    Text("退出登录", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

// MARK: - 自动刷新卡（筛选芯片选择前台轮询间隔）

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RefreshIntervalCard(controller: AppController) {
    MeterCard {
        Text("自动刷新", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(3.dp))
        Text(
            "前台轮询间隔，进入后台自动暂停",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(12.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            IntervalOption("15 秒", 15L, controller)
            IntervalOption("30 秒", 30L, controller)
            IntervalOption("1 分钟", 60L, controller)
            IntervalOption("5 分钟", 300L, controller)
            IntervalOption("10 分钟", 600L, controller)
        }
    }
}

@Composable
private fun IntervalOption(label: String, seconds: Long, controller: AppController) {
    FilterChip(
        selected = controller.refreshIntervalSeconds == seconds,
        onClick = { controller.refreshIntervalSeconds = seconds },
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer
        )
    )
}

// MARK: - 通知卡（低余额提醒开关 + 权限三态 + QA 入口）

@Composable
private fun NotificationCard(
    alertsEnabled: Boolean,
    showPermissionNote: Boolean,
    permissionDenialCount: Int,
    onToggle: (Boolean) -> Unit,
    onOpenSettings: () -> Unit,
    onSendTest: () -> Unit
) {
    MeterCard {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f)) {
                Text("低余额提醒", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(3.dp))
                Text(
                    "余额低于 " + currencySymbol("CNY") + format(LowBalancePolicy.DEFAULT_THRESHOLD) +
                        " 时本地通知，纯本地无推送",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(Modifier.width(12.dp))
            Switch(checked = alertsEnabled, onCheckedChange = onToggle)
        }
        if (showPermissionNote) {
            Spacer(Modifier.height(10.dp))
            Text(
                if (permissionDenialCount >= 2)
                    "通知权限已关闭：请在系统设置中允许 DeepSeekMeter 通知后重试"
                else
                    "通知权限被拒绝：可再次点击开关重试，或打开系统设置开启",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
            TextButton(onClick = onOpenSettings, contentPadding = PaddingValues(start = 0.dp)) {
                Text("打开系统通知设置")
            }
        }
        // QA 入口（仅 debug 构建）：低余额通知管线真机验证用——
        // 渠道/权限/图标/文案/点击跳转与真实余额无关，无需真实低余额账户（#16 QA 矩阵）
        if (BuildConfig.DEBUG) {
            Spacer(Modifier.height(8.dp))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f))
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(
                    "发送一条测试低余额通知（仅调试构建）",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f)
                )
                TextButton(onClick = onSendTest) { Text("发送") }
            }
        }
    }
}

// MARK: - 应用内更新卡（GitHub Release 检查 / 自动下载 / 覆盖安装；按钮形式，与 macOS 版一致）

@Composable
private fun UpdateCard(updateManager: UpdateManager) {
    val state = updateManager.state
    MeterCard {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f)) {
                Text("应用内更新", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(3.dp))
                Text(
                    updateStateText(state),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (state is UpdateState.Failed) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(Modifier.width(12.dp))
            updateControl(updateManager, state)
        }
        when (val s = state) {
            is UpdateState.Downloading -> {
                Spacer(Modifier.height(10.dp))
                LinearProgressIndicator(progress = { s.progress }, modifier = Modifier.fillMaxWidth())
            }
            is UpdateState.ReadyToInstall -> {
                Spacer(Modifier.height(12.dp))
                Button(
                    onClick = {
                        if (updateManager.canInstall()) updateManager.installReadyApk()
                        else updateManager.openInstallPermissionSettings()
                    },
                    modifier = Modifier.fillMaxWidth().height(44.dp)
                ) {
                    Text("安装 v" + s.version + " 并重启", style = MaterialTheme.typography.labelLarge)
                }
            }
            is UpdateState.Failed -> {
                if (updateManager.hasStagedApk) {
                    Spacer(Modifier.height(6.dp))
                    TextButton(onClick = { updateManager.installReadyApk() }, contentPadding = PaddingValues(start = 0.dp)) {
                        Text("重新安装")
                    }
                }
            }
            else -> {}
        }
    }
}

/** 右侧状态控件：检查/重试按钮常驻可点，检查与安装进行中用小指示器占位 */
@Composable
private fun updateControl(updateManager: UpdateManager, state: UpdateState) {
    when (state) {
        UpdateState.Idle, UpdateState.UpToDate ->
            FilledTonalButton(onClick = { updateManager.checkForUpdate() }) { Text("检查更新") }
        UpdateState.Checking, UpdateState.Installing ->
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
        is UpdateState.Failed ->
            FilledTonalButton(onClick = { updateManager.checkForUpdate() }) { Text("重试") }
        is UpdateState.Downloading, is UpdateState.ReadyToInstall -> {}
    }
}

private fun updateStateText(state: UpdateState): String = when (state) {
    is UpdateState.Idle -> "启动时自动检查 GitHub 新版本（仅读取，不上传任何数据）"
    is UpdateState.Checking -> "检查中…"
    is UpdateState.UpToDate -> "已是最新版本 ✓"
    is UpdateState.Downloading -> "正在下载新版本…"
    is UpdateState.ReadyToInstall -> "新版本已就绪，确认后覆盖安装（余额与设置保留）"
    is UpdateState.Installing -> "正在安装…"
    is UpdateState.Failed -> state.message
}

// MARK: - 隐私卡

@Composable
private fun PrivacyCard() {
    MeterCard {
        Text("隐私", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(7.dp))
        Text(
            "所有数据来自 DeepSeek 官方平台接口，使用你自己的登录态，不会发送到任何第三方。" +
                "Token 使用 Android Keystore 加密后保存在本机，「退出登录」可随时清除。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
