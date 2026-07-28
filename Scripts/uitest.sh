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
#
# 环境变量:
#   UITEST_DRY_RUN=1   只走"改模拟器偏好 → 退出时还原"这一段,不 boot 模拟器、
#                      不启动 Simulator.app、不跑 xcodebuild。供
#                      Scripts/check-uitest-restore.sh 验证还原逻辑用。
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
#
# **这是本机全局设置,不是本项目的设置。**
# ~/Library/Preferences/com.apple.iphonesimulator.plist 归 Simulator.app 所有,
# 对这台机器上的每一个项目生效。改了不还原,等于本仓库的一条测试命令永久改掉了
# 使用者别处的开发环境(跑过一次之后,任何项目的模拟器都不再连接硬件键盘)。
# 所以下面先把原值存起来,再用 trap 在退出时还原 —— 包括 Ctrl-C 中断、
# xcodebuild 失败、以及 set -e 触发的提前退出。
#
# 注意"原值"包含**这个键本来就不存在**这一种。那种情况必须还原成"不存在",
# 而不是写一个 true 进去:缺省与显式 true 未必等价,而且给使用者的 plist 留下
# 一个本来没有的键,本身就是没还原干净。
PLIST="$HOME/Library/Preferences/com.apple.iphonesimulator.plist"
ABSENT="__swiftyui_absent__"

# 全局键的原值。键不存在时 defaults read 退出码非 0。
#
# 注意 defaults 读写两侧的表示法**不一样**:read 对 bool 打印 0/1,而
# `write -bool` 只认 true|false|yes|no —— 把读到的 0/1 直接回写会静默失败
# (报个用法说明就走了,退出码非 0,被 `|| true` 吞掉),原值就丢了。
# 所以这里读到就归一化成 true/false 再存。
ORIG_GLOBAL="$(defaults read com.apple.iphonesimulator ConnectHardwareKeyboard 2>/dev/null || echo "$ABSENT")"
case "$ORIG_GLOBAL" in
  1 | true | YES) ORIG_GLOBAL=true ;;
  0 | false | NO) ORIG_GLOBAL=false ;;
esac
# 逐设备键的原值。分三层记录,因为脚本可能要**新建**中间那两层字典;
# 只还原叶子键会留下我们凭空造出来的空字典。
ORIG_DEVPREFS_PRESENT=yes
plutil -extract "DevicePreferences" raw -o - "$PLIST" >/dev/null 2>&1 || ORIG_DEVPREFS_PRESENT=no
ORIG_DEVICE_PRESENT=yes
plutil -extract "DevicePreferences.$UDID" raw -o - "$PLIST" >/dev/null 2>&1 || ORIG_DEVICE_PRESENT=no
ORIG_DEVICE="$(plutil -extract "DevicePreferences.$UDID.ConnectHardwareKeyboard" raw -o - "$PLIST" 2>/dev/null || echo "$ABSENT")"

restore_simulator_prefs() {
  local status=$?
  if [ "$ORIG_GLOBAL" = "$ABSENT" ]; then
    defaults delete com.apple.iphonesimulator ConnectHardwareKeyboard 2>/dev/null || true
  else
    defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool "$ORIG_GLOBAL" 2>/dev/null || true
  fi

  # 从最外层往里判断:哪一层是我们建的,就整层删掉。
  if [ "$ORIG_DEVPREFS_PRESENT" = no ]; then
    plutil -remove "DevicePreferences" "$PLIST" 2>/dev/null || true
  elif [ "$ORIG_DEVICE_PRESENT" = no ]; then
    plutil -remove "DevicePreferences.$UDID" "$PLIST" 2>/dev/null || true
  elif [ "$ORIG_DEVICE" = "$ABSENT" ]; then
    plutil -remove "DevicePreferences.$UDID.ConnectHardwareKeyboard" "$PLIST" 2>/dev/null || true
  else
    plutil -replace "DevicePreferences.$UDID.ConnectHardwareKeyboard" \
      -bool "$ORIG_DEVICE" "$PLIST" 2>/dev/null || true
  fi
  return "$status"
}
trap restore_simulator_prefs EXIT

defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false 2>/dev/null || true
plutil -insert "DevicePreferences" -json '{}' "$PLIST" 2>/dev/null || true
plutil -insert "DevicePreferences.$UDID" -json '{}' "$PLIST" 2>/dev/null || true
plutil -replace "DevicePreferences.$UDID.ConnectHardwareKeyboard" -bool NO "$PLIST" 2>/dev/null || true

# 还原逻辑的自检入口:偏好已改、trap 已挂,这里退出就会立刻走还原路径。
# Scripts/check-uitest-restore.sh 用它来断言"跑完之后 plist 与跑之前逐字节一致"。
if [ "${UITEST_DRY_RUN:-}" = "1" ]; then
  echo "UITEST_DRY_RUN=1:已改偏好并挂上还原 trap,跳过模拟器与 xcodebuild"
  exit 0
fi

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
