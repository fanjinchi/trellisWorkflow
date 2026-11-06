#!/usr/bin/env bash
# 一键把当前项目初始化为「Matt × Trellis」workflow。
#
# 默认优先使用 install.sh 缓存的 workflow（离线）；--refresh 或自定义 --source 才联网。
#
# 用法：
#   trellis-matt-init                 # 用 git config user.name 作为开发者名
#   trellis-matt-init --user alice    # 显式指定 .trellis/.developer 的名字
#   trellis-matt-init --source gh:me/fork
#   trellis-matt-init --force         # 已有项目时强制切换 workflow
#   trellis-matt-init --refresh       # 忽略本地缓存，联网拉最新 workflow
#
# 做五件事：
#   1. 新项目：trellis init --dsh + matt workflow；已有项目：切换 workflow
#   2. 优先用本地缓存；没有缓存或 --refresh 时才走 marketplace / curl
#   3. 给 .trellis/scripts/common/task_store.py 打父子 pointer 补丁
#   4. 把 .dsh/skills/trellis-start 的 review 路由刷成 code-review
#   5. 验证 workflow 可被 get_context.py 解析，并打印下一步
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${TRELLIS_WORKFLOW_SOURCE:-gh:fanjinchi/trellisWorkflow}"
TEMPLATE="${TRELLIS_WORKFLOW_TEMPLATE:-matt}"
USER_NAME="${TRELLIS_USER:-}"
USER_GIVEN=0
SOURCE_GIVEN=0
FORCE=0
REFRESH=0
MARKER="Single-source rule (every planning artifact"
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
LOCAL_WORKFLOW="${TRELLIS_WORKFLOW_CACHE:-$DSH_HOME_DIR/scripts/trellis-workflow-matt.md}"
SOURCE_LABEL="$SOURCE"

say() { printf '%s\n' "$*"; }
warn() { printf '⚠  %s\n' "$*" >&2; }
die() { printf '✗  %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -u|--user)    [ $# -ge 2 ] || die "--user 需要一个名字"; USER_NAME="$2"; USER_GIVEN=1; shift 2 ;;
    -s|--source)  [ $# -ge 2 ] || die "--source 需要 gh:owner/repo"; SOURCE="$2"; SOURCE_GIVEN=1; shift 2 ;;
    -t|--template) [ $# -ge 2 ] || die "--template 需要一个模板 id"; TEMPLATE="$2"; shift 2 ;;
    -f|--force)   FORCE=1; shift ;;
    -r|--refresh) REFRESH=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) die "未知参数：$1（用 --help 查看用法）" ;;
  esac
done

command -v trellis >/dev/null 2>&1 || die "没有找到 trellis。先运行仓库里的 scripts/install.sh。"
command -v python3 >/dev/null 2>&1 || die "需要 python3（Trellis 脚本和补丁都依赖它）"
command -v curl >/dev/null 2>&1 || die "需要 curl（网络回退时用）"

# 统一在项目根目录执行：优先 git 根，否则当前目录。
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  cd "$(git rev-parse --show-toplevel)"
fi
PROJECT_ROOT="$(pwd)"

if [ -z "$USER_NAME" ]; then
  USER_NAME="$(git config user.name 2>/dev/null || true)"
fi
[ -n "$USER_NAME" ] || USER_NAME="${USER:-developer}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  warn "当前目录不是 git 仓库。workflow 的 Phase 3.4 要 commit，建议先 git init。"
fi
command -v dsh >/dev/null 2>&1 || warn "没有找到 dsh；项目仍会初始化，但 .dsh/ 入口技能要等 dsh 可用后才会用到。"

