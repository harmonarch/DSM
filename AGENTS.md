# AGENTS.md — DeepSeekMeter 仓库操作规范

> This file is the operating manual for AI coding agents (Claude Code, Cursor, Codex, etc.).
> 开始在本仓库修改代码之前，请先完整阅读本文件，并严格遵守其中的规范与边界。

## 1. 项目是什么

DeepSeekMeter 是一个 **macOS 菜单栏小工具**（SwiftUI + AppKit）：实时展示 DeepSeek 平台账户的余额、本月费用、Token 用量与按天趋势。

- 工具链：Swift 6（swift-tools-version 6.0），**Swift 5 语言模式**（Package.swift 中显式设置）
- 平台：主包为 macOS 14+（Apple Silicon / Intel 均可）；移动端 iOS / Android 独立成端，见下一行
- 移动端：iOS 版（`ios/`，M1–M5 代码完成，分发待账号）与 Android 版（`android/`，A4 完成，A5 规划中），总体方案见 MOBILE-PLAN.md
- 构建：Swift Package Manager，**无 Xcode 工程、无任何第三方依赖、单 target**（仅指 macOS 包；iOS 工程在 `ios/` 内，见红线 6、13）
- 测试：轻量自测——macOS 用 swiftc 直接编译运行（`Scripts/selftest`），iOS 核心包用 `swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest`，Android 用本地 JVM 单测，均**不依赖 XCTest**
- CI：GitHub Actions（push main / PR 触发，覆盖 macOS / Windows / iOS / Android）；发布：打 `v*` 标签自动出 macOS DMG/ZIP、Windows ZIP、Android APK 与 SHA256SUMS Release（tag 须与四端版本号一致）
- 用户文档：README.md（中文，默认）+ README.en.md（英文），双语惯例

## 2. 常用命令（改动后必须本地验证）

```bash
swift run                        # 开发模式运行（无 .app 外壳）
swift build                      # debug 构建
swift build -c release           # release 构建
bash Scripts/run-tests.sh        # 运行自测（全绿才算通过）
bash Scripts/build-app.sh release # 组装 build/DeepSeekMeter.app 并签名
bash Scripts/install.sh          # 构建 + 安装到 /Applications 并启动

# iOS 版验证（核心包自测 + 工程结构静态校验必跑；有 Xcode 时还会构建 App 冒烟）
bash Scripts/run-ios-tests.sh
python3 Scripts/check-ios-project.py   # 单独跑工程结构校验（无 Xcode 环境的把关）
bash Scripts/check-core-drift.sh       # 校验 macOS 核心文件与 iOS 核心包未漂移

# 本机有 Xcode 后：一键跑 iOS 模拟器（构建 + 运行 + 截图），详见 docs/install-xcode-and-run.md
bash Scripts/run-ios-simulator.sh

# Android 核心单测（需 JDK 17 + Android SDK；JVM 直跑无需设备）
cd android && ./gradlew :core:test

# 版本号（四端一致性校验；发版用 bump-version.sh 一处改全，见第 7 节）
bash Scripts/check-version-sync.sh
bash Scripts/bump-version.sh 0.1.5
```

CI（`.github/workflows/ci.yml`）由 5 个平行 job 组成：**改动涉及哪一端，就必须让对应的 job 全绿**。

- version-sync：`check-version-sync.sh` 校验 macOS / Windows / Android / iOS 四端版本号一致，不一致直接失败
- macOS：`swift build` → `swift build -c release` → `run-tests.sh` → `build-app.sh release` → 冒烟启动 6 秒
- Windows：`dotnet build windows/DeepSeekMeter.sln -c Release` → `DeepSeekMeter.Selftest` → 冒烟启动 6 秒
- iOS：`check-core-drift.sh` → 核心包自测 → `check-ios-project.py` → 无签名模拟器构建
- Android：`./gradlew :core:test :app:assembleDebug`

只改文档或脚本时，至少跑与受影响端对应的命令。

注意：`swift run` 时 `Bundle.main.bundleIdentifier` 为 nil，开机自启注册会被跳过（SettingsStore 中已处理），这是预期行为，不是 Bug。

## 3. 仓库结构

