# Android 固定签名密钥（发布与应用内更新）

> 为什么需要固定签名：应用内更新会下载新 APK 直接覆盖安装，Android 要求新 APK 与已安装
> APK **签名一致**，否则系统拒绝安装（用户只能卸载重装、丢失 Token 和设置）。
> 2026-09 之前 Release APK 用 runner 现场生成的 debug keystore 签名，每个版本签名都不同，
> 因此 v0.0.5 及更早版本升级到固定签名版本时，需要手动卸载重装一次（最后一次）。

## 密钥存放在哪里

| 位置 | 内容 | 说明 |
| --- | --- | --- |
| GitHub Secrets（`harmonarch/DSM`） | `DSM_KEYSTORE_BASE64`、`DSM_RELEASE_STORE_PASSWORD` | release.yml 构建时解码注入，密钥本体不入仓库（红线 3） |
| 维护者本机 `~/DeepSeekMeter-release-keys/` | `dsm-release.keystore`、`STORE_PASSWORD.txt`、`dsm-release.keystore.b64` | 唯一离线备份，权限 700/600，**务必另行备份**（丢失则无法再覆盖安装，只能让用户卸载重装） |

- alias：`dsm`（固定，写死在 release.yml 与文档中）
- 证书 SHA-256 指纹：`AD:05:60:C9:12:D5:D7:21:A1:D6:E6:76:96:CA:89:B5:DA:01:65:F0:9C:7E:7C:F1:FE:27:34:1F:6A:34:31:3F`
- 生成信息：RSA 2048 / PKCS12 / 有效期 10950 天（30 年），生成于 2026-09-12

## CI 如何注入

`.github/workflows/release.yml` 的 `build-android` job 中：
`DSM_KEYSTORE_BASE64` → 解码到 `$RUNNER_TEMP`，并导出 `DSM_RELEASE_STORE_FILE` /
`DSM_RELEASE_STORE_PASSWORD` / `DSM_RELEASE_KEY_ALIAS` / `DSM_RELEASE_KEY_PASSWORD`
四个环境变量；`android/app/build.gradle.kts` 检测到这些变量即用固定签名，
未配置时回退 debug 签名（fork / 无 Secret 环境保持可构建）。

## 本机构建正式签名 APK

```bash
KEYDIR="$HOME/DeepSeekMeter-release-keys"
DSM_RELEASE_STORE_FILE="$KEYDIR/dsm-release.keystore" \
DSM_RELEASE_STORE_PASSWORD="$(cat "$KEYDIR/STORE_PASSWORD.txt")" \
DSM_RELEASE_KEY_ALIAS=dsm \
DSM_RELEASE_KEY_PASSWORD="$(cat "$KEYDIR/STORE_PASSWORD.txt")" \
  ./gradlew :app:assembleRelease --no-daemon
```

验证签名（确认是 `dsm` 而非 debug）：

```bash
keytool -printcert -jarfile android/app/build/outputs/apk/release/app-release.apk
```

## 换密钥意味着什么

只要换 keystore，所有存量用户下次升级必须卸载重装。除非密钥泄露，永远不要换。
