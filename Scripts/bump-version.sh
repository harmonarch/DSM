#!/bin/bash
# 一处更新四端版本号（macOS / Windows / Android / iOS）。
# 背景：同一个版本号散在 4 个平台的 4 个文件里，过去每次发版都要手工改 5 处以上，
# 且多次漏改（如 iOS 工程长期停在 0.1.0）。
# 用法：bash Scripts/bump-version.sh <x.y.z>
#   - 主版本号统一写进四端；versionCode 与 iOS build 号各自 +1（发版递增，不可回退）
#   - 若四端已都是该版本，则只做对齐修复，不再递增版本号（幂等，可安全重跑）
# 改完自动跑一遍 Scripts/check-version-sync.sh 确认四端一致。
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST="Scripts/Info.plist"
GRADLE="android/app/build.gradle.kts"
CSPROJ="windows/src/DeepSeekMeter/DeepSeekMeter.csproj"
PBXPROJ="ios/DeepSeekMeter.xcodeproj/project.pbxproj"

VERSION="${1:-}"
if ! printf '%s' "${VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "用法：bash Scripts/bump-version.sh <x.y.z>（例：0.1.5）" >&2
  exit 1
fi

for f in "${PLIST}" "${GRADLE}" "${CSPROJ}" "${PBXPROJ}"; do
  [ -f "${f}" ] || { echo "文件不存在：${f}" >&2; exit 1; }
done

# 重写文件，并保持原有的结尾换行状态。
# awk / sed 会给「结尾没有换行」的文件补一个换行，白添一条无意义的末尾 diff。
rewrite() { # $1=目标文件；标准输入=新内容
  local target="$1" tmp tmp2
  tmp=$(mktemp); tmp2=$(mktemp)
  cat > "${tmp}"
  if [ -s "${target}" ] && [ -n "$(tail -c1 "${target}" | tr -d '\n')" ]; then
    printf '%s' "$(cat "${tmp}")" > "${tmp2}"   # 原文件无尾换行 → 去掉新内容的尾换行
  else
    cp "${tmp}" "${tmp2}"
  fi
  mv "${tmp2}" "${target}"
  rm -f "${tmp}"
}

# plist 取值：取 <key>K</key> 之后第一个 <string> 的内容
plist_value() {
  awk -v key="$1" '
    index($0, "<key>" key "</key>") { getline; gsub(/.*<string>/, ""); gsub(/<\/string>.*/, ""); print; exit }
  ' "$2"
}
# plist 写值：定位 key 行，替换紧随其后的 <string> 值，保留原有缩进
plist_set() {
  awk -v key="$2" -v val="$3" '
    { print }
    index($0, "<key>" key "</key>") {
      getline
      match($0, /^[[:space:]]*/)
      print substr($0, 1, RLENGTH) "<string>" val "</string>"
    }
  ' "$1" | rewrite "$1"
}
# 原地替换（临时文件 + mv，规避 macOS / Linux 的 sed -i 差异）
subst() { # $1=ERE $2=替换 $3=文件
  sed -E "s#$1#$2#" "$3" | rewrite "$3"
}
# 取第一个匹配到的整数字段；同一字段出现多处时必须同值
int_field() { # $1=sed 提取表达式 $2=文件 $3=字段名（报错用）
  local values value
  values=$(sed -nE "$1" "$2")
  if [ "$(printf '%s\n' "${values}" | grep -c .)" -gt 1 ] && \
     [ "$(printf '%s\n' "${values}" | sort -u | grep -c .)" -ne 1 ]; then
    echo "${2} 中 ${3} 有多处且取值不一致，请先人工确认" >&2
    exit 1
  fi
  value=$(printf '%s\n' "${values}" | grep . | head -1)
  if ! printf '%s' "${value}" | grep -qE '^[0-9]+$'; then
    echo "从 ${2} 取 ${3} 失败，请检查文件结构是否变化" >&2
    exit 1
  fi
  printf '%s' "${value}"
}

OLD=$(plist_value CFBundleShortVersionString "${PLIST}")
[ -n "${OLD}" ] || { echo "从 ${PLIST} 取当前版本号失败" >&2; exit 1; }