```
Sources/DeepSeekMeter/
  AppMain.swift                  @main 入口；.accessory 激活策略（仅菜单栏，无 Dock 图标）
  AppDelegate.swift              生命周期组装：SettingsStore → AppModel → StatusItemController
  StatusItemController.swift     菜单栏 NSStatusItem + NSPopover 宿主（内容尺寸自适应）
  AppModel.swift                 状态中枢：@MainActor ObservableObject；轮询、拉取、错误状态
  PlatformService.swift          DeepSeek 平台私有接口客户端 + PlatformError
  Models.swift                   网络模型（Decodable）+ MonthUsage 聚合模型
  UpdateService.swift            应用内更新检查（GitHub Release 只读，见第 4 节）
  SettingsStore.swift            设置持久化（UserDefaults）+ 开机自启 + 旧钥匙串一次性迁移
  Formatting.swift               format() / currencySymbol() 等纯函数
  WAFGuard.swift                 平台前置风控（AWS WAF）适配：挑战判定 + 浏览器票据组装（纯函数）
  LoginWindowController.swift    内嵌官方登录页（WKWebView）+ Token 自动提取
  Views/
    PopoverView.swift            悬浮窗主界面（SwiftUI）
    SparklineView.swift          Token 按天用量柱状图
windows/                         Windows 版（.NET 8 + WPF，与 macOS 版功能对齐）
  src/DeepSeekMeter.Core/        纯逻辑库（PlatformService / Models / Formatting / SettingsStore / UpdateService / TokenProtector 等，零第三方依赖）
  src/DeepSeekMeter/             WPF 应用：MainViewModel / TrayIconController / PopoverWindow / LoginWindow 等
  tests/DeepSeekMeter.Selftest/  轻量自测（控制台，零测试框架）
  README.md                      Windows 英文说明（含与 macOS 版对应关系）
  README.zh-CN.md                Windows 中文说明
ios/                             iOS 版（M1–M5 完成，分发待账号，详见 MOBILE-PLAN.md）
  DeepSeekMeterCore/             共享核心 Swift Package（PlatformService / Models / Formatting / WAFGuard / TokenStoring / AppModel / BalanceSnapshot，零第三方依赖；AppModel 注入 TokenStoring+URLSession，可在 macOS 上自测）
  DeepSeekMeter.xcodeproj        iOS App 工程（SwiftUI，Xcode 16 同步文件夹格式）
  DeepSeekMeter/                 iOS App 源码（DeepSeekMeterApp(@main) / AppDelegate / ContentView / TokenStore(Keychain) / Views/ / NotificationService / BackgroundRefreshService）
  DeepSeekMeterWidget/           WidgetKit 余额小组件（快照驱动；Token 不进 App Group 共享容器）
  DeepSeekMeterCore/Sources/DeepSeekMeterCoreSelftest/  核心轻量自测（swift run 直接跑，不依赖 XCTest）
android/                         Android 版（A4 已完成，A5 规划中，详见 MOBILE-PLAN.md 第 4 节）
  app/                           Compose App 层（UI / 前台轮询 / 通知 / 应用内更新）
  core/                          纯逻辑核心模块（Kotlin，零第三方业务依赖；org.json 手写映射）
  core/src/test/                 本地 JVM 单测（无需设备；org.json 测试期用官方 jar 替身）
Scripts/
  build-app.sh / install.sh / notarize.sh / run-tests.sh / run-ios-tests.sh / run-ios-simulator.sh
  bump-version.sh                一处更新四端版本号（发版用，结尾自动校验一致性）
  check-version-sync.sh          校验四端版本号一致（CI version-sync job 调用）
  check-core-drift.sh            校验 macOS 核心文件与 iOS 核心包未漂移（红线 13 的执行者，CI 调用）
  fingerprint-core.sh            核心文件改动后更新 CORE_FINGERPRINT
  check-ios-project.py           无 Xcode 环境的 iOS 工程结构静态校验（CI 调用）
  make-icon.sh / generate-icon.swift / make-windows-icon.ps1 / generate-android-icon.swift
  publish-windows.ps1            Windows 发布辅助
  Info.plist                     应用包信息（版本号用 Scripts/bump-version.sh 统一改，勿手改单端）
  selftest/main.swift            轻量自测源码（swiftc 编译运行）
.github/workflows/
  ci.yml                         push main / PR：version-sync（四端版本号一致）+ macOS / Windows / iOS / Android 构建与自测；iOS job 另含核心漂移校验与工程结构校验
  release.yml                    打 v* 标签：version-check（tag 与四端版本号一致）→ 构建 macOS DMG/ZIP、Windows ZIP、Android APK 与 SHA256SUMS 并发布 GitHub Release
```

## 4. 架构分层（改动必须遵循）

依赖方向只允许自上而下：

```
UI（Views / StatusItemController / LoginWindowController）
        ↓ 读写 @Published 状态
AppModel / SettingsStore（@MainActor，状态与持久化）
        ↓ 调用
PlatformService（DeepSeek 平台接口入口） + UpdateService（GitHub 更新检查，只读） + Models（解码模型）
        ↓
Foundation / AppKit / SwiftUI / WebKit
```

