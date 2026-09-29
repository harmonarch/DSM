#!/bin/bash
# 生成两侧核心文件指纹（Sources/DeepSeekMeter/ 与 ios/DeepSeekMeterCore/Sources/DeepSeekMeterCore/ 逐文件对应的文件）。
# 每个文件记两行：先 macOS 侧，后 iOS 侧；任一侧改动都会让 check-core-drift.sh 失败（双向防漂移）。
# 用法：bash Scripts/fingerprint-core.sh
# 说明：核心逻辑改动后，先确认两侧实现一致（macOS 改动 → 移植到 iOS 核心包；iOS 改动 → 确认是否回移 macOS），
#       再重新生成指纹（见 check-core-drift.sh 与 AGENTS.md 红线 13）。
set -euo pipefail
cd "$(dirname "$0")/.."

# 逐文件对应的镜像核心文件（两侧同名）。必须与 Scripts/check-core-drift.sh 的 MIRROR_FILES 保持一致。
MIRROR_FILES=(
  "AppModel.swift"
  "Formatting.swift"
  "Models.swift"
  "PlatformService.swift"
  "WAFGuard.swift"
)
MAC_DIR="Sources/DeepSeekMeter"
IOS_DIR="ios/DeepSeekMeterCore/Sources/DeepSeekMeterCore"
OUT="ios/DeepSeekMeterCore/CORE_FINGERPRINT"

# 列出目录顶层的 .swift 文件名（与 check-core-drift.sh 中的同名函数保持一致）
list_swift_names() {
  find "$1" -maxdepth 1 -type f -name '*.swift' -exec basename {} \; | LC_ALL=C sort
}

TMP=$(mktemp)
EXPECTED_TMP=$(mktemp)
ACTUAL_TMP=$(mktemp)
# 刻意不用 EXIT trap：bash 3.2 下 trap 会把异常退出码吞成 0，改为每条退出路径显式清理
cleanup() {
  rm -f "$TMP" "$EXPECTED_TMP" "$ACTUAL_TMP"
}

# 安全网：清单必须与两侧目录的实际交集一致，避免生成"漏覆盖"的指纹
printf '%s\n' "${MIRROR_FILES[@]}" | LC_ALL=C sort > "$EXPECTED_TMP"
LC_ALL=C comm -12 <(list_swift_names "$MAC_DIR") <(list_swift_names "$IOS_DIR") > "$ACTUAL_TMP"
if ! diff -q "$EXPECTED_TMP" "$ACTUAL_TMP" >/dev/null; then
  echo "镜像核心文件清单与实际目录不一致，拒绝生成漏覆盖的指纹："
  echo "  macOS: ${MAC_DIR}/"
  echo "  iOS:   ${IOS_DIR}/"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$MAC_DIR/$f" ] || [ ! -f "$IOS_DIR/$f" ]; then
      echo "  · ${f}：某一侧缺失（被删除或改名 → 请同步另一侧并更新 MIRROR_FILES 清单）"
    fi
  done < "$EXPECTED_TMP"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! grep -qxF "$f" "$EXPECTED_TMP"; then
      echo "  · ${f}：两侧新增了同名文件但未纳入 MIRROR_FILES 清单（应镜像 → 加入清单；不应镜像 → 改名避免误判）"
    fi
  done < "$ACTUAL_TMP"
  echo "处理：同步更新 Scripts/fingerprint-core.sh 与 Scripts/check-core-drift.sh 的 MIRROR_FILES 清单"
  cleanup
  exit 1
fi

for f in "${MIRROR_FILES[@]}"; do
  for p in "$MAC_DIR/$f" "$IOS_DIR/$f"; do
    if [ ! -f "$p" ]; then
      echo "文件不存在: $p"
      echo "处理：确认是否误删；若已改名，请同时更新两侧目录与 MIRROR_FILES 清单"
      cleanup
      exit 1
    fi
    shasum -a 256 "$p" >> "$TMP"
  done
done

mv "$TMP" "$OUT"
echo "两侧指纹已写入 $OUT"
cat "$OUT"
cleanup
