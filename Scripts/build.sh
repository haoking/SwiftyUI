#!/usr/bin/env bash
# 构建 SwiftyUI 库。
# 不能用 `swift build`:本包仅依赖 UIKit,在 macOS 宿主上会失败。
set -euo pipefail
cd "$(dirname "$0")/.."

LOG=".build/build.log"
mkdir -p .build

# 完整输出落盘,再筛出有用的行。
# 不要用 `xcodebuild | grep ... || true` 再取 PIPESTATUS:`|| true` 是一条
# 简单命令,会把 PIPESTATUS 重置为 (0),真实失败会被吞掉。
set +e
xcodebuild build \
  -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme SwiftyUI \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/xcode \
  "$@" > "$LOG" 2>&1
status=$?
set -e

grep -E '^(/.*(error|warning):|\*\* BUILD)' "$LOG" || true
if [ "$status" -ne 0 ]; then
  echo "--- 构建失败,完整日志见 $LOG,末尾 30 行: ---"
  tail -30 "$LOG"
fi
exit "$status"