- DeepSeek 平台的网络请求只能经过 `PlatformService`；错误统一转为 `PlatformError`（带用户可读的中文 message）
- 平台前置有 AWS WAF：原生 URLSession 请求可能被挑战（HTTP 202 + `x-amzn-waf-action`，实测 macOS 27 起触发）。登录校验这类接口必须附上浏览器上下文解出的票据（`WAFGuard` + 登录窗 cookie），被挑战时抛 `PlatformError.wafChallenge`，**不要**当作普通 HTTP 错误反复重试（会被判为机器人，加重风控）
- 应用内更新的网络请求走独立的 `UpdateService`（GET api.github.com 的 releases/latest 与 Release 资源下载，只读、不上报任何本地数据，详见 Sources/DeepSeekMeter/UpdateService.swift；Windows/Android 同构实现）
- UI 只读模型层的 `@Published` 状态，**不直接发起网络请求**
- 新接口的响应模型写成 `Decodable` struct 放进 Models.swift，沿用平台 `{code, msg, data: {biz_code, biz_msg, biz_data}}` 包裹结构（注意 `biz_data` 有时是对象、有时是数组，以真实响应为准）
- 纯函数（格式化、币种符号、聚合计算）放 Formatting.swift / Models.swift 计算属性，并补自测
- 代码注释用中文 `///`；分组用 `// MARK: -`；UI 文案用中文

## 5. 提交规范（Conventional Commits，中文描述）

```
<type>(<scope>): <中文描述>
```

- type：`feat` / `fix` / `docs` / `refactor` / `chore` / `ci` / `test` / `perf`
- scope 可选（如 `ci`、`ui`、`api`）；描述用中文，一句话说清改了什么、为什么
- 示例：`fix(ci): build-app.sh 在无开发者证书环境下不再被 set -e 中断`

要求：
- 小步提交，一次提交只做一件事
- 不提交构建产物：`.build/`、`build/`、`.DS_Store` 已被 .gitignore 忽略，不要 `git add -f` 强加
- 提交信息与 diff 中不得出现真实 Token / 凭据

## 6. 分支与 PR 流程

1. 从 `main` 切分支，命名建议 `feat/xxx`、`fix/xxx`
2. 本地验证完整链（见第 2 节）
3. 提 PR 到 `main`，按 .github/pull_request_template.md 逐项填写勾选
4. PR 触发 CI，**CI 全绿才可合入**（建议 squash 合并）
5. PR 还会触发「AI Review」workflow（.github/workflows/ai-review.yml）：基于本文件规范与边界用 DeepSeek API 自动审查并提交 COMMENT 意见（更新式，只删旧 review 不发重复）；**它是顾问不是把关者，合并仍由维护者手动决定**。fork PR 同样审查（pull_request_target + API 获取 diff，不执行 PR 代码，secrets 安全）
6. 合入 main 的 push 也会触发 CI 验证

## 7. 发布流程（维护者）

1. `bash Scripts/bump-version.sh <x.y.z>` 一处更新四端版本号（macOS plist、Android `versionName`+`versionCode`、Windows 程序集版本、iOS `MARKETING_VERSION`+build 号）；脚本结尾会跑 `check-version-sync.sh` 确认四端一致
2. 本地 `bash Scripts/build-app.sh release` 验证
3. 打标签推送：`git tag v<版本号> && git push origin v<版本号>`。**tag 必须与四端版本号完全相等**——release.yml 的 version-check job 会校验，例如代码是 0.1.4 就只能打 `v0.1.4`，打 `v0.1.0` 会直接失败
4. release.yml 自动构建 macOS DMG/ZIP、Windows ZIP、Android APK 与 SHA256SUMS 并发布 Release（notes 自动生成；iOS 暂不发布二进制）
5. （可选）有 Developer ID 证书时用 `Scripts/notarize.sh` 公证后重新发布

## 8. 边界（红线，AI 不得越界）

以下行为视为违规，即使看起来"更完善"。括号内标注该条适用的端；未标注的适用于全仓库。

