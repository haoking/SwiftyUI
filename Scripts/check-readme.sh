#!/usr/bin/env bash
# 把 README.md 里的每一段 Swift 代码块抽出来,单独编译一遍。
#
# 为什么需要这条检查:README 与源码已经漂移过两次。第 3 轮专门修了一批"与源码
# 不符的事实性内容",第 4 轮复审又在同一份文件里找出六处新的事实错误 ——
# 包括引用了根本不存在的协议名、引用了 private 类型、以及一段直接复制会报
# `cannot find 'SimpleError' in scope` 的代码。第 3 轮其实**做过**一次校验,
# 但那个校验文件用完就删了,于是没有任何常设机制阻止再漂移一次。
# 这个脚本就是那个常设机制。
#
# 编译语境(这是这条检查的"合同",改它等于改对 README 示例的要求):
#
#   每段代码块放进一个**独立的** UIViewController 子类方法里编译。
#   于是 `self` 与 `view` 由 UIKit 提供 —— README 的示例本来就是按"写在一个
#   view controller 里"的语境写的。除此之外**没有任何**额外符号:
#
#   - 块与块之间不共享任何声明。第 3 段用第 2 段定义的变量,编译不过。
#   - 只 import UIKit 与 SwiftyUI。示例引用了 SwiftyUI 之外的东西,编译不过 ——
#     `SimpleError` 那处缺陷正是这么漏掉的:第 3 轮的校验环境里恰好有它,
#     但**印在 README 上的那段不是自足的**,读者复制过去就会报错。
#
# 有意不自足的代码块,在 ``` 围栏**上一行**写一条明确的排除标记:
#
#   <!-- readme-check: skip 这里写不检查的理由 -->
#
# 脚本会把跳过的段数打出来,所以"全部跳过"这种退化不会悄悄发生。
#
# 用法:
#   Scripts/check-readme.sh
set -euo pipefail
cd "$(dirname "$0")/.."

README="README.md"
OUT_DIR=".build/readme-check"
GENERATED="$OUT_DIR/ReadmeExamples.swift"
PRODUCTS=".build/xcode/Build/Products/Debug-iphonesimulator"

mkdir -p "$OUT_DIR"

# 需要编译好的 SwiftyUI.swiftmodule 才能做类型检查。
if [ ! -d "$PRODUCTS/SwiftyUI.swiftmodule" ]; then
  echo "未找到 $PRODUCTS/SwiftyUI.swiftmodule,先跑一次 Scripts/build.sh …"
  Scripts/build.sh >/dev/null
fi

# ── 抽取 ────────────────────────────────────────────────────────────────
# 逐行扫描,记住上一行(用于识别排除标记)。代码块里的 `import` 行要摘掉:
# 它们在 README 里是对的(示例要告诉读者 import 什么),但不能出现在函数体内,
# 生成文件在头部统一 import 一次。
awk -v out="$GENERATED" '
function flush_block() {
  printf("\n/// README.md:%d-%d\n", start_line, NR) > out
  printf("private final class ReadmeBlock%d: UIViewController {\n", kept) > out
  printf("  func check() {\n") > out
  for (i = 1; i <= n; i++) printf("%s\n", body[i]) > out
  printf("  }\n}\n") > out
  n = 0
}
BEGIN {
  print "// 本文件由 Scripts/check-readme.sh 从 README.md 自动生成,请勿手工编辑,也不要提交。" > out
  print "// 每段代码块一个独立类型:块之间不共享任何声明,只有 UIKit 与 SwiftyUI 在作用域内。" > out
  print "" > out
  print "import Foundation" > out
  print "import SwiftyUI" > out
  print "import UIKit" > out
  total = 0; kept = 0; skipped = 0; inblock = 0; n = 0
}
/^```swift[[:space:]]*$/ && inblock == 0 {
  total++
  start_line = NR
  if (prev ~ /<!--[[:space:]]*readme-check:[[:space:]]*skip/) {
    skipping = 1; skipped++
    printf("跳过 README.md:%d 的代码块 —— %s\n", NR, prev)
  } else {
    skipping = 0; kept++
  }
  inblock = 1
  prev = $0
  next
}
/^```[[:space:]]*$/ && inblock == 1 {
  if (!skipping) flush_block()
  inblock = 0
  prev = $0
  next
}
inblock == 1 {
  if (!skipping && $0 !~ /^import[[:space:]]/) body[++n] = "    " $0
  next
}
{ if ($0 !~ /^[[:space:]]*$/) prev = $0 }
END {
  printf("README.md 里共 %d 段 Swift 代码块:检查 %d 段,跳过 %d 段\n", total, kept, skipped)
  if (kept == 0) {
    print "错误:没有任何代码块被检查" > "/dev/stderr"
    exit 1
  }
}
' "$README"