# gh:owner/repo[#ref] -> raw.githubusercontent.com/owner/repo/<ref>
RAW_BASE=""
case "$SOURCE" in
  gh:*|github:*)
    src="${SOURCE#gh:}"; src="${src#github:}"
    ref="main"
    case "$src" in
      *"#"*) ref="${src##*#}"; src="${src%%#*}" ;;
    esac
    RAW_BASE="https://raw.githubusercontent.com/$src/$ref"
    ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fetch_workflow_file() {
  [ -n "$RAW_BASE" ] || return 1
  local path="" index="$tmpdir/index.json"

  if curl -fsSL --retry 3 --retry-delay 2 --max-time 30 "$RAW_BASE/index.json" -o "$index" 2>/dev/null; then
    path="$(python3 - "$index" "$TEMPLATE" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
for item in data.get("templates", []):
    if item.get("id") == sys.argv[2] and item.get("type") == "workflow":
        print(item.get("path", ""))
        break
PY
)" || path=""
  fi

  [ -n "$path" ] || path="workflows/$TEMPLATE/workflow.md"

  say "→ 回退：直接下载 $RAW_BASE/$path"
  curl -fsSL --retry 3 --retry-delay 2 --max-time 60 "$RAW_BASE/$path" -o "$tmpdir/workflow.md" || return 1
  [ -s "$tmpdir/workflow.md" ] || return 1
}

