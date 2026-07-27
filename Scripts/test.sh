#!/usr/bin/env bash
# 在 iOS 模拟器上运行单元测试。
# 不能用 `swift test`:本包仅依赖 UIKit,在 macOS 宿主上会失败。
#
# 用法:
#   Scripts/test.sh                                   跑全部测试
#   Scripts/test.sh SwiftyUITests/SwiftyColorTests    只跑某个 test case
set -euo pipefail
cd "$(dirname "$0")/.."

# 动态解析一台可用的 iPhone 模拟器。
# 不能写 name=iPhone 16 Pro:同名设备存在 arm64 与 x86_64 两条记录,xcodebuild 会因歧义失败。
UDID="$(xcrun simctl list devices available | awk -F'[()]' '/    iPhone/ {print $2}' | tail -1)"
if [ -z "$UDID" ]; then
  echo "错误:找不到可用的 iPhone 模拟器" >&2
  exit 1
fi

ARGS=()
if [ $# -gt 0 ]; then
  ARGS+=(-only-testing:"$1")
fi

LOG=".build/test.log"
mkdir -p .build

set +e
xcodebuild test \
  -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme SwiftyUI \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath .build/xcode \
  ${ARGS[@]+"${ARGS[@]}"} > "$LOG" 2>&1
status=$?
set -e

grep -E "^(Test Case|Test Suite 'All tests'|/.*error:|\*\* TEST)" "$LOG" || true
if [ "$status" -ne 0 ]; then
  echo "--- 测试失败,完整日志见 $LOG,末尾 40 行: ---"
  tail -40 "$LOG"
fi
exit "$status"
