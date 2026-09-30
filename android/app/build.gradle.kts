// App 模块（A3）：Compose UI 薄壳，业务逻辑全部来自 :core。
// Compose/Material3 为 Google 官方 UI 工具链（红线 11 不视为第三方业务依赖）；
// WebView 登录用平台 android.webkit（零额外依赖）。
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// release 固定签名的来源：环境变量注入（CI 在 release.yml 里把 Secret 里的 keystore 解码到临时目录；
// 本机配置方法见 docs/release-signing.md）。密钥本体不入仓库（红线 3）。
val dsmStoreFilePath = System.getenv("DSM_RELEASE_STORE_FILE")

// 是否显式放行 debug 签名：默认 false，即缺固定签名时 release 构建失败（见文件末尾的校验）。
// 用 providers.gradleProperty 读取（而非 project.findProperty），对配置缓存友好；
// 仅限本机无密钥时验证 release 变体能否打包：./gradlew :app:assembleRelease -PdsmAllowDebugSigning=true
val dsmAllowDebugSigning = providers.gradleProperty("dsmAllowDebugSigning")
    .map { it.toBoolean() }
    .getOrElse(false)

android {
    namespace = "com.deepseek.meter.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.deepseek.meter.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 14
        versionName = "0.2.2"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // 固定正式签名：CI 在 release.yml 里把 Secret 中的 keystore 解码到临时目录，
    // 通过 DSM_RELEASE_* 环境变量注入。跨版本签名一致后，应用内下载 APK 才能直接覆盖安装
    //（签名不一致会被系统拒绝，用户只能卸载重装）。密钥本体不入仓库（红线 3），
    // 本机配置方法见 docs/release-signing.md。
    // 未注入环境变量时不再静默回退 debug 签名：debug keystore 由各环境现场生成、互不相同，
    // 用它签出的 release 包会让已安装正式签名版本的用户永远无法覆盖安装。因此默认让 release
    // 构建失败（fail closed），只有显式 -PdsmAllowDebugSigning=true 才放行（仅限本机验证打包）。
    signingConfigs {
        val storeFilePath = dsmStoreFilePath
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
            // 正式签名缺失时 fail closed：不静默回退 debug 签名，只认显式的 -PdsmAllowDebugSigning=true。
            val dsmReleaseSigning = signingConfigs.findByName("dsmRelease")
            signingConfig = when {
                dsmReleaseSigning != null -> dsmReleaseSigning
                dsmAllowDebugSigning -> {
                    logger.warn(
                        "警告：未注入 DSM_RELEASE_* 环境变量，本次 release 构建使用 debug 签名。" +
                            "该 APK 严禁用于发布（debug 签名每个环境都不同，已安装正式签名版本的用户" +
                            "无法覆盖安装），仅限本机验证打包流程。详见 docs/release-signing.md。"
                    )
                    signingConfigs.getByName("debug")
                }
                // 置空即「没有可用的正式签名」；本次构建会在任务执行前直接失败（见文件末尾的校验），
                // 不会产出任何 release 包。
                else -> null
            }
        }
    }

    buildFeatures {
        compose = true
        // QA 测试通知入口依赖 BuildConfig.DEBUG 门控（仅 debug 构建显示，release 自动剔除）
        buildConfig = true
    }
}

// release 构建 fail closed：没有固定签名（且未显式放行 debug 签名）时，任何会产出 release 包
//（APK / AAB）的构建都在任务执行前失败，杜绝「用 debug 密钥签名发布」。
// 不把这段判断直接写进 buildTypes.release：android {} 的配置对每次 Gradle 调用都会求值，
// 在那里抛异常会连 :app:assembleDebug、:core:test 一起失败（debug 构建必须照常可用），
// 因此改为在任务图确定后判断本次构建是否真的要产出 release 包。
gradle.taskGraph.whenReady {
    // Kotlin DSL 里 Action<TaskExecutionGraph> 是「接收者风格」lambda：this 即本次构建的任务图。
    val releaseArtifactTasks = setOf(
        "assembleRelease",
        "packageRelease",
        "packageReleaseBundle",
        "bundleRelease",
    )
    val buildsReleaseArtifact = allTasks.any { it.name in releaseArtifactTasks }
    if (dsmStoreFilePath == null && !dsmAllowDebugSigning && buildsReleaseArtifact) {
        throw GradleException(
            """
            未配置 release 签名，已中止本次 release 构建（缺少 DSM_RELEASE_* 环境变量）。
            用 debug 密钥签名发布 APK 会让已安装正式签名版本的用户永远无法覆盖安装：
            应用内更新会因签名不一致被系统拒绝，用户只能卸载重装，Token 与设置全部丢失。
            固定签名的配置与备份方法见 docs/release-signing.md。
            仅在本机无密钥、只想验证 release 变体能否编译打包时，可显式放行 debug 签名：
              ./gradlew :app:assembleRelease -PdsmAllowDebugSigning=true
            """.trimIndent()
        )
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