# 已是目标版本时视为「对齐修复」：只补齐掉队的平台，不递增版本号，便于安全重跑
REPAIR_ONLY=0
[ "${OLD}" = "${VERSION}" ] && REPAIR_ONLY=1
BUMP=$((1 - REPAIR_ONLY))
if [ "${REPAIR_ONLY}" -eq 1 ]; then
  echo "macOS 已是 ${VERSION}：本次只把其它三端对齐，不递增 versionCode / iOS build 号"
else
  echo "版本号：${OLD} → ${VERSION}"
fi
echo

# macOS：短版本号与 build 号在仓库里同值（check-version-sync.sh 会校验）
plist_set "${PLIST}" CFBundleShortVersionString "${VERSION}"
plist_set "${PLIST}" CFBundleVersion "${VERSION}"
echo "  macOS    ${PLIST}   CFBundleShortVersionString / CFBundleVersion = ${VERSION}"

# Android：versionCode 必须单调递增，发版时 +1
ANDROID_CODE=$(int_field 's/^[[:space:]]*versionCode[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "${GRADLE}" versionCode)
ANDROID_CODE_NEW=$((ANDROID_CODE + BUMP))
subst '^([[:space:]]*versionName[[:space:]]*=[[:space:]]*")[^"]*(")' "\\1${VERSION}\\2" "${GRADLE}"
subst '^([[:space:]]*versionCode[[:space:]]*=[[:space:]]*)[0-9]+' "\\1${ANDROID_CODE_NEW}" "${GRADLE}"
echo "  Android  ${GRADLE}   versionName = ${VERSION}，versionCode ${ANDROID_CODE} → ${ANDROID_CODE_NEW}"

# Windows：AssemblyVersion / FileVersion 比 Version 多一段（x.y.z.0）
subst '^([[:space:]]*<Version>)[^<]*(</Version>.*)' "\\1${VERSION}\\2" "${CSPROJ}"
subst '^([[:space:]]*<AssemblyVersion>)[^<]*(</AssemblyVersion>.*)' "\\1${VERSION}.0\\2" "${CSPROJ}"
subst '^([[:space:]]*<FileVersion>)[^<]*(</FileVersion>.*)' "\\1${VERSION}.0\\2" "${CSPROJ}"
echo "  Windows  ${CSPROJ}   Version = ${VERSION}，AssemblyVersion / FileVersion = ${VERSION}.0"

# iOS：MARKETING_VERSION 在每个 target 的 Debug/Release 各一处，必须全部改到
IOS_MARKETING=$(grep -cE 'MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+;' "${PBXPROJ}")
[ "${IOS_MARKETING}" -gt 0 ] || { echo "从 ${PBXPROJ} 未找到 MARKETING_VERSION" >&2; exit 1; }
IOS_BUILD=$(int_field 's/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "${PBXPROJ}" CURRENT_PROJECT_VERSION)
IOS_BUILD_COUNT=$(grep -cE '^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*[0-9]+;' "${PBXPROJ}")
if [ "${IOS_BUILD_COUNT}" -ne "${IOS_MARKETING}" ]; then
  echo "  提示：CURRENT_PROJECT_VERSION 有 ${IOS_BUILD_COUNT} 处、MARKETING_VERSION 有 ${IOS_MARKETING} 处，数量不一致，请人工确认" >&2
fi
IOS_BUILD_NEW=$((IOS_BUILD + BUMP))
subst '(MARKETING_VERSION = )[0-9]+\.[0-9]+\.[0-9]+;' "\\1${VERSION};" "${PBXPROJ}"
subst '^([[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*)[0-9]+' "\\1${IOS_BUILD_NEW}" "${PBXPROJ}"
echo "  iOS      ${PBXPROJ}   MARKETING_VERSION = ${VERSION}（${IOS_MARKETING} 处），build ${IOS_BUILD} → ${IOS_BUILD_NEW}"

echo
echo "改动摘要："
git diff --stat -- "${PLIST}" "${GRADLE}" "${CSPROJ}" "${PBXPROJ}" | sed 's/^/  /'
echo
bash Scripts/check-version-sync.sh
