# 给 Agent 的部署指引：Matt × Trellis for DSH

> 你（Agent）拿到的任务：在一台**新电脑**上复刻用户的 DSH + Trellis + Matt 工作流环境，然后教会用户怎么用。
> 用户只需要做两件事：把仓库放到本机、告诉你「按 `AGENT-SETUP.md` 部署」。其余步骤你来做，并用大白话汇报。

---

## 0. 先搞清楚「宏」是什么

DSH 没有用户自定义斜杠命令的目录（命令只能由插件注册），所以这里的「宏」不是 `/trellis-matt-init`，而是两个入口：

| 入口 | 怎么用 | 适合谁 |
| --- | --- | --- |
| 终端命令 | `trellis-matt-init --user <名字>`（Windows：`trellis-matt-init.cmd -User <名字>`） | 喜欢自己敲命令的用户 |
| dsh 技能 | 在项目里对 dsh 说「初始化这个项目」「用我的 workflow 初始化」 | 不想记命令的用户 |

两者跑的是同一套逻辑：初始化 `.trellis/`、写入 matt workflow、打父子 pointer 补丁、刷新 dsh 入口技能。

---

## 1. 先确认这些前提

| 项目 | 要求 |
| --- | --- |
| 系统 | Linux / macOS / Windows 10+ |
| Shell | Linux/macOS：`bash`；Windows：PowerShell 5.1+（系统自带）。PowerShell 被策略禁用时，`.cmd` 会自动改用 Node 跑同一套步骤 |
| Node.js | ≥ 20，`npm` 可全局安装（不要用 sudo 装整个脚本；npm 全局目录要当前用户可写） |
| 其它命令 | `git`、`curl`（Windows 用 PowerShell 自带网络请求，不强制 curl）、`python3` / `python` |
| 网络 | 能访问 github.com、raw.githubusercontent.com、registry.npmjs.org |
| DSH | 已安装 `dsh`（`~/.dsh` 或 `%USERPROFILE%\.dsh` 存在） |

如果缺 Node 或 dsh，先停下来告诉用户缺什么，不要自行安装系统级组件。

---

## 2. 一条命令装机器级环境

### Linux / macOS

```bash
git clone https://github.com/fanjinchi/trellisWorkflow ~/code/trellisWorkflow
cd ~/code/trellisWorkflow
bash scripts/install.sh
```

### Windows

```powershell
git clone https://github.com/fanjinchi/trellisWorkflow $HOME\code\trellisWorkflow
cd $HOME\code\trellisWorkflow
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1
```

也可以直接双击 `scripts\install.cmd`。

**PowerShell 被安全策略挡住时**（`running scripts is disabled`、AppLocker、Constrained Language Mode），`.cmd` 会先试 PowerShell，失败后自动改用 Node 跑同一套步骤（`scripts\win-fallback.mjs`；Node 是 Trellis 的依赖，一定在）。想强制走 Node：

```bat
set TRELLIS_NO_POWERSHELL=1
scripts\install.cmd
```

它会做 7 件事（幂等，可重复跑）：

1. 检查/安装 Trellis CLI `0.6.17`（本仓库的补丁按这个版本验证）
2. 把 Matt skills 下载到 `~/.agents/skills`（Windows：`%USERPROFILE%\.agents\skills`）
3. 把工作流需要的 12 个 Matt 技能复制到 `~/.dsh/skills`，并去掉 `disable-model-invocation: true`——DSH 会隐藏带这行的技能，去掉后模型才能自动调用
4. 安装全局规则到 `~/.dsh/AGENTS.md`；已有文件会先备份成 `AGENTS.md.bak.<时间>`
5. 安装初始化宏：`~/.dsh/scripts/trellis-matt-init.sh`（Windows：`.ps1` + `.cmd`）和 `~/.local/bin/trellis-matt-init`
6. 安装 dsh 技能 `~/.dsh/skills/trellis-matt-init`（用户说一句话就能触发项目初始化）
7. 给 Trellis 的 `task_store.py` 模板打父子 pointer 补丁（让 `task.py create --parent` 自动给 child 的 `prd.md` 种 `## Upstream Contracts`）

**同时会把 `workflows/matt/workflow.md` 缓存到 `~/.dsh/scripts/trellis-workflow-matt.md`。** 之后初始化项目默认用这份本地缓存，**不需要再连 GitHub**；只有加 `--refresh`（Windows：`-Refresh`）或自定义 `--source` 才联网。