install_workflow_file() {
  cp "$tmpdir/workflow.md" .trellis/workflow.md
  # 从 hash 清单移除，让 trellis update 不覆盖用户托管的 workflow。
  python3 - <<'PY'
import json
from pathlib import Path
p = Path(".trellis/.template-hashes.json")
if p.exists():
    data = json.loads(p.read_text(encoding="utf-8"))
    data.get("hashes", {}).pop(".trellis/workflow.md", None)
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

cache_workflow() {
  [ "$SOURCE_GIVEN" -eq 0 ] || return 0
  [ "$TEMPLATE" = "matt" ] || return 0
  [ -s .trellis/workflow.md ] || return 0
  mkdir -p "$(dirname "$LOCAL_WORKFLOW")" 2>/dev/null || return 0
  cp .trellis/workflow.md "$LOCAL_WORKFLOW" 2>/dev/null || true
}

use_local_workflow() {
  [ "$TEMPLATE" = "matt" ] || return 1
  [ -s "$LOCAL_WORKFLOW" ] || return 1
  cp "$LOCAL_WORKFLOW" "$tmpdir/workflow.md"
  install_workflow_file
  SOURCE_LABEL="本地缓存"
  say "→ 使用本地缓存 workflow：$LOCAL_WORKFLOW"
}

offline_init() {
  say "→ trellis init（离线，使用本地缓存）"
  trellis init --dsh --yes --user "$USER_NAME" </dev/null
  cp "$LOCAL_WORKFLOW" "$tmpdir/workflow.md"
  install_workflow_file
  SOURCE_LABEL="本地缓存"
}

verify_workflow() {
  [ -s .trellis/workflow.md ] || die "workflow.md 为空，初始化失败"
  if [ "$EXPECT_MATT" -eq 1 ] && [ "$TEMPLATE" = "matt" ] && ! grep -qF "$MARKER" .trellis/workflow.md; then
    die "workflow.md 不是 Matt 模板（缺少标记）。检查 --source / --template。"
  fi
  python3 .trellis/scripts/get_context.py --mode phase >/dev/null 2>&1 \
    || die "get_context.py 无法解析 workflow.md，模板可能损坏"
}

refresh_dsh_entry() {
  # 上游 dsh 模板的 trellis-start 快捷表仍把 review 指向已退休的 trellis-check。
  local f=".dsh/skills/trellis-start/SKILL.md"
  [ -f "$f" ] || return 0
  python3 - "$f" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
new = s.replace(
    "| Done coding / quality check | `trellis-check` |",
    "| Done coding / quality check | `code-review` |",
)
if new != s:
    p.write_text(new, encoding="utf-8")
PY
}

patch_task_store() {
  [ -f .trellis/scripts/common/task_store.py ] || return 0
  if [ -f "$SCRIPT_DIR/patch-task-store.py" ]; then
    python3 "$SCRIPT_DIR/patch-task-store.py" .trellis/scripts/common/task_store.py >/dev/null
  else
    warn "找不到 patch-task-store.py，跳过父子 pointer 补丁"
  fi
}

init_project() {
  if [ "$REFRESH" -eq 0 ] && [ "$SOURCE_GIVEN" -eq 0 ] && [ "$TEMPLATE" = "matt" ] && [ -s "$LOCAL_WORKFLOW" ]; then
    offline_init
    return 0
  fi

  local i ok=""
  for i in 1 2 3; do
    say "→ trellis init（第 $i/3 次，marketplace：$SOURCE）"
    if trellis init --dsh --yes --user "$USER_NAME" --workflow "$TEMPLATE" --workflow-source "$SOURCE" </dev/null; then
      if [ "$TEMPLATE" != "matt" ] || grep -qF "$MARKER" .trellis/workflow.md 2>/dev/null; then
        ok=1
        break
      fi
      warn "init 返回成功但 workflow 不是 Matt 版"
    fi
    warn "第 $i 次失败（常见原因：raw.githubusercontent 超时）"
    sleep 2
  done

  if [ -n "$ok" ]; then
    cache_workflow
    return 0
  fi

  warn "marketplace 连续失败，改用离线结构 + 直取 workflow.md"
  trellis init --dsh --yes --user "$USER_NAME" </dev/null
  if fetch_workflow_file; then
    install_workflow_file
    cache_workflow
    return 0
  fi
  if [ -s "$LOCAL_WORKFLOW" ]; then
    warn "网络不可用，改用本地缓存"
    cp "$LOCAL_WORKFLOW" "$tmpdir/workflow.md"
    install_workflow_file
    SOURCE_LABEL="本地缓存"
    return 0
  fi
  die "无法下载 workflow.md，也没有本地缓存。可先在有网的机器上跑 install.sh，或手动把 workflows/matt/workflow.md 放到 .trellis/workflow.md。"
}

switch_workflow() {
  if [ "$REFRESH" -eq 0 ] && [ "$SOURCE_GIVEN" -eq 0 ] && [ "$TEMPLATE" = "matt" ] && [ -s "$LOCAL_WORKFLOW" ]; then
    use_local_workflow
    return 0
  fi

  say "→ 切换 workflow 到 $TEMPLATE（marketplace：$SOURCE）"
  if trellis workflow --marketplace "$SOURCE" --template "$TEMPLATE" --force </dev/null; then
    if [ "$TEMPLATE" != "matt" ] || grep -qF "$MARKER" .trellis/workflow.md; then
      cache_workflow
      return 0
    fi
    warn "切换返回成功但内容不是 Matt 版"
  fi

  warn "marketplace 切换失败，改用直取 workflow.md"
  if fetch_workflow_file; then
    install_workflow_file
    cache_workflow
    return 0
  fi
  if [ -s "$LOCAL_WORKFLOW" ]; then
    warn "网络不可用，改用本地缓存"
    cp "$LOCAL_WORKFLOW" "$tmpdir/workflow.md"
    install_workflow_file
    SOURCE_LABEL="本地缓存"
    return 0
  fi
  die "无法下载 workflow.md，也没有本地缓存"
}

# 已有项目：身份首次初始化后不再变；--user 此时不生效，只提示。
if [ -f .trellis/.developer ]; then
  current_dev="$(sed -n 's/^name=//p' .trellis/.developer | head -n1)"
  if [ -n "$current_dev" ]; then
    if [ "$USER_GIVEN" -eq 1 ] && [ "$current_dev" != "$USER_NAME" ]; then
      warn "项目已有开发者身份 '$current_dev'；--user $USER_NAME 只在首次初始化生效。要换身份：删掉 .trellis/.developer 后重跑。"
    fi
    USER_NAME="$current_dev"
  fi
fi

say "项目：$PROJECT_ROOT"
say "开发者：$USER_NAME（首次初始化时由 --user 决定 .trellis/.developer 与 workspace 目录名）"

EXPECT_MATT=0
if [ -f .trellis/workflow.md ] && [ "$FORCE" -eq 0 ]; then
  say "→ 已有 workflow，保持不变（要强制切换加 --force）"
  if [ "$TEMPLATE" = "matt" ] && ! grep -qF "$MARKER" .trellis/workflow.md; then
    warn "当前 workflow 不是 Matt 版；保持原样。要切换请加 --force。"
  fi
else
  EXPECT_MATT=1
  if [ -f .trellis/workflow.md ]; then
    switch_workflow
  else
    init_project
  fi
fi

refresh_dsh_entry
patch_task_store
verify_workflow

say ""
say "✅ 初始化完成"
say "   .trellis/workflow.md  → $TEMPLATE（来源：$SOURCE_LABEL）"
say "   .trellis/.developer   → $USER_NAME"
say "   下一步：在这个目录启动 dsh；新会话会按全局规则先加载 trellis-start。"
say "   提示：换团队/换机器时每人用自己的 --user，别共用同一个开发者目录。"
