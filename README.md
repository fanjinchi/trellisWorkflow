# Trellis Matt Workflow 模板

把 Trellis 的 Plan / Execute / Finish 流程与 Matt 的 spec-driven 工程流串起来的 `workflow.md` 模板，供多台电脑、多个项目复用。

## 目录

- `index.json` — Trellis marketplace 索引，声明一个 `type: "workflow"` 模板
- `workflows/matt/workflow.md` — 完整工作流（约 774 行，已在 Trellis 0.6.17 项目里通过解析器验证）

## 这份 workflow 做了什么

- **规划阶段整体交给 Matt**：`grill-with-docs`（在仓库里跑 `grilling` 面试，留下 `GLOSSARY.md` / ADR）→ `to-spec` 出 spec → `to-tickets` 拆 tracer-bullet 工单；Trellis 只保留任务生命周期与产物路径，`trellis-brainstorm` 已退出路由（其产物规则、收敛闸门并入 workflow 自身）
- **单一事实源**：每个事实（公式/阈值/配置键/契约/决策）只在一个产物里写全，其它处只写指针；AC 可复述字面值，散文不行；`file:line`、grep 输出、代码清单进 `research/` 或检查脚本，不进规划产物；任务目录就是 tracker，不再同时写 bd
- **父子 pointer 通道**：父任务持有跨 child 不变式，child 只写 `upstream contract: <parent>/design.md §n` 指针，不再复制父任务内容；`task.py create --parent` 会自动把 `## Upstream Contracts` 种进 child 的 `prd.md`；实现者与评审者的读取顺序都追加 `父任务 design/prd`
- **技能路由表**：workflow 自带「意图 → Matt skill」表（grill/spec/tickets/design/research/bug/triage/implement/tdd/review），并说明 `implement` 与 `implement-spec` 的分界；只有表里没有的才去 `ask-matt` 路由（它的完整地图里有本机未安装的 skill）
- **实施与审查**：Phase 2 用 Matt `implement` / `implement-spec` + `tdd`；`code-review` 做 Standards + Spec 双轴审查
- **收尾**：保留 Trellis 的 `trellis-update-spec` spec 回写与 Phase 3.4 commit 闸门

## 前置条件

1. **Trellis CLI**：本模板基于 0.6.17 编写。
2. **已初始化的项目**：`trellis init`，确保 `.trellis/scripts/`、Trellis bundled skills 与 agents 存在。
3. **Matt skills** 已安装（按平台放在 `~/.agents/skills/` 或等价目录）：

   ```bash
   npx skills add mattpocock/skills
   ```

   关键 skill：`grill-with-docs`（仓库内首选，驱动 `grilling` 面试原语）、`grill-me`（无仓库时）、`to-spec`、`to-tickets`、`implement`、`implement-spec`、`tdd`、`code-review`、`codebase-design`、`domain-modeling`、`diagnosing-bugs`、`prototype`、`research`、`triage`、`ask-matt`。
   首次使用建议在项目里跑一次 `setup-matt-pocock-skills`，配置 issue tracker、triage labels 和 domain docs。

> workflow 只按名字引用这些 skill，不打包它们。目标机器缺 skill 时，流程会退化成普通 Trellis 流程。


## marketplace 只分发 workflow.md

`trellis workflow --marketplace ... --template matt` 只写 `.trellis/workflow.md`（并把它从 `.template-hashes.json` 里移除，交给用户管理）。其它两处配套改动不在模板里，换机器时需要单独处理：

1. **`task.py create --parent` 自动种 `## Upstream Contracts`**：改了 `.trellis/scripts/common/task_store.py` 的 `_default_prd_content`，新增 `parent_name` 参数 → 在 child 的 `prd.md` 里种一节父任务指针。本项目的 `.trellis/scripts/` 与 trellis npm 包内模板 `dist/templates/trellis/scripts/common/task_store.py` 都已打上；新机器需要同样打一次（函数体见本节末尾）。
2. **`.dsh/` 等平台入口 skill**（`trellis-start` / `trellis-continue` / `DSH.md`）：里面已经写的是 `grill-with-docs` 路由，与 workflow 保持一致；如果平台文件来自旧版，需要一并刷新。

> 为什么不把指针种进 `implement.jsonl`：`curated_entry_count` 对任何带 `file` 的行计数，自动种一行等于白送一条 curated entry，会击穿 `task.py start` 的「零 spec 上下文」闸门。

## 安装

假设模板仓库是 `gh:fanjinchi/trellisWorkflow`：

```bash
# 1) 先看模板列表（可选）
trellis workflow --list --marketplace gh:fanjinchi/trellisWorkflow

# 2) 直接替换当前项目的 .trellis/workflow.md
trellis workflow --marketplace gh:fanjinchi/trellisWorkflow --template matt --force

# 3) 想先审阅再启用：写到 .trellis/workflow.md.new
trellis workflow --marketplace gh:fanjinchi/trellisWorkflow --template matt --create-new
```

### 备用安装（raw.githubusercontent 被墙或超时）

如果 `--list` / `--template` 报 `Could not reach registry index` 或超时，用 `gh` 直接取文件，效果等价：

```bash
gh api repos/fanjinchi/trellisWorkflow/contents/workflows/matt/workflow.md \
  -H 'Accept: application/vnd.github.raw' > .trellis/workflow.md
```

在已初始化的项目根目录执行；会覆盖现有 `.trellis/workflow.md`，建议先备份。

Trellis 0.7+ 支持把模板保存成项目内变体，按任务/开发者切换：

```bash
trellis workflow --save matt --marketplace gh:fanjinchi/trellisWorkflow
python3 ./.trellis/scripts/task.py workflow matt
```

> 0.6.17 的 `trellis workflow` 没有 `--save`，只能用上面的直接替换方式。

## 验证

```bash
python3 ./.trellis/scripts/get_context.py --mode phase
python3 ./.trellis/scripts/get_context.py --mode phase --step 1.1
python3 ./.trellis/scripts/get_context.py --mode phase --step 2.1
```

工作流必须保留这些解析标记：`## Phase Index`、`#### X.Y` 步骤标题、成对的 `[workflow-state:...]` 块。`get_context.py` 是最终判据。

## 更新与固定版本

- **改模板**：编辑 `workflows/matt/workflow.md`，在目标项目重跑安装命令（`--force`）。
- **固定版本**：`gh:fanjinchi/trellisWorkflow#v1`（分支或 tag 均可）。
- 目标项目本地改过的 `workflow.md` 不会被 `trellis update` 覆盖（非 native 模板会从 hash 清单移除）。

## 说明

- 模板不包含 `.trellis/spec/` 的项目规范；spec 是另一类模板（`trellis init --registry`）。需要的话可以在本仓库再加一个 `type: "spec"` 条目。
- 如果实际仓库名不是 `fanjinchi/trellisWorkflow`，把上面的 marketplace 源替换成 `gh:<owner>/<repo>` 即可。

## License

This template is a derivative of the Trellis workflow template
([mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis)), licensed under
AGPL-3.0-only. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