**如果第 7 步提示权限失败**：说明 npm 全局目录不可写，让用户处理 npm 全局权限后重跑；不要用 sudo 跑整个脚本。

---

## 3. 验证（逐条跑，把结果贴给用户）

### Linux / macOS

```bash
trellis --version                                   # 期望：0.6.17
bash ~/.dsh/scripts/sync-matt-skills.sh --check      # 期望：✅ Matt skills 与 dsh 副本齐全
test -f ~/.dsh/AGENTS.md && echo AGENTS_OK           # 期望：AGENTS_OK
test -x ~/.local/bin/trellis-matt-init && echo MACRO_OK  # 期望：MACRO_OK
test -s ~/.dsh/scripts/trellis-workflow-matt.md && echo CACHE_OK  # 期望：CACHE_OK
grep -c "disable-model-invocation" ~/.dsh/skills/implement/SKILL.md  # 期望：0
```

### Windows

```powershell
trellis --version
powershell -NoProfile -ExecutionPolicy Bypass -File $HOME\.dsh\scripts\sync-matt-skills.ps1 -Check
Test-Path $HOME\.dsh\AGENTS.md
Test-Path $HOME\.local\bin\trellis-matt-init.cmd
Test-Path $HOME\.dsh\scripts\trellis-workflow-matt.md
Select-String -Path $HOME\.dsh\skills\implement\SKILL.md -Pattern "disable-model-invocation" -Quiet  # 期望：False
```

以上任何一条不符合预期，先用第 2 节重跑一次；仍失败再按第 6/7 节手工做。

---

## 4. 初始化一个项目

在**项目根目录**（有 `.git` 的目录）执行：

### Linux / macOS

```bash
trellis-matt-init --user <开发者的名字>
```

### Windows

```powershell
trellis-matt-init.cmd -User <开发者的名字>
```

- `--user` / `-User` 决定 `.trellis/.developer` 和 `.trellis/workspace/<名字>/`。**一定要提醒用户显式设置**；不传时宏会退回 `git config user.name`，再退回系统用户名。
- `--user` 只在**首次初始化**生效：已有 `.trellis/.developer` 的项目，宏会保留原身份并提示；确实要换身份就先删 `.trellis/.developer` 再重跑（旧 workspace 目录保留）。
- 默认 workflow 来源是 `gh:fanjinchi/trellisWorkflow`（用户自己的仓库）。换 fork 用 `--source gh:owner/repo`（Windows：`-Source`）。
- **默认用本地缓存，不联网。** 想拉最新 workflow 加 `--refresh`（Windows：`-Refresh`）。
- 已有 `.trellis/` 的项目默认保持原 workflow；确认要切换成 matt 才加 `--force`（Windows：`-Force`）。
- 新项目会执行 `trellis init --dsh`，只装 dsh 平台文件。

验证这几件事：

```bash
grep -c "Single-source rule (every planning artifact" .trellis/workflow.md   # 期望：1
python3 .trellis/scripts/get_context.py --mode phase | head -3               # 期望：## Phase Index
grep -c "parent_name" .trellis/scripts/common/task_store.py                  # 期望：≥1
grep -c "trellis-check" .dsh/skills/trellis-start/SKILL.md                    # 期望：0（review 已指向 code-review）
cat .trellis/.developer                                                       # 期望：name=<你传的名字>
```

Windows 把 `python3` 换成 `python`，`grep -c` 换成 `Select-String ... -Quiet` 即可。

---

## 5. 告诉用户怎么用（照着说，别展开）

装好之后，用户的日常只有三句话：

1. **新项目接入**：在项目里说「初始化这个项目」，或终端跑 `trellis-matt-init --user <名字>`（Windows：`trellis-matt-init.cmd -User <名字>`）。
2. **开始干活**：在项目里开 dsh，说「用 trellis-start 开始」——DSH 没有 session hook，全局规则已经约定：进入有 `.trellis/` 的项目先加载 `trellis-start`。之后按 Matt 流程走：需求拷问 → spec → tickets → 实现/TDD → review → 收尾。
3. **换电脑**：重复本文件第 1～2 节；每个项目重新跑一次第 4 节。

---

## 6. 脚本失败时：Linux / macOS 手工一步步做

