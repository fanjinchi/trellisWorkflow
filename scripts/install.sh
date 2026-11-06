#!/usr/bin/env bash
# 在新电脑上安装「Matt × Trellis for DSH」环境。
#
# 做这些事：
#   1. 检查/安装 Trellis CLI（默认 0.6.17）
#   2. 下载 Matt skills → ~/.agents/skills
#   3. 给 DSH 生成模型可见副本 → ~/.dsh/skills（去掉 disable-model-invocation）
#   4. 安装全局规则 → ~/.dsh/AGENTS.md（已有文件会先备份）
#   5. 安装初始化宏与本地 workflow 缓存 → ~/.dsh/scripts/ 与 ~/.local/bin/trellis-matt-init
#   6. 安装 dsh 技能 → ~/.dsh/skills/trellis-matt-init
#   7. 给 Trellis 的 task_store.py 模板打父子 pointer 补丁
#
# 幂等，可重复执行。用法：
#   bash scripts/install.sh
#   TRELLIS_VERSION=0.6.17 bash scripts/install.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
TRELLIS_VERSION="${TRELLIS_VERSION:-0.6.17}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

export DSH_HOME AGENTS_HOME

say() { printf '%s\n' "$*"; }
warn() { printf '⚠  %s\n' "$*" >&2; }
die() { printf '✗  %s\n' "$*" >&2; exit 1; }
step() { printf '\n== %s ==\n' "$*"; }

command -v git >/dev/null 2>&1 || die "需要 git"
command -v curl >/dev/null 2>&1 || die "需要 curl"
command -v node >/dev/null 2>&1 || die "需要 Node.js"
command -v npm >/dev/null 2>&1 || die "需要 npm"
command -v python3 >/dev/null 2>&1 || die "需要 python3"

version_ge() {
  # 只处理 x.y.z 数字版本；Trellis 的 --version 输出就是这种。
  [ "$(python3 -c 'import sys; k=lambda v: tuple(int(x) for x in v.split(".")); print(1 if k(sys.argv[1]) >= k(sys.argv[2]) else 0)' "$1" "$2")" = "1" ]
}

step "1/7 Trellis CLI"
if command -v trellis >/dev/null 2>&1; then
  current="$(trellis --version 2>/dev/null | tail -n1 | tr -d '[:space:]')"
  if version_ge "$current" "$TRELLIS_VERSION"; then
    if [ "$current" = "$TRELLIS_VERSION" ]; then
      say "✅ trellis $current"
    else
      warn "trellis $current 高于测试版本 $TRELLIS_VERSION；本仓库的补丁按 $TRELLIS_VERSION 编写，继续但可能不兼容"
    fi
  else
    say "→ 升级 trellis $current → $TRELLIS_VERSION"
    npm install -g "@mindfoldhq/trellis@$TRELLIS_VERSION" || die "npm 全局安装失败（检查 npm 全局目录权限）"
  fi
else
  say "→ 安装 trellis $TRELLIS_VERSION"
  npm install -g "@mindfoldhq/trellis@$TRELLIS_VERSION" || die "npm 全局安装失败（检查 npm 全局目录权限）"
fi
command -v trellis >/dev/null 2>&1 || die "trellis 安装后仍不在 PATH；把 npm 全局 bin 加进 PATH 后重试"

step "2/7 Matt skills"
bash "$REPO_DIR/scripts/sync-matt-skills.sh"

step "3/7 全局规则 ~/.dsh/AGENTS.md"
mkdir -p "$DSH_HOME"
if [ -f "$DSH_HOME/AGENTS.md" ] && ! cmp -s "$REPO_DIR/dsh/AGENTS.md" "$DSH_HOME/AGENTS.md"; then
  backup="$DSH_HOME/AGENTS.md.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$DSH_HOME/AGENTS.md" "$backup"
  say "已备份原有全局规则 → $backup"
fi
cp "$REPO_DIR/dsh/AGENTS.md" "$DSH_HOME/AGENTS.md"
say "✅ $DSH_HOME/AGENTS.md"

