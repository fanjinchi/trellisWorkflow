---
name: trellis-matt-init
description: 一键把当前项目初始化为 Matt × Trellis workflow（trellis init --dsh + matt 模板 + 父子 pointer 补丁），并检查 Matt skills 与 DSH 副本是否就绪。用户说“初始化这个项目”“用我的 workflow 初始化”“接入 trellis”时使用。
---

# Matt × Trellis 项目初始化

目标：让当前项目带上 `.trellis/`（matt workflow）、父子 pointer 补丁，并确认 Matt skills 与 DSH 入口技能就绪。

## 步骤

1. 确认在项目根目录（有 `.git` 或 `package.json` 等）。不是 git 仓库时提醒用户 workflow 的 Phase 3.4 需要 commit，但**不要擅自 `git init`**。
2. 检查工具：`command -v trellis`、`test -x ~/.dsh/scripts/trellis-matt-init.sh`。缺任何一个就告诉用户先运行 workflow 仓库里的 `scripts/install.sh`，不要手搓替代步骤。
3. 确定开发者名：
   - 用户本轮给过名字就用；
   - 否则用 `git config user.name`；
   - 都没有就问一次。这个名字会写入 `.trellis/.developer` 并决定 `.trellis/workspace/<name>/`，以后改要迁移。
4. 运行初始化宏：

   ```bash
   ~/.dsh/scripts/trellis-matt-init.sh --user "<名字>"
   ```

   Windows：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\.dsh\scripts\trellis-matt-init.ps1" -User "<名字>"
   ```

   已有 `.trellis/` 且用户确认要换成 matt 时加 `--force`（Windows：`-Force`）。默认来源是 `gh:fanjinchi/trellisWorkflow`，需要换 fork 时加 `--source gh:owner/repo`（Windows：`-Source`）。默认用本地缓存、不联网；要拉最新加 `--refresh`（Windows：`-Refresh`）。
5. 按输出逐项验证：
   - `.trellis/workflow.md` 含 `Single-source rule (every planning artifact`
   - `python3 .trellis/scripts/get_context.py --mode phase` 能输出 Phase Index
   - `.trellis/scripts/common/task_store.py` 的 `_default_prd_content` 带 `parent_name`
6. 用大白话向用户汇报：初始化了哪个项目、workflow 指向哪个仓库、项目里第一句话该怎么说。

## 边界

- 不要改业务代码，只动 `.trellis/` 和 `.dsh/`。
- 不要 commit / push。
- 网络失败时宏会自己重试并回退到 curl；仍失败就把错误原文交给用户，不要无休止重试。
- 用户没要求时不要顺手升级 trellis。
