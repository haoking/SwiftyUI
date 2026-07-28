#!/usr/bin/env bash
# 断言 Scripts/uitest.sh 会把它改过的模拟器全局偏好原样还原。
#
# 为什么需要这条检查:uitest.sh 为了让软件键盘出现在屏幕内,必须关掉
# ~/Library/Preferences/com.apple.iphonesimulator.plist 里的 ConnectHardwareKeyboard。
# 那是 Simulator.app 的**本机全局设置**,对这台机器上所有项目生效 —— 一条测试命令
# 不该永久改掉使用者别处的开发环境。还原逻辑没人看得见,所以给它配一条会红的检查。
#
# 手法:先把本机真实状态存起来(退出时无条件还原),再人为构造两种"原状",
# 各跑一次 uitest.sh 的 dry run,断言跑完之后回到了构造出来的那个原状:
#
#   A. 键**本来不存在** → 跑完必须仍然不存在(而不是被写成 true 或 false)
#   B. 键本来是 true     → 跑完必须仍然是 true
#
# 判别力:把 uitest.sh 里的 `trap restore_simulator_prefs EXIT` 删掉,两个用例都会红
# (A 变成"多出一个 false",B 变成"true 被改成 false")。
#
# 这里的存档/还原代码**故意**不与 uitest.sh 共用实现:共用的话,被测逻辑自己出错
# 时检查的脚手架会跟着一起错,两边的错误互相抵消,检查就没有判别力了。
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST="$HOME/Library/Preferences/com.apple.iphonesimulator.plist"
ABSENT="__absent__"

# 必须与 uitest.sh 完全同一套解析规则(含 SWIFTYUI_SIMULATOR 钉子与回落,
# 完整理由见 uitest.sh 里的注释)—— 少一步,这里解析出的 UDID 就可能和
# uitest.sh 实际用的不是同一台,check 就会对着一台 run_dry 从未碰过的设备
# 验证,变成形式通过(vacuous pass):曾经两边都只是裸 tail -1 时看似一致,
# 其实只是本机库存的巧合,SWIFTYUI_SIMULATOR 一旦覆盖机型就会露馅。
PREFERRED_DEVICE="${SWIFTYUI_SIMULATOR:-iPhone 17}"
DEVICES="$(xcrun simctl list devices available)"

UDID="$(printf '%s\n' "$DEVICES" | awk -F'[()]' -v want="$PREFERRED_DEVICE" '
  { name=$1; gsub(/^ +/, "", name); gsub(/ +$/, "", name); if (name == want) print $2 }' | tail -1)"

if [ -z "$UDID" ]; then
  UDID="$(printf '%s\n' "$DEVICES" | awk -F'[()]' '/    iPhone/ {print $2}' | tail -1)"
fi

if [ -z "$UDID" ]; then
  echo "错误:找不到可用的 iPhone 模拟器" >&2
  exit 1
fi

DEVICE_NAME="$(printf '%s\n' "$DEVICES" | grep -F "$UDID" | head -1 | sed -E 's/^ *(.*) \([0-9A-F-]+\).*$/\1/')"
echo "使用模拟器:${DEVICE_NAME:-未知} ($UDID)"

read_global() {
  defaults read com.apple.iphonesimulator ConnectHardwareKeyboard 2>/dev/null || echo "$ABSENT"
}

read_device() {
  plutil -extract "DevicePreferences.$UDID.ConnectHardwareKeyboard" raw -o - "$PLIST" 2>/dev/null ||
    echo "$ABSENT"
}

clear_global() { defaults delete com.apple.iphonesimulator ConnectHardwareKeyboard 2>/dev/null || true; }
clear_device() { plutil -remove "DevicePreferences.$UDID.ConnectHardwareKeyboard" "$PLIST" 2>/dev/null || true; }

# ── 本机真实状态存档:无论后面怎么失败,退出时都还原 ─────────────────────
REAL_GLOBAL="$(read_global)"
case "$REAL_GLOBAL" in
  1 | true | YES) REAL_GLOBAL=true ;;
  0 | false | NO) REAL_GLOBAL=false ;;
esac
REAL_DEVPREFS_PRESENT=yes
plutil -extract "DevicePreferences" raw -o - "$PLIST" >/dev/null 2>&1 || REAL_DEVPREFS_PRESENT=no
REAL_DEVICE_PRESENT=yes
plutil -extract "DevicePreferences.$UDID" raw -o - "$PLIST" >/dev/null 2>&1 || REAL_DEVICE_PRESENT=no
REAL_DEVICE="$(read_device)"

restore_real_state() {
  local status=$?
  if [ "$REAL_GLOBAL" = "$ABSENT" ]; then
    clear_global
  else
    defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool "$REAL_GLOBAL" 2>/dev/null || true
  fi
  if [ "$REAL_DEVPREFS_PRESENT" = no ]; then
    plutil -remove "DevicePreferences" "$PLIST" 2>/dev/null || true
  elif [ "$REAL_DEVICE_PRESENT" = no ]; then
    plutil -remove "DevicePreferences.$UDID" "$PLIST" 2>/dev/null || true
  elif [ "$REAL_DEVICE" = "$ABSENT" ]; then
    clear_device
  else
    plutil -replace "DevicePreferences.$UDID.ConnectHardwareKeyboard" -bool "$REAL_DEVICE" "$PLIST" 2>/dev/null || true
  fi
  return "$status"
}
trap restore_real_state EXIT

failures=0
report() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $name"
  else
    echo "  ✗ $name:期望 [$expected],实得 [$actual]" >&2
    failures=$((failures + 1))
  fi
}

run_dry() {
  # dry run 只走"改偏好 → 退出时还原"这一段,不 boot 模拟器也不跑 xcodebuild。
  UITEST_DRY_RUN=1 Scripts/uitest.sh >/dev/null
}

echo "用例 A:键本来不存在,跑完必须仍然不存在"
clear_global
clear_device
run_dry
report "全局 ConnectHardwareKeyboard" "$ABSENT" "$(read_global)"
report "逐设备 ConnectHardwareKeyboard" "$ABSENT" "$(read_device)"

echo "用例 B:键本来是 true,跑完必须仍然是 true"
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool true
plutil -insert "DevicePreferences" -json '{}' "$PLIST" 2>/dev/null || true
plutil -insert "DevicePreferences.$UDID" -json '{}' "$PLIST" 2>/dev/null || true
plutil -replace "DevicePreferences.$UDID.ConnectHardwareKeyboard" -bool YES "$PLIST"
run_dry
report "全局 ConnectHardwareKeyboard" "1" "$(read_global)"
report "逐设备 ConnectHardwareKeyboard" "true" "$(read_device)"

if [ "$failures" -ne 0 ]; then
  echo "Scripts/uitest.sh 没有还原它改过的模拟器全局偏好($failures 项)" >&2
  exit 1
fi
echo "Scripts/uitest.sh 的模拟器偏好还原正常"