> 目标：即使 `install.sh` 或宏完全跑不起来，你也能按下面的顺序把环境装完。每一步都有验证命令，做完一步再下一步。
> 以下命令默认在**仓库根目录**执行；6.7 会 `cd` 到项目根目录。

### 6.1 安装 Trellis

```bash
npm install -g @mindfoldhq/trellis@0.6.17
trellis --version
```

期望输出 `0.6.17`。如果 `trellis` 不在 PATH，把 `npm prefix -g` 下的 `bin` 加进 PATH。

### 6.2 下载 Matt skills 到 `~/.agents/skills`

```bash
tmp="$(mktemp -d)"
git clone --depth 1 https://github.com/mattpocock/skills "$tmp/matt"
mkdir -p ~/.agents/skills
for name in ask-matt codebase-design code-review diagnosing-bugs domain-modeling \
  grill-me grill-with-docs grilling handoff implement implement-spec \
  improve-codebase-architecture pr prototype research retro setup-matt-pocock-skills \
  tdd to-spec to-tickets triage wayfinder writing-for-agents; do
  src="$(find "$tmp/matt/skills" -type f -path "*/$name/SKILL.md" -print -quit)"
  if [ -n "$src" ]; then
    rm -rf ~/.agents/skills/$name
    cp -a "$(dirname "$src")" ~/.agents/skills/$name
  else
    echo "缺少 $name"
  fi
done
ls ~/.agents/skills | wc -l   # 期望：23
```

如果 `git clone` 失败：换代理/镜像，或下载 zip：

```bash
curl -L -o /tmp/matt.zip https://github.com/mattpocock/skills/archive/refs/heads/main.zip
unzip -q /tmp/matt.zip -d /tmp/matt-src
# 之后把上面的 "$tmp/matt/skills" 换成 /tmp/matt-src/skills-main/skills
```

### 6.3 生成 dsh 模型可见副本

```bash
mkdir -p ~/.dsh/skills
for name in ask-matt grill-me grill-with-docs handoff implement implement-spec \
  improve-codebase-architecture retro to-spec to-tickets triage wayfinder; do
  rm -rf ~/.dsh/skills/$name
  cp -a ~/.agents/skills/$name ~/.dsh/skills/$name
  python3 - "$HOME/.dsh/skills/$name/SKILL.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8").splitlines()
kept = [l for l in lines if not l.strip().startswith("disable-model-invocation:")]
p.write_text("\n".join(kept) + "\n", encoding="utf-8")
PY
done
grep -c "disable-model-invocation" ~/.dsh/skills/implement/SKILL.md   # 期望：0
```

### 6.4 安装全局规则

```bash
mkdir -p ~/.dsh
[ -f ~/.dsh/AGENTS.md ] && cp ~/.dsh/AGENTS.md ~/.dsh/AGENTS.md.bak.$(date +%Y%m%d-%H%M%S)
cp dsh/AGENTS.md ~/.dsh/AGENTS.md
grep -q "DSH × Trellis 入口" ~/.dsh/AGENTS.md && echo AGENTS_OK
```

### 6.5 安装宏、辅助脚本、dsh 技能

```bash
mkdir -p ~/.dsh/scripts ~/.local/bin ~/.dsh/skills/trellis-matt-init
cp scripts/trellis-matt-init.sh scripts/sync-matt-skills.sh scripts/patch-task-store.py ~/.dsh/scripts/
cp workflows/matt/workflow.md ~/.dsh/scripts/trellis-workflow-matt.md
chmod +x ~/.dsh/scripts/trellis-matt-init.sh ~/.dsh/scripts/sync-matt-skills.sh ~/.dsh/scripts/patch-task-store.py
ln -sf ~/.dsh/scripts/trellis-matt-init.sh ~/.local/bin/trellis-matt-init
cp dsh/skills/trellis-matt-init/SKILL.md ~/.dsh/skills/trellis-matt-init/
test -x ~/.local/bin/trellis-matt-init && echo MACRO_OK
```

如果 `~/.local/bin` 不在 PATH，直接用完整路径，或把它加进 PATH。

### 6.6 给 Trellis 模板打父子 pointer 补丁

```bash
trellis_real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v trellis)")"
pkg_root="$(dirname "$(dirname "$trellis_real")")"
python3 scripts/patch-task-store.py "$pkg_root/dist/templates/trellis/scripts/common/task_store.py"
```

