# 给 Agent 的部署指引：Matt × Trellis for DSH

> 你（Agent）拿到的任务：在一台**新电脑**上复刻用户的 DSH + Trellis + Matt 工作流环境，然后教会用户怎么用。
> 用户只需要做两件事：把仓库放到本机、告诉你「按 `AGENT-SETUP.md` 部署」。其余步骤你来做，并用大白话汇报。

---

## 0. 先确认这些前提

| 项目 | 要求 |
| --- | --- |
| 系统 | Linux 或 macOS，有 `bash`、`git`、`curl`、`python3` |
| Node.js | ≥ 20，`npm` 可全局安装（不要用 sudo 装整个脚本；npm 全局目录要当前用户可写） |
| 网络 | 能访问 github.com、raw.githubusercontent.com、registry.npmjs.org |
| DSH | 已安装 `dsh`（`~/.dsh` 存在） |

如果缺 Node 或 dsh，先停下来告诉用户缺什么，不要自行安装系统级组件。

---

## 1. 取仓库

```bash
git clone https://github.com/fanjinchi/trellisWorkflow ~/code/trellisWorkflow
cd ~/code/trellisWorkflow
```

如果用户已经克隆过，直接进入该目录并 `git pull`。

---

## 2. 一条命令装机器级环境

```bash
bash scripts/install.sh
```

它会做 7 件事（幂等，可重复跑）：

1. 检查/安装 Trellis CLI `0.6.17`（本仓库的补丁按这个版本验证）
2. 把 Matt skills 下载到 `~/.agents/skills`
3. 把工作流需要的 12 个 Matt 技能复制到 `~/.dsh/skills`，并去掉 `disable-model-invocation: true`——DSH 会隐藏带这行的技能，去掉后模型才能自动调用
4. 安装全局规则到 `~/.dsh/AGENTS.md`；已有文件会先备份成 `AGENTS.md.bak.<时间>`
5. 安装初始化宏：`~/.dsh/scripts/trellis-matt-init.sh` 和 `~/.local/bin/trellis-matt-init`
6. 安装 dsh 技能 `~/.dsh/skills/trellis-matt-init`（用户说一句话就能触发项目初始化）
7. 给 Trellis 的 `task_store.py` 模板打父子 pointer 补丁（让 `task.py create --parent` 自动给 child 的 `prd.md` 种 `## Upstream Contracts`）

**如果第 7 步提示权限失败**：说明 npm 全局目录不可写，让用户处理 npm 全局权限后重跑；不要用 sudo 跑整个脚本。

---

## 3. 验证（逐条跑，把结果贴给用户）

```bash
trellis --version                                   # 期望：0.6.17
bash ~/.dsh/scripts/sync-matt-skills.sh --check      # 期望：✅ Matt skills 与 dsh 副本齐全
test -f ~/.dsh/AGENTS.md && echo AGENTS_OK           # 期望：AGENTS_OK
test -x ~/.local/bin/trellis-matt-init && echo MACRO_OK  # 期望：MACRO_OK
grep -c "disable-model-invocation" ~/.dsh/skills/implement/SKILL.md  # 期望：0
```

以上任何一条不符合预期，先用 `bash scripts/install.sh` 重跑一次；仍失败再按第 6 节排查。

---

## 4. 初始化一个项目

在**项目根目录**（有 `.git` 的目录）执行：

```bash
trellis-matt-init --user <开发者的名字>
```

- `--user` 决定 `.trellis/.developer` 和 `.trellis/workspace/<名字>/`。**一定要提醒用户显式设置**；不传时宏会退回 `git config user.name`，再退回系统用户名。
- `--user` 只在**首次初始化**生效：已有 `.trellis/.developer` 的项目，宏会保留原身份并提示；确实要换身份就先删 `.trellis/.developer` 再重跑（旧 workspace 目录保留）。
- 默认 workflow 来源是 `gh:fanjinchi/trellisWorkflow`（用户自己的仓库）。换 fork 用 `--source gh:owner/repo`。
- 已有 `.trellis/` 的项目默认保持原 workflow；确认要切换成 matt 才加 `--force`。
- 新项目会执行 `trellis init --dsh`，只装 dsh 平台文件。

验证这几件事：

```bash
grep -c "Single-source rule (every planning artifact" .trellis/workflow.md   # 期望：1
python3 .trellis/scripts/get_context.py --mode phase | head -3               # 期望：## Phase Index
grep -c "parent_name" .trellis/scripts/common/task_store.py                  # 期望：≥1
grep -c "trellis-check" .dsh/skills/trellis-start/SKILL.md                    # 期望：0（review 已指向 code-review）
cat .trellis/.developer                                                       # 期望：name=<你传的名字>
```

