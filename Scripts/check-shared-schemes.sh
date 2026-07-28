#!/usr/bin/env bash
# 断言脚本与 CI 依赖的 scheme 都是**共享**的,而不是靠 xcodebuild 自动生成。
#
# 背景:`Scripts/uitest.sh` 与 CI 的"构建示例工程"都写 `-scheme iOSExample`,
# 但很长一段时间里 xcshareddata 只跟踪了 SwiftyUI.xcscheme,iOSExample 那个
# 是 xcodebuild 现场自动生成的(xcuserdata/ 在 gitignore 里,全新检出没有它)。
# 全新检出下确实能跑通,但那是**未声明**的依赖:自动生成出来的 scheme 内容是
# 隐式的(测试动作包含哪些 target、用哪个 build configuration),会随 Xcode
# 版本漂移,而且一旦哪台机器/哪个 runner 上关掉了自动生成就直接找不到 scheme。
#
# 手法:把 .xcodeproj 复制到临时目录,在副本里写一份把**所有** native target 的
# 自动生成都关掉的 xcuserdata,再问 xcodebuild 有哪些 scheme。此时能列出来的
# 只可能来自 xcshareddata。全程在副本上做,一个字节都不碰使用者真实的 Xcode 状态。
#
# 判别力(已实测):删掉 xcshareddata/xcschemes/iOSExample.xcscheme,本检查立刻
# 变红(只剩 SwiftyUI)。
#
# **它抓不到什么**:scheme 文件在、但内容是坏的。实测把根元素改成 <NotAScheme>,
# `xcodebuild -list` 照样把它列出来 —— 那个命令只看文件名,不解析内容。
# 所以本检查锁的是"这个 scheme 已共享、且不靠自动生成",不是"这个 scheme 是对的"。
# 后者由 Scripts/uitest.sh 真跑一遍 UI 测试来保证,那是更强也更贴题的信号。
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="SwiftyUI.xcodeproj"

# 这两个是脚本与 CI 真正会用 `-scheme` 点名的:
#   SwiftyUI    —— podspec / 框架构建
#   iOSExample  —— Scripts/uitest.sh、CI 的"构建示例工程"
REQUIRED_SCHEMES="SwiftyUI iOSExample"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -R "$PROJECT" "$WORK/"
COPY="$WORK/$PROJECT"
rm -rf "$COPY/xcuserdata"

# 从 pbxproj 里读出所有 PBXNativeTarget 的 UUID —— 不硬编码,新增 target 时自动跟上。
# 声明形如:
#   0C2D75D31F877D9900596281 /* iOSExample */ = {
#       isa = PBXNativeTarget;
TARGET_UUIDS="$(
  awk '/isa = PBXNativeTarget;/ { print prev } { prev = $0 }' "$PROJECT/project.pbxproj" |
    awk '{print $1}' | grep -E '^[0-9A-Fa-f]{24}$' | sort -u
)"
if [ -z "$TARGET_UUIDS" ]; then
  echo "错误:没能从 $PROJECT/project.pbxproj 里解析出任何 PBXNativeTarget" >&2
  exit 1
fi

USER_DIR="$COPY/xcuserdata/$(whoami).xcuserdatad/xcschemes"
mkdir -p "$USER_DIR"
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  echo '<plist version="1.0"><dict><key>SuppressBuildableAutocreation</key><dict>'
  for uuid in $TARGET_UUIDS; do
    echo "<key>$uuid</key><dict><key>primary</key><true/></dict>"
  done
  echo '</dict></dict></plist>'
} >"$USER_DIR/xcschememanagement.plist"

FOUND="$(
  xcodebuild -list -project "$COPY" 2>/dev/null |
    awk '/^[[:space:]]*Schemes:/ { inlist = 1; next } inlist && NF { print $1 }'
)"

failures=0
for scheme in $REQUIRED_SCHEMES; do
  if printf '%s\n' $FOUND | grep -qxF "$scheme"; then
    echo "  ✓ $scheme 是共享 scheme"
  else
    echo "  ✗ $scheme 不是共享 scheme —— 关掉自动生成之后就找不到它了" >&2
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  echo >&2
  echo "把它加进版本控制:$PROJECT/xcshareddata/xcschemes/<名字>.xcscheme" >&2
  echo "(Xcode 里 Product > Scheme > Manage Schemes,勾上 Shared)" >&2
  exit 1
fi
echo "脚本与 CI 依赖的 scheme 全部已共享"