期望输出 `已打补丁` 或 `已是带 parent 指针的版本`。

### 6.7 初始化项目（离线，不依赖 GitHub）

```bash
cd <项目根目录>
trellis init --dsh --yes --user <名字>
cp ~/.dsh/scripts/trellis-workflow-matt.md .trellis/workflow.md
python3 - <<'PY'
import json
from pathlib import Path
p = Path(".trellis/.template-hashes.json")
if p.exists():
    data = json.loads(p.read_text(encoding="utf-8"))
    data.get("hashes", {}).pop(".trellis/workflow.md", None)
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
python3 ~/.dsh/scripts/patch-task-store.py .trellis/scripts/common/task_store.py
python3 - <<'PY'
from pathlib import Path
p = Path(".dsh/skills/trellis-start/SKILL.md")
if p.exists():
    s = p.read_text(encoding="utf-8")
    n = s.replace("| Done coding / quality check | `trellis-check` |",
                  "| Done coding / quality check | `code-review` |")
    if n != s:
        p.write_text(n, encoding="utf-8")
PY
python3 .trellis/scripts/get_context.py --mode phase | head -3   # 期望：## Phase Index
```

---

## 7. 脚本失败时：Windows 手工一步步做

> 在 PowerShell 里执行。路径都用 `$HOME`（即 `%USERPROFILE%`）。
> 以下命令默认在**仓库根目录**执行；7.7 会 `cd` 到项目根目录。
>
> **如果 PowerShell 本身被禁用**（连 `powershell -File` 都起不来），不要照抄下面的 PowerShell 命令，改用 Node 版：`node scripts\win-fallback.mjs install`（等价于 7.1–7.6）；项目里用 `node %USERPROFILE%\.dsh\scripts\win-fallback.mjs init -User <名字>`（等价于 7.7）。

### 7.1 安装 Trellis

```powershell
npm install -g @mindfoldhq/trellis@0.6.17
trellis --version
```

### 7.2 下载 Matt skills

```powershell
$tmp = Join-Path $env:TEMP "matt-skills"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
git clone --depth 1 https://github.com/mattpocock/skills $tmp
$names = @("ask-matt","codebase-design","code-review","diagnosing-bugs","domain-modeling",
  "grill-me","grill-with-docs","grilling","handoff","implement","implement-spec",
  "improve-codebase-architecture","pr","prototype","research","retro",
  "setup-matt-pocock-skills","tdd","to-spec","to-tickets","triage","wayfinder","writing-for-agents")
$dst = Join-Path $HOME ".agents\skills"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
foreach ($name in $names) {
  $skill = Get-ChildItem (Join-Path $tmp "skills") -Recurse -Filter "SKILL.md" |
    Where-Object { $_.Directory.Name -eq $name } | Select-Object -First 1
  if ($skill) {
    $target = Join-Path $dst $name
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    Copy-Item -Recurse -Force $skill.Directory.FullName $target
  } else { Write-Warning "Missing $name" }
}
(Get-ChildItem $dst -Directory).Count   # 期望：23
```

### 7.3 生成 dsh 模型可见副本

```powershell
$visible = @("ask-matt","grill-me","grill-with-docs","handoff","implement",
  "implement-spec","improve-codebase-architecture","retro","to-spec","to-tickets",
  "triage","wayfinder")
$dshSkills = Join-Path $HOME ".dsh\skills"
New-Item -ItemType Directory -Force -Path $dshSkills | Out-Null
foreach ($name in $visible) {
  $src = Join-Path $HOME ".agents\skills\$name"
  $target = Join-Path $dshSkills $name
  if (Test-Path $target) { Remove-Item -Recurse -Force $target }
  Copy-Item -Recurse -Force $src $target
  $file = Join-Path $target "SKILL.md"
  $lines = Get-Content $file | Where-Object { $_ -notmatch '^disable-model-invocation:\s*true\s*$' }
  [IO.File]::WriteAllLines($file, $lines, (New-Object System.Text.UTF8Encoding($false)))
}
Select-String -Path (Join-Path $dshSkills "implement\SKILL.md") -Pattern "disable-model-invocation" -Quiet  # 期望：False
```

### 7.4 安装全局规则

