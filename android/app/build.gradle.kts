// App 模块（A3）：Compose UI 薄壳，业务逻辑全部来自 :core。
// Compose/Material3 为 Google 官方 UI 工具链（红线 11 不视为第三方业务依赖）；
// WebView 登录用平台 android.webkit（零额外依赖）。
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.deepseek.meter.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.deepseek.meter.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 11
        versionName = "0.1.5"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // 固定正式签名（可选用）：CI 在 release.yml 里把 Secret 中的 keystore 解码到临时目录，
    // 通过 DSM_RELEASE_* 环境变量注入。跨版本签名一致后，应用内下载 APK 才能直接覆盖安装
    //（签名不一致会被系统拒绝，用户只能卸载重装）。密钥本体不入仓库（红线 3），
    // 本机配置方法见 docs/release-signing.md；未注入环境变量时回退 debug 签名，
    // 保持无密钥环境可构建（签名仅保证可安装，不构成信任背书）。
    signingConfigs {
        val storeFilePath = System.getenv("DSM_RELEASE_STORE_FILE")
        if (storeFilePath != null) {
            create("dsmRelease") {
                storeFile = file(storeFilePath)
                storePassword = System.getenv("DSM_RELEASE_STORE_PASSWORD")
                keyAlias = System.getenv("DSM_RELEASE_KEY_ALIAS")
                keyPassword = System.getenv("DSM_RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("dsmRelease")
                ?: signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        compose = true
        // QA 测试通知入口依赖 BuildConfig.DEBUG 门控（仅 debug 构建显示，release 自动剔除）
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))

    // Compose 官方工具链（BOM 统一版本）
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.foundation:foundation")
    // 核心 Material 图标（Home/Settings 等，BOM 统一版本；androidx 官方，红线 11 豁免同 Compose 工具链）
    implementation("androidx.compose.material:material-icons-core")

    // 后台刷新调度（D6 已决策，见 MOBILE-PLAN.md / Issue #11）：androidx 官方后台调度库，
    // 仅用于 :app 层低余额后台刷新；:core 保持零 AndroidX 依赖。
    // 版本选择依据：Issue #11 / D6 要求 ≥ 2.8.0（ExistingPeriodicWorkPolicy.UPDATE 语义）；
    // 2.10.1 为稳定版，其 minSdk 23 < 本项目 minSdk 26，兼容。
    implementation("androidx.work:work-runtime:2.10.1")
}
