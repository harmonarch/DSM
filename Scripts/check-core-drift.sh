#!/bin/bash
# 双向检查 macOS 与 iOS 两侧核心文件是否漂移。
# 原则：两份核心逻辑必须逐文件对应（防三端漂移，见 MOBILE-PLAN.md 3.3 / AGENTS.md 红线 13）。
# 指纹 ios/DeepSeekMeterCore/CORE_FINGERPRINT 同时记录两侧哈希，因此任一侧单独改动都会被发现：
#   macOS 侧改动 → 需同步移植到 ios/DeepSeekMeterCore；iOS 侧改动 → 需确认是否回移 macOS。
# 用法：bash Scripts/check-core-drift.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# 逐文件对应的镜像核心文件（两侧同名）。清单是权威来源，顺序稳定（字母序），与 CORE_FINGERPRINT 一致。
# iOS 专有（TokenStoring / BalanceSnapshot）与 macOS 专有（SettingsStore / UpdateService 等）不在此列。
# 清单与两侧目录实际交集不一致时直接失败（见下方清单校验），不会静默漏覆盖。
MIRROR_FILES=(
  "AppModel.swift"
  "Formatting.swift"
  "Models.swift"
  "PlatformService.swift"
  "WAFGuard.swift"
)
MAC_DIR="Sources/DeepSeekMeter"
IOS_DIR="ios/DeepSeekMeterCore/Sources/DeepSeekMeterCore"
FINGER="ios/DeepSeekMeterCore/CORE_FINGERPRINT"

# 列出目录顶层的 .swift 文件名：两侧同名即视为镜像对（子目录、非 Swift 文件不参与）
list_swift_names() {
  find "$1" -maxdepth 1 -type f -name '*.swift' -exec basename {} \; | LC_ALL=C sort
}

# 从 "sha256  path" 文件里取某路径的哈希；缺失时输出空串
hash_of() {
  grep -F "  $2" "$1" 2>/dev/null | head -n 1 | awk '{print $1}' || true
}

HASH_TMP=$(mktemp)
EXPECTED_TMP=$(mktemp)
ACTUAL_TMP=$(mktemp)
# 刻意不用 EXIT trap：bash 3.2 下 trap 会把异常退出码吞成 0（守卫会静默变绿），改为每条退出路径显式清理
cleanup() {
  rm -f "$HASH_TMP" "$EXPECTED_TMP" "$ACTUAL_TMP"
}

if [ ! -f "$FINGER" ]; then
  echo "缺少指纹文件 ${FINGER}，请先运行：bash Scripts/fingerprint-core.sh"
  cleanup
  exit 1
fi

# 1) 清单校验：MIRROR_FILES 必须与两侧目录的实际交集完全一致
printf '%s\n' "${MIRROR_FILES[@]}" | LC_ALL=C sort > "$EXPECTED_TMP"
LC_ALL=C comm -12 <(list_swift_names "$MAC_DIR") <(list_swift_names "$IOS_DIR") > "$ACTUAL_TMP"
if ! diff -q "$EXPECTED_TMP" "$ACTUAL_TMP" >/dev/null; then
  echo "镜像核心文件清单校验失败：MIRROR_FILES 与两侧同名 .swift 文件的实际交集不一致"
  echo "  macOS: ${MAC_DIR}/"
  echo "  iOS:   ${IOS_DIR}/"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$MAC_DIR/$f" ]; then
      echo "  · ${f}：macOS 侧缺失 $MAC_DIR/${f}（被删除或改名 → 请同步另一侧并更新 MIRROR_FILES 清单）"
    fi
    if [ ! -f "$IOS_DIR/$f" ]; then
      echo "  · ${f}：iOS 侧缺失 $IOS_DIR/${f}（被删除或改名 → 请同步另一侧并更新 MIRROR_FILES 清单）"
    fi
  done < "$EXPECTED_TMP"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! grep -qxF "$f" "$EXPECTED_TMP"; then
      echo "  · ${f}：两侧新增了同名文件但未纳入 MIRROR_FILES 清单（应镜像 → 加入清单；不应镜像 → 改名避免误判）"
    fi
  done < "$ACTUAL_TMP"
  echo "处理：核对两侧文件名后更新 Scripts/check-core-drift.sh 与 Scripts/fingerprint-core.sh 的 MIRROR_FILES 清单"
  echo "      再运行 bash Scripts/fingerprint-core.sh 更新指纹，并运行 bash Scripts/run-ios-tests.sh 确认核心自测全绿"
  cleanup
  exit 1
fi

# 2) 生成两侧当前哈希（顺序与 MIRROR_FILES 一致：每个文件先 macOS 后 iOS）
for f in "${MIRROR_FILES[@]}"; do
  for p in "$MAC_DIR/$f" "$IOS_DIR/$f"; do
    if [ ! -f "$p" ]; then
      echo "文件不存在: $p"
      echo "处理：确认是否误删；若已改名，请同时更新两侧目录与 MIRROR_FILES 清单后重跑 fingerprint-core.sh"
      cleanup
      exit 1
    fi
    shasum -a 256 "$p" >> "$HASH_TMP"
  done
done

if diff -q "$HASH_TMP" "$FINGER" >/dev/null; then
  echo "两侧核心文件与指纹一致，无漂移"
  cleanup
  exit 0
fi

# 3) 逐文件比对，指出是哪一侧改了
echo "检测到核心文件漂移："
mac_changed=0
ios_changed=0
for f in "${MIRROR_FILES[@]}"; do
  mac="$MAC_DIR/$f"
  ios="$IOS_DIR/$f"
  mac_was=$(hash_of "$FINGER" "$mac")
  ios_was=$(hash_of "$FINGER" "$ios")
  if [ -z "$mac_was" ]; then
    echo "  · [指纹缺失] $mac 在 ${FINGER} 中没有记录（指纹格式过旧？）"
  fi
  if [ -z "$ios_was" ]; then
    echo "  · [指纹缺失] $ios 在 ${FINGER} 中没有记录（指纹格式过旧？）"
  fi
  if [ "$(hash_of "$HASH_TMP" "$mac")" != "$mac_was" ]; then
    echo "  · [macOS 侧] $mac 有改动"
    mac_changed=1
  fi
  if [ "$(hash_of "$HASH_TMP" "$ios")" != "$ios_was" ]; then
    echo "  · [iOS 侧]   $ios 有改动"
    ios_changed=1
  fi
done

if [ "$mac_changed" = "0" ] && [ "$ios_changed" = "0" ]; then
  echo "  指纹文件与当前 MIRROR_FILES 清单不一致（可能残留旧路径或旧格式记录）"
elif [ "$mac_changed" = "1" ] && [ "$ios_changed" = "1" ]; then
  echo "结论：两侧都改过。请确认 macOS 与 iOS 两份实现语义一致，而不是各改各的。"
elif [ "$mac_changed" = "1" ]; then
  echo "结论：macOS 侧改过，改动需要同步移植到 ios/DeepSeekMeterCore/Sources/DeepSeekMeterCore/（否则 iOS 会落后）"
else
  echo "结论：iOS 侧改过，需要确认是否回移 Sources/DeepSeekMeter/（iOS 侧先改时别把 macOS 落下）"
fi

echo "处理：1) 确认两侧实现一致（Sources/DeepSeekMeter/ ↔ ios/DeepSeekMeterCore/Sources/DeepSeekMeterCore/）"
echo "      2) 运行 bash Scripts/fingerprint-core.sh 更新两侧指纹"
echo "      3) 运行 bash Scripts/run-ios-tests.sh 确认核心自测全绿"
cleanup
exit 1