```powershell
New-Item -ItemType Directory -Force -Path (Join-Path $HOME ".dsh") | Out-Null
$dst = Join-Path $HOME ".dsh\AGENTS.md"
if (Test-Path $dst) { Copy-Item $dst "$dst.bak.$(Get-Date -Format yyyyMMdd-HHmmss)" }
Copy-Item -Force "dsh\AGENTS.md" $dst
Select-String -Path $dst -Pattern "DSH × Trellis 入口" -Quiet   # 期望：True
```

### 7.5 安装宏、辅助脚本、dsh 技能

```powershell
$scripts = Join-Path $HOME ".dsh\scripts"
$bin = Join-Path $HOME ".local\bin"
New-Item -ItemType Directory -Force -Path $scripts, $bin, (Join-Path $HOME ".dsh\skills\trellis-matt-init") | Out-Null
Copy-Item -Force "scripts\trellis-matt-init.ps1", "scripts\sync-matt-skills.ps1", "scripts\patch-task-store.py", "scripts\win-fallback.mjs" $scripts
Copy-Item -Force "workflows\matt\workflow.md" (Join-Path $scripts "trellis-workflow-matt.md")
Copy-Item -Force "dsh\skills\trellis-matt-init\SKILL.md" (Join-Path $HOME ".dsh\skills\trellis-matt-init")
$cmd = @"
@echo off
setlocal EnableExtensions
if /i "%TRELLIS_NO_POWERSHELL%"=="1" goto :node
where powershell >nul 2>nul
if errorlevel 1 goto :node
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.dsh\scripts\trellis-matt-init.ps1" %*
if not errorlevel 1 exit /b 0
:node
where node >nul 2>nul
if errorlevel 1 (
  echo ERROR: PowerShell is unavailable and Node was not found.
  exit /b 1
)
node "%USERPROFILE%\.dsh\scripts\win-fallback.mjs" init %*
exit /b %ERRORLEVEL%
"@
[IO.File]::WriteAllText((Join-Path $bin "trellis-matt-init.cmd"), ($cmd -replace "`r?`n", "`r`n"), [System.Text.Encoding]::Default)
Test-Path (Join-Path $bin "trellis-matt-init.cmd")   # 期望：True
```

### 7.6 给 Trellis 模板打补丁

```powershell
$npmRoot = (& npm root -g | Select-Object -Last 1).Trim()
$taskStore = Join-Path $npmRoot "@mindfoldhq\trellis\dist\templates\trellis\scripts\common\task_store.py"
python scripts\patch-task-store.py $taskStore
```

### 7.7 初始化项目（离线）

```powershell
cd <项目根目录>
trellis init --dsh --yes --user <名字>
Copy-Item -Force (Join-Path $HOME ".dsh\scripts\trellis-workflow-matt.md") ".trellis\workflow.md"
$hp = ".trellis\.template-hashes.json"
if (Test-Path $hp) {
  $data = Get-Content $hp -Raw | ConvertFrom-Json
  if ($data.hashes) { $data.hashes.PSObject.Properties.Remove(".trellis/workflow.md") }
  [IO.File]::WriteAllText((Resolve-Path $hp).Path, ($data | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
}
python scripts\patch-task-store.py ".trellis\scripts\common\task_store.py"
$start = ".dsh\skills\trellis-start\SKILL.md"
if (Test-Path $start) {
  $s = [IO.File]::ReadAllText($start)
  $n = $s.Replace('| Done coding / quality check | `trellis-check` |', '| Done coding / quality check | `code-review` |')
  if ($n -ne $s) { [IO.File]::WriteAllText($start, $n, (New-Object System.Text.UTF8Encoding($false))) }
}
python .trellis\scripts\get_context.py --mode phase | Select-Object -First 3   # 期望：## Phase Index
```

---

## 8. 关键事实（用户问起时这样解释）

### 为什么 DSH 每次新会话都要手动碰 `trellis-start`？

Trellis 0.6.17（npm 最新 stable）把 dsh 定义为 **class-2 pull 型平台**：它只往项目里写 `.dsh/skills/`、`.agents/skills/` 和 `.dsh/DSH.md`，**不写 session hook**。所以没有「会话启动自动注入 workflow 上下文」这回事。

本仓库的补偿方式：在 `~/.dsh/AGENTS.md` 里加了一条全局规则——进入含 `.trellis/` 的项目，每个新会话先加载 `trellis-start`。效果等价于别的平台的 SessionStart hook，代价是一次技能加载。

### 为什么 Matt 技能要复制一份到 `~/.dsh/skills`？

