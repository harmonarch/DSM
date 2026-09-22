#!/bin/bash
# 校验四端版本号是否一致（macOS / Windows / Android / iOS）。
# 背景：同一个版本号散在 4 个平台的 4 个文件里，历史上多次漏改
#（如 iOS 工程长期停在 0.1.0，而 macOS / Windows / Android 已到 0.1.4）。
# 版本号统一用 Scripts/bump-version.sh <x.y.z> 修改，再跑本脚本确认。
# 用法：bash Scripts/check-version-sync.sh [期望版本]
#   不带参数：只校验四端一致（CI 的 version-sync job）
#   带参数（v0.1.5 或 0.1.5）：额外校验四端版本等于它（release.yml 用 tag 调用，
#                              拦住「打了标签但版本号没改」）
# 退出码：0 = 通过，1 = 不一致
set -euo pipefail
cd "$(dirname "$0")/.."

EXPECT="${1:-}"
EXPECT="${EXPECT#v}"

PLIST="Scripts/Info.plist"
GRADLE="android/app/build.gradle.kts"
CSPROJ="windows/src/DeepSeekMeter/DeepSeekMeter.csproj"
PBXPROJ="ios/DeepSeekMeter.xcodeproj/project.pbxproj"

# plist 取值：取 <key>K</key> 之后第一个 <string> 的内容。
# 不用 PlistBuddy —— CI 跑在 Linux 上，没有这个工具。
plist_value() {
  awk -v key="$1" '
    index($0, "<key>" key "</key>") { getline; gsub(/.*<string>/, ""); gsub(/<\/string>.*/, ""); print; exit }
  ' "$2"
}

MACOS=$(plist_value CFBundleShortVersionString "${PLIST}")
MACOS_BUILD=$(plist_value CFBundleVersion "${PLIST}")
ANDROID=$(sed -nE 's/^[[:space:]]*versionName[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "${GRADLE}")
ANDROID_CODE=$(sed -nE 's/^[[:space:]]*versionCode[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "${GRADLE}")
WINDOWS=$(sed -nE 's|^[[:space:]]*<Version>([^<]+)</Version>.*|\1|p' "${CSPROJ}")
WINDOWS_ASM=$(sed -nE 's|^[[:space:]]*<AssemblyVersion>([^<]+)</AssemblyVersion>.*|\1|p' "${CSPROJ}")
WINDOWS_FILE=$(sed -nE 's|^[[:space:]]*<FileVersion>([^<]+)</FileVersion>.*|\1|p' "${CSPROJ}")
# iOS 的 MARKETING_VERSION 在每个 target 的 Debug/Release 各有一处，必须全部统一
IOS_LIST=$(grep -oE 'MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+;' "${PBXPROJ}" | sed -E 's/.*= ([0-9.]+);/\1/')
IOS_COUNT=$(printf '%s\n' "${IOS_LIST}" | grep -c . || true)
IOS=$(printf '%s\n' "${IOS_LIST}" | sort -u | grep . || true)
IOS_UNIQ_COUNT=$(printf '%s\n' "${IOS}" | grep -c . || true)
# 报错信息里用单行展示（不统一时可能是多值）
IOS_SHOW=$(printf '%s' "${IOS}" | tr '\n' '/')

FAILED=0
fail() { echo "  ✗ $1"; FAILED=1; }

echo "四端版本号："
echo "  macOS    ${PLIST}   CFBundleShortVersionString = ${MACOS:-<未取到>}"
echo "  Windows  ${CSPROJ}   Version = ${WINDOWS:-<未取到>}"
echo "  Android  ${GRADLE}   versionName = ${ANDROID:-<未取到>}（versionCode ${ANDROID_CODE:-<未取到>}）"
echo "  iOS      ${PBXPROJ}   MARKETING_VERSION = ${IOS_SHOW}（${IOS_COUNT} 处）"
echo

# 空值优先报错，避免下面把「四端都没取到」误判为一致
for pair in "macOS:${MACOS}" "Windows:${WINDOWS}" "Android:${ANDROID}" "iOS:${IOS_SHOW}"; do
  platform=${pair%%:*}
  value=${pair#*:}
  [ -n "${value}" ] || fail "${platform} 版本号未取到，检查文件结构是否变化"
done
if [ "${FAILED}" -ne 0 ]; then
  echo
  echo "版本号校验失败"
  exit 1
fi

# 1) 四端主版本号必须一致；iOS 的多处配置也必须在内部统一
for pair in "Windows:${WINDOWS}" "Android:${ANDROID}" "iOS:${IOS_SHOW}"; do
  platform=${pair%%:*}
  value=${pair#*:}
  if [ "${value}" != "${MACOS}" ]; then
    fail "${platform} 为 ${value}，与 macOS ${MACOS} 不一致"
  fi
done
if [ "${IOS_UNIQ_COUNT}" -ne 1 ]; then
  fail "iOS 的 MARKETING_VERSION 内部不统一：${IOS_SHOW}"
fi

# 2) 各端自身的格式约定（bump-version.sh 会一并维护，手工改动容易漏其中一处）
if [ "${MACOS_BUILD}" != "${MACOS}" ]; then
  fail "macOS CFBundleVersion 为 ${MACOS_BUILD}，按仓库约定应与 CFBundleShortVersionString（${MACOS}）同值"
fi
if [ "${WINDOWS_ASM}" != "${WINDOWS}.0" ]; then
  fail "Windows AssemblyVersion 为 ${WINDOWS_ASM}，应为 ${WINDOWS}.0"
fi
if [ "${WINDOWS_FILE}" != "${WINDOWS}.0" ]; then
  fail "Windows FileVersion 为 ${WINDOWS_FILE}，应为 ${WINDOWS}.0"
fi

# 3) 给定期望版本时（release.yml 传 tag）额外校验一致
if [ -n "${EXPECT}" ]; then
  if ! printf '%s' "${EXPECT}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "期望版本 ${EXPECT} 格式不合法（应形如 v0.1.5 或 0.1.5）"
  elif [ "${EXPECT}" != "${MACOS}" ]; then
    fail "标签版本 ${EXPECT} 与代码中的版本 ${MACOS} 不一致（打标签前先跑 Scripts/bump-version.sh）"
  fi
fi

echo
if [ "${FAILED}" -ne 0 ]; then
  echo "版本号校验失败：请用 bash Scripts/bump-version.sh <x.y.z> 统一修改后重试"
  exit 1
fi
if [ -n "${EXPECT}" ]; then
  echo "版本号一致 ✓（四端均为 ${MACOS}，与标签 ${EXPECT} 相符）"
else
  echo "版本号一致 ✓（四端均为 ${MACOS}）"
fi