# ── 编译 ────────────────────────────────────────────────────────────────
# 只做类型检查,不生成产物 —— 要验的是"这段代码能不能编译",不是能不能运行。
# 目标三元组与语言模式必须与 Package.swift 一致(iOS 18 / Swift 6),
# 否则检查过了、使用者那边照样编译不过。
#
# -suppress-warnings:生成文件里的 "unused variable" 是**包装手法的产物**
# (README 里 `let redFloat = myColor.redValue` 本来就是拿来说明返回类型的),
# 不是 README 的缺陷。这条检查只判 error。
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
LOG="$OUT_DIR/compile.log"

set +e
xcrun swiftc \
  -typecheck \
  -swift-version 6 \
  -target arm64-apple-ios18.0-simulator \
  -sdk "$SDK" \
  -I "$PRODUCTS" \
  -suppress-warnings \
  "$GENERATED" >"$LOG" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "README 的 Swift 代码块编译失败:" >&2
  echo >&2
  cat "$LOG" >&2
  echo >&2
  echo "生成的文件在 $GENERATED,每个类型上方注明了它对应 README.md 的哪几行。" >&2
  exit 1
fi

echo "README 的 Swift 代码块全部编译通过"

# ── 第二段:正文里点名的类型,必须真的存在、而且是 public ──────────────
#
# 编译检查够不到正文(prose)。而已经出现过的两次事实错误里,有两处正好在正文里:
#
#   - "the `ImageCache` protocol" —— 协议真名是 `ImageCacheable`,`ImageCache`
#     根本不存在。这与第 3 轮修掉的 `ThreadPool`(真名 `SwiftyThreadPool`)
#     是同一类错误,已经咬了两次。
#   - "`SwiftyToastCenter.default`" —— 这个类型是 private,使用者根本没法
#     写出这个名字。存在 ≠ 可用,所以这里只认 public 声明。
#
# 手法:把正文里每一段反引号内容的**开头标识符**抽出来(限首字母大写),
# 要求它要么是 Sources 里的一个 public 类型声明,要么在下面这份显式外部白名单里。
# 取开头标识符而不是整段,是为了让 `SwiftyToastCenter.default`、`UIImage.load(_:)`、
# `Promise<T>` 这些带成员/参数/泛型的写法都归到它们的类型上 ——
# 上面第二条缺陷正是 `Type.member` 形状,只认裸名字会漏掉。
# 白名单要手工维护,这是有意的:多一个陌生名字就该有人看一眼,
# 而不是让检查悄悄放过。
EXTERNAL_ALLOWLIST="
AnyObject
Date
MainActor
NSObject
Operation
OperationQueue
Sendable
Task
UIColor
UIControl
UIImage
UIImageView
UIResponder
UIView
UIWindow
"
# 不是类型:T 是 `Promise<T>` 里的泛型参数,另两个是文件名。
EXTERNAL_ALLOWLIST="$EXTERNAL_ALLOWLIST
T
Package
Podfile
"

PUBLIC_TYPES="$(
  grep -hoE '\bpublic( +(final|indirect))* +(class|struct|enum|protocol|actor|typealias) +[A-Za-z_][A-Za-z0-9_]*' \
    Sources/*.swift | awk '{print $NF}' | sort -u
)"

KNOWN="$(printf '%s\n%s\n' "$PUBLIC_TYPES" "$EXTERNAL_ALLOWLIST" | grep -v '^[[:space:]]*$' | sort -u)"

# 正文 = README 去掉所有围栏代码块之后的部分。
UNKNOWN="$(
  awk '/^```/ { inb = !inb; next } !inb' "$README" |
    grep -oE '`[A-Z][A-Za-z0-9_]*[^`]*`' |
    sed -E 's/^`([A-Z][A-Za-z0-9_]*).*/\1/' | sort -u |
    grep -vxF "$KNOWN" || true
)"

if [ -n "$UNKNOWN" ]; then
  echo >&2
  echo "README 正文里点名了这些类型,但它们既不是 Sources 里的 public 声明,也不在外部白名单里:" >&2
  printf '  %s\n' $UNKNOWN >&2
  echo >&2
  echo "要么名字写错了(比如 ImageCache → ImageCacheable),要么它不是 public" >&2
  echo "(使用者写不出这个名字),要么它确实是个外部类型 —— 那就把它加进" >&2
  echo "Scripts/check-readme.sh 的 EXTERNAL_ALLOWLIST,让这次放行是一个有人看过的决定。" >&2
  exit 1
fi

echo "README 正文里点名的类型全部存在且 public"