DSH 解析技能 frontmatter，`disable-model-invocation: true` 会让技能**对模型隐藏**；Matt 上游有 12 个工作流技能带这行。DSH 的用户技能根优先级是 `~/.dsh/skills`（rank 400）高于 `~/.agents/skills`（rank 500），所以在 `~/.dsh/skills` 放一份去掉该行的副本，模型就能自动调用。上游更新后重跑 `sync-matt-skills.sh` / `sync-matt-skills.ps1`。

### `--user` 是什么？

Trellis 的开发者身份，不是系统账号。它决定 `.trellis/.developer` 和 `.trellis/workspace/<名字>/`；团队里每人用自己的名字，别共用。只在首次初始化生效。

### 网络失败怎么办？

- **初始化项目**：默认用 `install.sh` 缓存的 `~/.dsh/scripts/trellis-workflow-matt.md`，**完全离线**。只有 `--refresh` / `-Refresh` 或自定义 `--source` 才联网。
- **联网时**：marketplace 的 index 只有 5 秒超时，宏重试 3 次；仍失败就退回「`trellis init` 原生结构 + curl/Invoke-WebRequest 直取 `workflow.md` + 从 hash 清单移除该文件」；再失败就退回本地缓存。
- **安装环境**：`install.sh` / `install.ps1` 本身要 clone 仓库和 Matt skills，第一次装环境仍需一次 GitHub 可达；完全被墙时先解决代理或镜像。

### 为什么有 `patch-task-store.py`？

Trellis 0.6.17 上游的 `task.py create --parent` 不会给 child 的 `prd.md` 种父任务指针；本 workflow 的「父子 pointer 通道」依赖这一节。补丁幂等，装机器时打 npm 模板，初始化项目时再对项目文件打一次。

---

## 9. 故障排查

| 现象 | 处理 |
| --- | --- |
| `trellis: command not found` | npm 全局 bin 不在 PATH；`export PATH="$(npm prefix -g)/bin:$PATH"`（Windows 把 `npm prefix -g` 下的目录加进 PATH） |
| `Could not fetch workflow template index` | 宏会自动回退；若回退也失败，用 `gh api repos/fanjinchi/trellisWorkflow/contents/workflows/matt/workflow.md -H 'Accept: application/vnd.github.raw' > .trellis/workflow.md`，再删掉 `.trellis/.template-hashes.json` 里的 `.trellis/workflow.md` 键 |
| npm 全局安装 EACCES | 修 npm prefix 权限或改用用户级 prefix；不要 sudo 跑整个脚本 |
| 已有 `~/.dsh/AGENTS.md` 被覆盖 | 用脚本打印的 `AGENTS.md.bak.<时间>` 恢复；确认要合并再手工编辑 |
| 初始化后 dsh 不加载 `trellis-start` | 确认 `~/.dsh/AGENTS.md` 含「DSH × Trellis 入口」一节；确认项目根有 `.trellis/` |
| 模型看不到某个 Matt 技能 | 看它是否在 `~/.dsh/skills` 且 SKILL.md 里没有 `disable-model-invocation: true`；重跑 `sync-matt-skills` |
| Windows 提示 `running scripts is disabled` | 用 `powershell -NoProfile -ExecutionPolicy Bypass -File ...`，或双击 `install.cmd`（它会自动回退到 Node） |
| PowerShell 完全被禁用（AppLocker / Constrained Language Mode） | 用 `.cmd`（自动回退 Node）；或在**仓库根目录**跑 `node scripts\win-fallback.mjs install`。项目里用已安装副本 `node %USERPROFILE%\.dsh\scripts\win-fallback.mjs init -User <名字>`（已安装副本只能 init/sync，不能 install） |
| Windows 找不到 `trellis-matt-init.cmd` | 把 `%USERPROFILE%\.local\bin` 加进 PATH，或用完整路径 |
| 初始化后 workflow 不是 matt | 加 `--force` / `-Force` 重跑；仍不对就检查 `--source` / `-Source` |

---

## 10. 边界

- 只动环境与项目里的 `.trellis/`、`.dsh/`；不要改用户业务代码。
- 不要 commit / push。
- 不安装 Claude Code / Kimi / Pi 等其它平台的文件；本仓库只服务 dsh。
- 用户没明确要求时不要升级 Trellis 大版本；0.6.17 是当前验证版本。