step "4/7 初始化宏与辅助脚本"
mkdir -p "$DSH_HOME/scripts"
cp "$REPO_DIR/scripts/trellis-matt-init.sh" "$DSH_HOME/scripts/"
cp "$REPO_DIR/scripts/sync-matt-skills.sh" "$DSH_HOME/scripts/"
cp "$REPO_DIR/scripts/patch-task-store.py" "$DSH_HOME/scripts/"
cp "$REPO_DIR/workflows/matt/workflow.md" "$DSH_HOME/scripts/trellis-workflow-matt.md"
chmod +x "$DSH_HOME/scripts/trellis-matt-init.sh" "$DSH_HOME/scripts/sync-matt-skills.sh" "$DSH_HOME/scripts/patch-task-store.py"
mkdir -p "$BIN_DIR"
ln -sf "$DSH_HOME/scripts/trellis-matt-init.sh" "$BIN_DIR/trellis-matt-init"
say "✅ $DSH_HOME/scripts/trellis-matt-init.sh"
say "✅ $BIN_DIR/trellis-matt-init"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR 不在 PATH；直接用完整路径 $BIN_DIR/trellis-matt-init，或把该目录加进 PATH" ;;
esac

step "5/7 dsh 技能 trellis-matt-init"
mkdir -p "$DSH_HOME/skills/trellis-matt-init"
cp "$REPO_DIR/dsh/skills/trellis-matt-init/SKILL.md" "$DSH_HOME/skills/trellis-matt-init/SKILL.md"
say "✅ $DSH_HOME/skills/trellis-matt-init/SKILL.md"

step "6/7 Trellis 模板补丁（父子 pointer）"
trellis_bin="$(command -v trellis)"
trellis_real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$trellis_bin")"
pkg_root="$(dirname "$(dirname "$trellis_real")")"
task_store="$pkg_root/dist/templates/trellis/scripts/common/task_store.py"
if [ -f "$task_store" ]; then
  if python3 "$REPO_DIR/scripts/patch-task-store.py" "$task_store"; then
    say "✅ 模板已打补丁：$task_store"
  else
    warn "模板补丁失败：$task_store（不影响已有项目，但之后 trellis init 的 child 任务不会自动种父指针）"
  fi
else
  warn "找不到 $task_store"
fi

step "7/7 验证"
fail=0
trellis --version >/dev/null 2>&1 || { warn "trellis 不可用"; fail=1; }
bash "$REPO_DIR/scripts/sync-matt-skills.sh" --check >/dev/null 2>&1 || { warn "Matt skills 不齐"; fail=1; }
[ -f "$DSH_HOME/AGENTS.md" ] || { warn "缺少 $DSH_HOME/AGENTS.md"; fail=1; }
[ -x "$BIN_DIR/trellis-matt-init" ] || { warn "缺少 $BIN_DIR/trellis-matt-init"; fail=1; }
[ -f "$DSH_HOME/skills/trellis-matt-init/SKILL.md" ] || { warn "缺少 dsh 技能 trellis-matt-init"; fail=1; }
[ -s "$DSH_HOME/scripts/trellis-workflow-matt.md" ] || { warn "缺少本地 workflow 缓存"; fail=1; }
if [ -f "$task_store" ]; then
  python3 "$REPO_DIR/scripts/patch-task-store.py" --check "$task_store" >/dev/null 2>&1 || { warn "trellis 模板未打补丁"; fail=1; }
fi

if [ "$fail" -ne 0 ]; then
  die "安装未全部通过，按上面的 ⚠ 逐项处理"
fi

say ""
say "✅ 环境安装完成"
say ""
say "下一步："
say "  1. 初始化具体项目：cd <项目根> && trellis-matt-init --user <你的名字>"
say "  2. 或在 dsh 里直接说：「用我的 workflow 初始化这个项目」"
say "  3. 新项目默认指向 gh:fanjinchi/trellisWorkflow；换 fork 用 --source gh:owner/repo"
say "  4. 更新 Matt skills：bash $DSH_HOME/scripts/sync-matt-skills.sh"
