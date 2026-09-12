// 根界面：主页 + 设置 两个 Tab（对齐 iOS 两 Tab 结构）+ 登录全屏页。
// Material 3 骨架：Scaffold + NavigationBar（官方底部导航，选中态自带胶囊指示器）
// + 主页下拉刷新（PullToRefreshBox）+ 切页方向性滑动过渡。
package com.deepseek.meter.app

import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import com.deepseek.meter.core.AppModel

/// 根界面：极简 M3 结构，内容区随 Tab 方向性滑动切换
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeepSeekMeterApp(controller: AppController) {
    val state = controller.state
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }
    var showLogin by remember { mutableStateOf(false) }

    if (showLogin) {
        LoginScreen(
            onDismiss = { showLogin = false },
            onSaveToken = { token, done ->
                controller.saveToken(token) { ok ->
                    done(ok)
                    if (ok) showLogin = false
                }
            }
        )
        return
    }

    val view = LocalView.current

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = {
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        selectedTab = 0
                    },
                    icon = {
                        Icon(
                            if (selectedTab == 0) Icons.Filled.Home else Icons.Outlined.Home,
                            contentDescription = "主页"
                        )
                    },
                    label = { Text("主页") }
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = {
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        selectedTab = 1
                    },
                    icon = {
                        Icon(
                            if (selectedTab == 1) Icons.Filled.Settings else Icons.Outlined.Settings,
                            contentDescription = "设置"
                        )
                    },
                    label = { Text("设置") }
                )
            }
        }
    ) { innerPadding ->
        AnimatedContent(
            targetState = selectedTab,
            transitionSpec = {
                // 方向性滑动：去右边的页从右侧进，回左边的页从左侧进（淡入淡出压缩到短时长）
                val direction = if (targetState > initialState) 1 else -1
                (slideInHorizontally(tween(220, easing = FastOutSlowInEasing)) { it / 5 * direction } + fadeIn(tween(180))) togetherWith
                    (slideOutHorizontally(tween(160)) { -it / 8 * direction } + fadeOut(tween(140)))
            },
            label = "tabSwitch",
            modifier = Modifier.fillMaxSize()
        ) { tab ->
            if (tab == 0) {
                HomePane(
                    state = state,
                    controller = controller,
                    onLogin = { showLogin = true },
                    contentPadding = innerPadding
                )
            } else {
                SettingsPane(
                    state = state,
                    controller = controller,
                    onLogin = { showLogin = true },
                    contentPadding = innerPadding
                )
            }
        }
    }
}

/** 主页：下拉刷新 + 滚动内容（顶部让出状态栏，左右统一 20dp 边距） */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomePane(
    state: AppModel.State,
    controller: AppController,
    onLogin: () -> Unit,
    contentPadding: PaddingValues
) {
    val pullState = rememberPullToRefreshState()
    PullToRefreshBox(
        isRefreshing = state.fetching,
        onRefresh = { controller.refresh() },
        state = pullState,
        // 指示器只在真正刷新时渲染：空闲时不渲染任何东西，
        // 规避 Activity 重建等场景下空闲指示器残影卡住的问题（模拟器实测复现过）
        indicator = {
            if (state.fetching) {
                PullToRefreshDefaults.Indicator(
                    modifier = Modifier.align(Alignment.TopCenter),
                    isRefreshing = state.fetching,
                    state = pullState
                )
            }
        },
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                .padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 8.dp)
        ) {
            HomeScreen(state = state, controller = controller, onLogin = onLogin)
        }
    }
}

/** 设置：普通滚动内容 */
@Composable
private fun SettingsPane(
    state: AppModel.State,
    controller: AppController,
    onLogin: () -> Unit,
    contentPadding: PaddingValues
) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .verticalScroll(rememberScrollState())
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 24.dp)
    ) {
        SettingsScreen(state = state, controller = controller, onLogin = onLogin)
    }
}
