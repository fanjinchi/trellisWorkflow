[English](./README.en.md) | 简体中文

# Trellis Matt Workflow 模板

在Linux do论坛大佬的启发下配置的个人工作流，抄了大佬的部分设置https://linux.do/t/topic/2635801原贴在这里。workflow是让大肥鱼帮忙改的，把部分Matt Skill本来只能手动触发的改成了模型可发现以便适配工作流。本人是个软件白痴因此在使用中发现问题和修改的会比较慢，之后再发现有什么痛点再改了。workflow其实改了pi，kimicode，dsh三个的部分，但是给兄弟用的所以只让ai总结了一个dsh的部署方案。不过如果你想用的话其他agent的思路应该不会有多大区别，ai应该能分析的明白的。打包的包含了我个人在用的全局规则如果你只想用workflow那就只改下Matt Skill然后初始化的时候--workflow matt --workflow-source gh:fanjinchi/trellisWorkflow带上这个参数应该就好了

把 Trellis 的 Plan / Execute / Finish 流程与 Matt 的 spec-driven 工程流串起来的一套可复用环境：`workflow.md` 模板 + 机器级安装脚本 + 项目级初始化宏。面向 **DeepSeek Harness (dsh)**。

- 新电脑部署：交给 dsh 的 Agent 读 [AGENT-SETUP.md](./AGENT-SETUP.md)，或自己跑 `bash scripts/install.sh`
- 单个项目接入：`trellis-matt-init --user <你的名字>`
- 工作流本体：`workflows/matt/workflow.md`

## 最快路径（新电脑）

```bash
git clone https://github.com/fanjinchi/trellisWorkflow ~/code/trellisWorkflow
bash ~/code/trellisWorkflow/scripts/install.sh
```

然后在任意项目根目录：

```bash
trellis-matt-init --user <你的名字>
```

就这两条。之后在该项目里启动 dsh，说「用 trellis-start 开始」。

> 更省事：把下面这句话交给新电脑上的 dsh ——
> 「克隆 https://github.com/fanjinchi/trellisWorkflow，读 AGENT-SETUP.md，按里面的步骤把环境装好并向用户汇报。」

## 目录

- `AGENT-SETUP.md` — 给 Agent 的部署指引（步骤、验证、故障排查）
- `dsh/AGENTS.md` — 全局规则，安装到 `~/.dsh/AGENTS.md`
- `dsh/skills/trellis-matt-init/SKILL.md` — dsh 技能，用户说「初始化这个项目」时触发
- `scripts/install.sh` — 机器级安装（Trellis、Matt skills、dsh 副本、全局规则、宏、模板补丁）
- `scripts/trellis-matt-init.sh` — 项目级一键初始化宏
- `scripts/sync-matt-skills.sh` — 下载/更新 Matt skills 并生成 dsh 模型可见副本
- `scripts/patch-task-store.py` — 给 Trellis 的 `task_store.py` 打父子 pointer 补丁
- `index.json` — Trellis marketplace 索引，声明一个 `type: "workflow"` 模板
- `workflows/matt/workflow.md` — 完整工作流（已在 Trellis 0.6.17 项目里通过解析器验证）

## 这份 workflow 做了什么

- **规划阶段整体交给 Matt**：`grill-with-docs`（在仓库里跑 `grilling` 面试，留下 `GLOSSARY.md` / ADR）→ `to-spec` 出 spec → `to-tickets` 拆 tracer-bullet 工单；Trellis 只保留任务生命周期与产物路径
- **单一事实源**：每个事实（公式/阈值/配置键/契约/决策）只在一个产物里写全，其它处只写指针；AC 可复述字面值，散文不行；`file:line`、grep 输出、代码清单进 `research/` 或检查脚本，不进规划产物；任务目录就是 tracker，不再同时写 bd
- **父子 pointer 通道**：父任务持有跨 child 不变式，child 只写 `upstream contract: <parent>/design.md §n` 指针；补丁后 `task.py create --parent` 会自动把 `## Upstream Contracts` 种进 child 的 `prd.md`
- **技能路由表**：workflow 自带「意图 → Matt skill」表；只有表里没有的才去 `ask-matt` 路由
- **实施与审查**：Phase 2 用 Matt `implement` / `implement-spec` + `tdd`；`code-review` 做 Standards + Spec 双轴审查
- **收尾**：保留 Trellis 的 `trellis-update-spec` spec 回写与 Phase 3.4 commit 闸门

## dsh 上没有 session hook（0.6.17 仍然如此）

Trellis 把 dsh 定义为 **class-2 pull 型平台**：只写 `.dsh/skills/`、`.agents/skills/` 和 `.dsh/DSH.md`，**不写 session hook**。所以每个新会话不会自动注入 workflow 状态，需要加载 `trellis-start` 技能。npm 最新版仍是 0.6.17（2026-11 核对），上游 main 的后续提交也没有加 dsh hook。

