#!/usr/bin/env bash
# 下载 Matt skills，并给 DSH 生成“模型可调用”的副本。
#
# 为什么需要副本：DSH 尊重 frontmatter 的 `disable-model-invocation: true`
# （带该行的技能不会进入模型可见的技能目录）；而 `~/.dsh/skills` 的用户技能
# 根优先级高于共享的 `~/.agents/skills`。所以要让 Matt 技能能被模型自动调用，
# 只能把工作流用到的、带该标记的技能复制一份到 `~/.dsh/skills` 并去掉该行。
#
# 上游更新后重跑本脚本即可；幂等。
#
# 用法：
#   sync-matt-skills.sh          # 下载/更新并同步
#   sync-matt-skills.sh --check  # 只检查现状，不联网、不写入
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
MATT_REPO="${MATT_REPO:-https://github.com/mattpocock/skills.git}"
MATT_REF="${MATT_REF:-main}"

# workflow.md 的路由表 + 它依赖/收尾会用到的 Matt skills。
MATT_SKILLS=(
  ask-matt
  codebase-design
  code-review
  diagnosing-bugs
  domain-modeling
  grill-me
  grill-with-docs
  grilling
  handoff
  implement
  implement-spec
  improve-codebase-architecture
  pr
  prototype
  research
  retro
  setup-matt-pocock-skills
  tdd
  to-spec
  to-tickets
  triage
  wayfinder
  writing-for-agents
)

# 上游带 disable-model-invocation、需要复制到 dsh 用户技能根的技能。
DSH_VISIBLE=(
  ask-matt
  grill-me
  grill-with-docs
  handoff
  implement
  implement-spec
  improve-codebase-architecture
  retro
  to-spec
  to-tickets
  triage
  wayfinder
)

say() { printf '%s\n' "$*"; }
warn() { printf '⚠  %s\n' "$*" >&2; }
die() { printf '✗  %s\n' "$*" >&2; exit 1; }

strip_flag() {
  local file="$1" tmp
  tmp="$(mktemp)"
  grep -v -E '^disable-model-invocation:[[:space:]]*true[[:space:]]*$' "$file" >"$tmp" || true
  mv "$tmp" "$file"
}

check_state() {
  local missing=0 flagged=0 name
  for name in "${MATT_SKILLS[@]}"; do
    if [ ! -f "$AGENTS_HOME/skills/$name/SKILL.md" ]; then
      warn "缺少 $AGENTS_HOME/skills/$name"
      missing=1
    fi
  done
  for name in "${DSH_VISIBLE[@]}"; do
    if [ ! -f "$DSH_HOME/skills/$name/SKILL.md" ]; then
      warn "缺少 $DSH_HOME/skills/$name"
      missing=1
    elif grep -qE '^disable-model-invocation:[[:space:]]*true[[:space:]]*$' "$DSH_HOME/skills/$name/SKILL.md"; then
      warn "$DSH_HOME/skills/$name 仍带 disable-model-invocation，模型会看不到"
      flagged=1
    fi
  done
  if [ "$missing" -eq 0 ] && [ "$flagged" -eq 0 ]; then
    say "✅ Matt skills 与 dsh 副本齐全"
    return 0
  fi
  return 1
}

if [ "${1:-}" = "--check" ]; then
  check_state
  exit $?
fi

command -v git >/dev/null 2>&1 || die "需要 git"
mkdir -p "$AGENTS_HOME/skills" "$DSH_HOME/skills"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

say "→ 下载 Matt skills（$MATT_REF）..."
if ! git clone --depth 1 --branch "$MATT_REF" "$MATT_REPO" "$tmpdir/matt" >/dev/null 2>&1; then
  die "git clone 失败：$MATT_REPO。检查网络/代理后重试。"
fi

copied=0
for name in "${MATT_SKILLS[@]}"; do
  src="$(find "$tmpdir/matt/skills" -type f -path "*/$name/SKILL.md" -print -quit 2>/dev/null || true)"
  if [ -z "$src" ]; then
    warn "上游没有找到技能 $name（跳过）"
    continue
  fi
  dst="$AGENTS_HOME/skills/$name"
  rm -rf "$dst"
  cp -a "$(dirname "$src")" "$dst"
  copied=$((copied + 1))
done
say "✅ 已安装 $copied 个 Matt skills → $AGENTS_HOME/skills"

for name in "${DSH_VISIBLE[@]}"; do
  src="$AGENTS_HOME/skills/$name"
  if [ ! -f "$src/SKILL.md" ]; then
    warn "$name 未安装，无法生成 dsh 副本"
    continue
  fi
  rm -rf "$DSH_HOME/skills/$name"
  cp -a "$src" "$DSH_HOME/skills/$name"
  strip_flag "$DSH_HOME/skills/$name/SKILL.md"
done
say "✅ 已生成 ${#DSH_VISIBLE[@]} 个 dsh 模型可见副本 → $DSH_HOME/skills"

check_state