---

## 5. 告诉用户怎么用（照着说，别展开）

装好之后，用户的日常只有三句话：

1. **新项目接入**：在项目里说「初始化这个项目」，或终端跑 `trellis-matt-init --user <名字>`。
2. **开始干活**：在项目里开 dsh，说「用 trellis-start 开始」——DSH 没有 session hook，全局规则已经约定：进入有 `.trellis/` 的项目先加载 `trellis-start`。之后按 Matt 流程走：需求拷问 → spec → tickets → 实现/TDD → review → 收尾。
3. **换电脑**：重复本文件第 1～2 节；每个项目重新跑一次第 4 节。

---

## 6. 关键事实（用户问起时这样解释）

### 为什么 DSH 每次新会话都要手动碰 `trellis-start`？

Trellis 0.6.17（npm 最新版）把 dsh 定义为 **class-2 pull 型平台**：它只往项目里写 `.dsh/skills/`、`.agents/skills/` 和 `.dsh/DSH.md`，**不写 session hook**。所以没有「会话启动自动注入 workflow 上下文」这回事。

本仓库的补偿方式：在 `~/.dsh/AGENTS.md` 里加了一条全局规则——进入含 `.trellis/` 的项目，每个新会话先加载 `trellis-start`。效果等价于别的平台的 SessionStart hook，代价是一次技能加载。

### 为什么 Matt 技能要复制一份到 `~/.dsh/skills`？

DSH 解析技能 frontmatter，`disable-model-invocation: true` 会让技能**对模型隐藏**；Matt 上游有 12 个工作流技能带这行。DSH 的用户技能根优先级是 `~/.dsh/skills`（rank 400）高于 `~/.agents/skills`（rank 500），所以在 `~/.dsh/skills` 放一份去掉该行的副本，模型就能自动调用。上游更新后重跑 `sync-matt-skills.sh`。

### `--user` 是什么？

Trellis 的开发者身份，不是系统账号。它决定 `.trellis/.developer` 和 `.trellis/workspace/<名字>/`；团队里每人用自己的名字，别共用。

### 网络失败怎么办？

初始化宏默认走 marketplace（`trellis init --workflow matt --workflow-source ...`），Trellis 对 registry index 只有 5 秒超时，raw.githubusercontent 慢时很容易失败。宏会自动重试 3 次；仍失败就退回「`trellis init` 原生结构 + curl 直取 `workflow.md` + 从 hash 清单移除该文件」。所以只要最终 curl 能拿到文件，初始化就能成功。

### 为什么有 `patch-task-store.py`？

Trellis 0.6.17 上游的 `task.py create --parent` 不会给 child 的 `prd.md` 种父任务指针；本 workflow 的「父子 pointer 通道」依赖这一节。补丁幂等，装机器时打 npm 模板，初始化项目时再对项目文件打一次。

---

## 7. 故障排查

| 现象 | 处理 |
| --- | --- |
| `trellis: command not found` | npm 全局 bin 不在 PATH；找到 `npm prefix -g` 下的 `bin` 加进 PATH，或 `export PATH="$(npm prefix -g)/bin:$PATH"` |
| `Could not fetch workflow template index` | 宏会自动回退；若回退也失败，用 `gh api repos/fanjinchi/trellisWorkflow/contents/workflows/matt/workflow.md -H 'Accept: application/vnd.github.raw' > .trellis/workflow.md`，再删掉 `.trellis/.template-hashes.json` 里的 `.trellis/workflow.md` 键 |
| npm 全局安装 EACCES | 修 npm prefix 权限或改用用户级 prefix；不要 sudo 跑整个脚本 |
| 已有 `~/.dsh/AGENTS.md` 被覆盖 | 用脚本打印的 `AGENTS.md.bak.<时间>` 恢复；确认要合并再手工编辑 |
| 初始化后 dsh 不加载 `trellis-start` | 确认 `~/.dsh/AGENTS.md` 含「DSH × Trellis 入口」一节；确认项目根有 `.trellis/` |
| 模型看不到某个 Matt 技能 | 看它是否在 `~/.dsh/skills` 且 SKILL.md 里没有 `disable-model-invocation: true`；重跑 `sync-matt-skills.sh` |

---

## 8. 边界

- 只动环境与项目里的 `.trellis/`、`.dsh/`；不要改用户业务代码。
- 不要 commit / push。
- 不安装 Claude Code / Kimi / Pi 等其它平台的文件；本仓库只服务 dsh。
- 用户没明确要求时不要升级 Trellis 大版本；0.6.17 是当前验证版本。
