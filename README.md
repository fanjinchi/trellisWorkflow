# Trellis Matt Workflow 模板

把 Trellis 的 Plan / Execute / Finish 流程与 Matt 的 spec-driven 工程流串起来的 `workflow.md` 模板，供多台电脑、多个项目复用。

## 目录

- `index.json` — Trellis marketplace 索引，声明一个 `type: "workflow"` 模板
- `workflows/matt/workflow.md` — 完整工作流（约 738 行，已在 Trellis 0.6.17 项目里通过解析器验证）

## 这份 workflow 做了什么

- **Phase 1 规划前先 grill**：加载 `grill-me` / `grilling`，把需求、范围、验收标准、关键决策谈拢后才建任务、写 `prd.md`
- **spec 沉淀**：用 `to-spec` 把已谈拢的对话整理成 spec（`prd.md`；复杂任务再补 `design.md` / `implement.md`）
- **ticket graph**：用 `to-tickets` 拆 tracer-bullet 工单，子任务之间写明 blocking edges，按 frontier 顺序实施
- **实施与审查**：Phase 2 用 Matt `implement` / `implement-spec` + `tdd`；`code-review` 做 Standards + Spec 双轴审查
- **收尾**：保留 Trellis 的 `trellis-update-spec` spec 回写与 Phase 3.4 commit 闸门

## 前置条件

1. **Trellis CLI**：本模板基于 0.6.17 编写。
2. **已初始化的项目**：`trellis init`，确保 `.trellis/scripts/`、Trellis bundled skills 与 agents 存在。
3. **Matt skills** 已安装（按平台放在 `~/.agents/skills/` 或等价目录）：

   ```bash
   npx skills add mattpocock/skills
   ```

   关键 skill：`grill-me` / `grilling`、`to-spec`、`to-tickets`、`implement`、`implement-spec`、`tdd`、`code-review`、`diagnosing-bugs`、`prototype`、`research`。
   首次使用建议在项目里跑一次 `setup-matt-pocock-skills`，配置 issue tracker、triage labels 和 domain docs。

> workflow 只按名字引用这些 skill，不打包它们。目标机器缺 skill 时，流程会退化成普通 Trellis 流程。

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