本仓库的替代方案：`dsh/AGENTS.md` 里加了一条全局规则——进入含 `.trellis/` 的项目，每个新会话先加载 `trellis-start`。效果等价于 SessionStart hook，成本是一次技能加载。

## 安装细节

### 前置条件

1. **Trellis CLI 0.6.17**（npm 最新版；更高版本未验证）
2. **dsh** 已安装，`~/.dsh` 存在
3. **Node.js ≥ 20**、`git`、`curl`、`python3`
4. 能访问 GitHub / npm（raw.githubusercontent 慢也能用，宏会回退）

### `install.sh` 具体做了什么

1. 安装/校验 `@mindfoldhq/trellis@0.6.17`
2. `git clone` Matt skills → `~/.agents/skills`（只装 workflow 用到的 23 个）
3. 复制其中 12 个带 `disable-model-invocation: true` 的技能到 `~/.dsh/skills` 并去掉该行（DSH 会隐藏带这行的技能）
4. 安装 `~/.dsh/AGENTS.md`（已有文件先备份为 `AGENTS.md.bak.<时间>`）
5. 安装 `~/.dsh/scripts/` 与 `~/.local/bin/trellis-matt-init`
6. 安装 dsh 技能 `~/.dsh/skills/trellis-matt-init`
7. 给 npm 包内的 `task_store.py` 模板打父子 pointer 补丁

### 宏的默认值与回退

```bash
trellis-matt-init --user alice
# 等价于：
trellis init --dsh --yes --user alice \
  --workflow matt --workflow-source gh:fanjinchi/trellisWorkflow
```

- `--user`：开发者身份，写入 `.trellis/.developer` 并决定 `.trellis/workspace/<名字>/`。**建议显式设置**；不传时退回 `git config user.name`。只在首次初始化生效，已有 `.trellis/.developer` 的项目不会被覆盖。
- `--source gh:owner/repo`：换 fork。
- `--force`：已有 `.trellis/` 时强制切换 workflow。
- 网络失败：宏重试 3 次 → 退回 `trellis init` 原生结构 + `curl` 直取 `workflow.md` + 从 `.template-hashes.json` 移除该文件（防止 `trellis update` 覆盖）。
- 宏还会顺手把 `.dsh/skills/trellis-start` 快捷表里的 review 路由从上游遗留的 `trellis-check` 刷成 `code-review`，与 workflow 保持一致。

### 手动初始化（不用宏）

```bash
trellis init --dsh -u <名字> --workflow matt --workflow-source gh:fanjinchi/trellisWorkflow
python3 ~/.dsh/scripts/patch-task-store.py .trellis/scripts/common/task_store.py
```

### 只用 marketplace 分发 workflow（旧方式）

```bash
trellis workflow --marketplace gh:fanjinchi/trellisWorkflow --template matt --force
```

只写 `.trellis/workflow.md`。**其余配套改动**（dsh 技能副本、`task_store.py` 补丁、全局规则）现在由 `install.sh` / 宏负责，不需要再手工处理。

## 验证

```bash
# 机器级
trellis --version
bash ~/.dsh/scripts/sync-matt-skills.sh --check

# 项目级（在项目根目录）
grep -c "Single-source rule (every planning artifact" .trellis/workflow.md   # 1
python3 .trellis/scripts/get_context.py --mode phase | head -3               # ## Phase Index
grep -c "parent_name" .trellis/scripts/common/task_store.py                  # ≥1
grep -c "trellis-check" .dsh/skills/trellis-start/SKILL.md                    # 0
```

workflow 必须保留这些解析标记：`## Phase Index`、`#### X.Y` 步骤标题、成对的 `[workflow-state:...]` 块。`get_context.py` 是最终判据。

## 更新与固定版本

- **改 workflow 模板**：编辑 `workflows/matt/workflow.md`，提交后重跑项目的 `trellis workflow --marketplace ... --force` 或 `trellis-matt-init --force`。
- **更新 Matt skills**：`bash ~/.dsh/scripts/sync-matt-skills.sh`。
- **固定版本**：`gh:fanjinchi/trellisWorkflow#v1`（分支或 tag 均可）。
- Trellis 升级后：重跑 `install.sh` 重新打模板补丁；若 `trellis update` 覆盖了项目里的 `task_store.py`，重跑 `patch-task-store.py`。

## 说明

- 模板不包含 `.trellis/spec/` 的项目规范；spec 是另一类模板（`trellis init --registry`）。
- 如果实际仓库名不是 `fanjinchi/trellisWorkflow`，把 `--source` 和 README 里的地址替换成 `gh:<owner>/<repo>`。
- 上游 main 的 `task_store.py` 没有父子 pointer 逻辑，本仓库的补丁是必要的；上游若以后内置，`patch-task-store.py` 会检测到并跳过。

## License

This template is a derivative of the Trellis workflow template
([mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis)), licensed under
AGPL-3.0-only. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