1. **不引入任何第三方依赖**。零依赖单 target 是刻意设计；新增依赖需先开 Issue 讨论
2. **（macOS）不把 Token 存回钥匙串**。ad-hoc 签名下钥匙串会每次启动弹密码授权，因此 Token 刻意存 UserDefaults；SettingsStore 中已有一次性迁移逻辑，保留即可。iOS / Android 的存储方式见红线 12
3. **不把真实 Token / 凭据写进代码、日志、截图或提交**。调试一律用占位符
4. **不臆造平台接口**。PlatformService 访问的是 platform.deepseek.com 的**私有接口**（共 4 个：`/api/v0/users/get_user_summary`、`/api/v0/usage/by_api_key/amount`、`/api/v0/usage/by_api_key/cost`，以及走 `/auth-api/v0/` 前缀的 `/auth-api/v0/users/current`；其中两个 usage 接口的参数 `start`/`end` 为 Unix 秒、`tz` 为秒偏移、`bucket` 分桶粒度），无公开文档；不要凭空猜测 URL、参数或响应字段——改动前抓真实响应验证，并同步更新 selftest 的样例 JSON
5. **不改数据流向**。所有数据只能来自 DeepSeek 官方接口，不得上报任何第三方；隐私承诺见 README「隐私与数据」
6. **（macOS）不引入 Xcode 工程或 XCTest**。测试保持 swiftc 轻量自测（Scripts/selftest/main.swift）；需要更重的测试设施先开 Issue。iOS 工程只允许存在于 `ios/` 内，且必须通过 `Scripts/check-ios-project.py` 的结构校验（见红线 13）
7. **不破坏平台与语言模式约束**：macOS 14+、Swift 5 语言模式（Package.swift）
8. **不改语言基调**：代码注释、UI 文案用中文；文档遵循 README.md（中文，默认）+ README.en.md（英文）双语惯例
9. **不破坏 CI**。合入前本地跑完整验证链；CI 红了先修复再继续
10. **不提交产物与本地文件**：`.build/`、`build/`、`.DS_Store`、`*.xcuserstate`

### 移动端红线（红线 11–13，编号与上表连续）

11. **（iOS / Android）移动端同样零第三方依赖**：iOS/Android 业务逻辑零第三方依赖；系统框架（URLSession / SwiftUI / WebKit / Security / WidgetKit，以及 Android 的 Compose / HttpURLConnection / WorkManager 等）与平台官方工具不视为第三方（与 Windows 版 WebView2 例外同理）。其中 WorkManager 为 androidx 官方后台调度库，准入已经过 Issue 讨论（红线 1，见 [Issue #11](https://github.com/pppolf/DeepSeekMeter/issues/11)），仅用于 `:app` 层后台刷新，`:core` 保持零 AndroidX 依赖；其他 androidx 库（如 Room / DataStore）不因本条目自动豁免，引入前同样需按红线 1 单独开 Issue 讨论
12. **（iOS / Android）Token 存储分平台**：红线 2 仅约束 macOS；**iOS 用 Keychain（kSecClassGenericPassword）、Android 用 Keystore 加密后存 SharedPreferences**——移动端 App 有正式签名，钥匙串不会弹窗；同样不得把真实 Token 写进代码/日志/截图。**小组件快照**（App Group UserDefaults）只放余额等非敏感展示数据，不放 Token
13. **（iOS / Android）移动端核心逻辑统一在 `ios/DeepSeekMeterCore`**（Swift 5 语言模式，与 Sources/DeepSeekMeter/ 逐文件对应，防三端漂移）；改动任一侧核心文件（PlatformService / Models / Formatting / WAFGuard）后，必须跑 `bash Scripts/fingerprint-core.sh` 更新 `CORE_FINGERPRINT` 并跑核心自测（第 2 节命令），CI 用 `Scripts/check-core-drift.sh` 拦截漏同步；`.xcodeproj` 只允许存在于 `ios/` 内，macOS 包保持无 Xcode 工程；新接口改动前先抓真实响应验证并同步更新自测样例 JSON（红线 4 同样适用）

## 9. 完成标准（Definition of Done）

按「改动涉及哪一端」勾选（与 .github/pull_request_template.md 一致）：

- [ ] macOS 改动：`swift build` / `swift build -c release` / `bash Scripts/run-tests.sh` / `bash Scripts/build-app.sh release` 均通过
- [ ] 核心逻辑改动（PlatformService / Models / Formatting / WAFGuard）：`bash Scripts/fingerprint-core.sh` 已更新指纹，`check-core-drift.sh` 通过
- [ ] iOS 改动：`bash Scripts/run-ios-tests.sh` 通过（内含核心漂移校验与 `check-ios-project.py` 工程结构校验）
- [ ] Android 改动：`cd android && ./gradlew :core:test :app:assembleDebug` 通过
- [ ] Windows 改动：`dotnet build windows/DeepSeekMeter.sln -c Release` 与 `DeepSeekMeter.Selftest` 通过
- [ ] 新增纯逻辑已补自测
- [ ] 未触碰第 8 节任何红线
- [ ] 提交信息符合第 5 节规范，小步提交
- [ ] PR 描述完整、按模板勾选；CI 全绿
