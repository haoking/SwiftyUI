#!/usr/bin/env bash
# 在 iOS 模拟器上运行单元测试。
# 不能用 `swift test`:本包仅依赖 UIKit,在 macOS 宿主上会失败。
#
# 用法:
#   Scripts/test.sh                                   跑全部测试
#   Scripts/test.sh SwiftyUITests/SwiftyColorTests    只跑某个 test case
set -euo pipefail
cd "$(dirname "$0")/.."

# 解析一台可用的 iPhone 模拟器。
#
# 不能写 name=iPhone 16 Pro:同名设备存在 arm64 与 x86_64 两条记录,xcodebuild 会因歧义失败。
# 但也不能只取 tail -1:选中哪台取决于本机装了什么以及 simctl 的列出顺序,
# 而取色测试对屏幕 scale 敏感、几何断言对窗口尺寸敏感 —— 换台机器就可能
# 出现无法复现的失败。因此优先钉住一个机型,缺失时才回落。
PREFERRED_DEVICE="${SWIFTYUI_SIMULATOR:-iPhone 17}"
DEVICES="$(xcrun simctl list devices available)"

# 精确匹配设备名(逐字比较,不是正则):行形如 "    iPhone 17 (UDID) (Booted)"。
# 字段分隔符用 [()] 而非转义括号:后者(如 ' \(')在某些 awk 实现上会报
# "illegal primary in regular expression"——在 pipefail 下直接崩、零输出。
# [()] 不需要转义,$1 是设备名(可能带尾随空格),$2 就是 UDID,不必再 split。
#
# awk 里不提前 exit:提前退出会在没读完 $DEVICES 时关闭管道读端,上游 printf
# 可能因此收到 SIGPIPE,pipefail 下这条 UDID=$(...) 赋值就会以非零状态阵亡且
# 零输出。本仓库在 CI 的 Xcode 选择步骤已经踩过同一个模式(见
# .github/workflows/ci.yml),这里改成让 awk 读完全部输入、把候选交给
# tail -1 去挑,顺带也和下面回落那行的取法(同名重复时取最后一条)保持一致。
UDID="$(printf '%s\n' "$DEVICES" | awk -F'[()]' -v want="$PREFERRED_DEVICE" '
  { name=$1; gsub(/^ +/, "", name); gsub(/ +$/, "", name); if (name == want) print $2 }' | tail -1)"

if [ -z "$UDID" ]; then
  echo "提示:未找到 \"$PREFERRED_DEVICE\",回落到任意可用 iPhone。" >&2
  echo "     可用 SWIFTYUI_SIMULATOR 指定机型。" >&2
  UDID="$(printf '%s\n' "$DEVICES" | awk -F'[()]' '/    iPhone/ {print $2}' | tail -1)"
fi

if [ -z "$UDID" ]; then
  echo "错误:找不到可用的 iPhone 模拟器" >&2
  exit 1
fi

# 把实际选中的设备打进日志 —— 失败无法复现时,第一件要知道的事就是当时跑在哪台上。
DEVICE_NAME="$(printf '%s\n' "$DEVICES" | grep -F "$UDID" | head -1 | sed -E 's/^ *(.*) \([0-9A-F-]+\).*$/\1/')"
echo "使用模拟器:${DEVICE_NAME:-未知} ($UDID)"

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
