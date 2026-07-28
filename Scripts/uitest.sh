#!/usr/bin/env bash
# 在 iOS 模拟器上运行 iOSExample 的 XCUITest。
#
# 与 Scripts/test.sh(库的单元测试)是两条独立的入口:后者跑的是 SwiftyUI
# 这个 SPM 包的测试 target,没有宿主 App;本脚本跑的是需要真实 App 进程、
# 真实触摸与真实旋转的验收用例。
#
# 用法:
#   Scripts/uitest.sh                                        跑全部 UI 测试
#   Scripts/uitest.sh iOSExampleUITests/SwiftyUIExampleUITests/testX   只跑一条
set -euo pipefail
cd "$(dirname "$0")/.."

# 动态解析一台可用的 iPhone 模拟器。
# 不能写 name=iPhone 16 Pro:同名设备存在 arm64 与 x86_64 两条记录,xcodebuild 会因歧义失败。
UDID="$(xcrun simctl list devices available | awk -F'[()]' '/    iPhone/ {print $2}' | tail -1)"
if [ -z "$UDID" ]; then
  echo "错误:找不到可用的 iPhone 模拟器" >&2
  exit 1
fi

# 键盘避让用例需要**软件键盘真的出现在屏幕内**。
#
# 实测:只让 xcodebuild 自己拉起模拟器(无 Simulator.app)时,系统认为接着一块
# 硬件键盘,软件键盘会被停靠到屏幕外 —— frame 为 (0, 952, 402, 233),而屏幕高 874。
# 此时 keyboardWillShow 带的 frame 也在屏幕外,alert 按设计就不该上移,
# testAlertWithTextFieldAvoidsKeyboard 会红。用例本身会显式报出这一情形
# (见该用例里 waitForKeyboardOnScreen 的失败信息),不会静默通过。
#
# 解法:关掉"连接硬件键盘"(全局 + 该设备)并**启动 Simulator.app**。
# 只写偏好不启动 Simulator.app 无效 —— 那个偏好是 Simulator.app 读的。
PLIST="$HOME/Library/Preferences/com.apple.iphonesimulator.plist"
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false 2>/dev/null || true
plutil -insert "DevicePreferences" -json '{}' "$PLIST" 2>/dev/null || true
plutil -insert "DevicePreferences.$UDID" -json '{}' "$PLIST" 2>/dev/null || true
plutil -replace "DevicePreferences.$UDID.ConnectHardwareKeyboard" -bool NO "$PLIST" 2>/dev/null || true
# 软件键盘在"检测到硬件键盘"时会自动最小化,这一项把它关掉,作为第二道保险。
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl spawn "$UDID" defaults write com.apple.Preferences AutomaticMinimizationEnabled -bool false 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$UDID" 2>/dev/null || true

ARGS=()
if [ $# -gt 0 ]; then
  ARGS+=(-only-testing:"$1")
else
  ARGS+=(-only-testing:iOSExampleUITests)
fi

LOG=".build/uitest.log"
mkdir -p .build

set +e
xcodebuild test \
  -project SwiftyUI.xcodeproj \
  -scheme iOSExample \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath .build/xcode-uitest \
  ${ARGS[@]+"${ARGS[@]}"} > "$LOG" 2>&1
status=$?
set -e

grep -E "^(Test Case|Test Suite 'All tests'|/.*error:|\*\* TEST)" "$LOG" || true
if [ "$status" -ne 0 ]; then
  echo "--- UI 测试失败,完整日志见 $LOG,末尾 60 行: ---"
  tail -60 "$LOG"
fi
exit "$status"
