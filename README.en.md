[简体中文](./README.md) | English

# Trellis Matt Workflow Template

A reusable environment that connects Trellis's Plan / Execute / Finish lifecycle with Matt's spec-driven engineering flow: a `workflow.md` template, a machine-level installer, and a per-project init macro. Built for **DeepSeek Harness (dsh)**.

- Deploy on a new machine: hand [AGENT-SETUP.md](./AGENT-SETUP.md) to the dsh agent, or run `bash scripts/install.sh` yourself
- Add a project: `trellis-matt-init --user <your-name>`
- Workflow itself: `workflows/matt/workflow.md`

## Fastest path (new machine)

```bash
git clone https://github.com/fanjinchi/trellisWorkflow ~/code/trellisWorkflow
bash ~/code/trellisWorkflow/scripts/install.sh
```

Then, from any project root:

```bash
trellis-matt-init --user <your-name>
```

That's it. Start dsh in the project and say "start with trellis-start".

> Even simpler: give this sentence to dsh on the new machine —
> "Clone https://github.com/fanjinchi/trellisWorkflow, read AGENT-SETUP.md, set up the environment as described, and report back to the user."

## Layout

- `AGENT-SETUP.md` — agent-facing deployment guide (steps, verification, troubleshooting)
- `dsh/AGENTS.md` — global rules, installed to `~/.dsh/AGENTS.md`
- `dsh/skills/trellis-matt-init/SKILL.md` — dsh skill triggered by "initialize this project"
- `scripts/install.sh` — machine-level install (Trellis, Matt skills, dsh copies, global rules, macro, template patch)
- `scripts/trellis-matt-init.sh` — one-command project initialization macro
- `scripts/sync-matt-skills.sh` — download/update Matt skills and generate model-visible dsh copies
- `scripts/patch-task-store.py` — patch Trellis's `task_store.py` with the parent/child pointer logic
- `index.json` — Trellis marketplace index declaring a `type: "workflow"` template
- `workflows/matt/workflow.md` — the full workflow (validated against the parser in a Trellis 0.6.17 project)

> `AGENT-SETUP.md` is currently written in Chinese. This README covers the complete setup path in English.

## What this workflow does

- **Planning is owned by Matt**: `grill-with-docs` (runs the `grilling` interview in the repo, leaving a `GLOSSARY.md` / ADR trail) → `to-spec` produces the spec → `to-tickets` splits it into tracer-bullet tickets. Trellis only owns task lifecycle and artifact paths.
- **Single source of truth**: every fact (formula, threshold, config key, contract, decision) is stated in full in exactly one artifact; everywhere else points at it. Acceptance criteria may restate a literal value; prose may not. `file:line` references, grep output, and code listings belong in `research/` or a check script, not in planning artifacts. The task directory is the tracker; nothing is duplicated into bd.
- **Parent/child pointer channel**: the parent owns invariants shared across children; a child only writes an `upstream contract: <parent>/design.md §n` pointer. With the patch, `task.py create --parent` seeds `## Upstream Contracts` into the child's `prd.md` automatically.
- **Skill routing table**: the workflow ships its own "intent → Matt skill" table; only intents missing from it go through `ask-matt`.
- **Implementation and review**: Phase 2 uses Matt's `implement` / `implement-spec` + `tdd`; `code-review` runs the Standards + Spec two-axis review.
- **Wrap-up**: keeps Trellis's `trellis-update-spec` spec write-back and the Phase 3.4 commit gate.

## No session hook on dsh (still true in 0.6.17)

Trellis treats dsh as a **class-2 pull-based** platform: it only writes `.dsh/skills/`, `.agents/skills/`, and `.dsh/DSH.md`, and **does not install a session hook**. Each new session therefore does not receive workflow state automatically; `trellis-start` must be loaded explicitly. The latest npm release is still 0.6.17 (checked 2026-11), and the commits on upstream `main` after that release do not add a dsh hook.

This repo works around it with a global rule in `dsh/AGENTS.md`: in a project containing `.trellis/`, every new session loads `trellis-start` first. It is equivalent to a SessionStart hook, at the cost of one skill load.

## Installation details

### Prerequisites

1. **Trellis CLI 0.6.17** (latest npm release; newer versions are untested)
2. **dsh** installed, with `~/.dsh` present
3. **Node.js ≥ 20**, `git`, `curl`, `python3`
4. Network access to GitHub / npm (a slow raw.githubusercontent still works; the macro falls back)

### What `install.sh` does

1. Installs/checks `@mindfoldhq/trellis@0.6.17`
2. `git clone`s Matt skills into `~/.agents/skills` (only the 23 used by the workflow)
3. Copies the 12 skills carrying `disable-model-invocation: true` into `~/.dsh/skills` and removes that line (DSH hides skills carrying it)
4. Installs `~/.dsh/AGENTS.md` (an existing file is backed up as `AGENTS.md.bak.<timestamp>`)
5. Installs `~/.dsh/scripts/` and `~/.local/bin/trellis-matt-init`
6. Installs the dsh skill `~/.dsh/skills/trellis-matt-init`
7. Patches the `task_store.py` template inside the npm package with the parent/child pointer logic

### Macro defaults and fallback

```bash
trellis-matt-init --user alice
# equivalent to:
trellis init --dsh --yes --user alice \
  --workflow matt --workflow-source gh:fanjinchi/trellisWorkflow
```

- `--user`: developer identity, written to `.trellis/.developer` and used for `.trellis/workspace/<name>/`. **Set it explicitly**; when omitted it falls back to `git config user.name`. It only applies on first initialization; an existing `.trellis/.developer` is never overwritten.
- `--source gh:owner/repo`: use a fork.
- `--force`: force the workflow switch when `.trellis/` already exists.
- Network failure: the macro retries 3 times → falls back to a plain `trellis init` structure + `curl` fetching `workflow.md` directly + removing that file from `.template-hashes.json` (so `trellis update` will not overwrite it).
- The macro also rewrites the review route in `.dsh/skills/trellis-start` from the stale upstream `trellis-check` to `code-review`, keeping it consistent with the workflow.

### Manual initialization (without the macro)

```bash
trellis init --dsh -u <name> --workflow matt --workflow-source gh:fanjinchi/trellisWorkflow
python3 ~/.dsh/scripts/patch-task-store.py .trellis/scripts/common/task_store.py
```

### Marketplace-only workflow install (legacy path)

```bash
trellis workflow --marketplace gh:fanjinchi/trellisWorkflow --template matt --force
```

This only writes `.trellis/workflow.md`. **The other supporting changes** (dsh skill copies, `task_store.py` patch, global rules) are now handled by `install.sh` / the macro, so no manual work is needed.

## Verification

```bash
# Machine level
trellis --version
bash ~/.dsh/scripts/sync-matt-skills.sh --check

# Project level (from the project root)
grep -c "Single-source rule (every planning artifact" .trellis/workflow.md   # 1
python3 .trellis/scripts/get_context.py --mode phase | head -3               # ## Phase Index
grep -c "parent_name" .trellis/scripts/common/task_store.py                  # >=1
grep -c "trellis-check" .dsh/skills/trellis-start/SKILL.md                    # 0
```

The workflow must keep these parser markers: `## Phase Index`, `#### X.Y` step headings, and paired `[workflow-state:...]` blocks. `get_context.py` is the final judge.

## Updates and version pinning

- **Change the workflow template**: edit `workflows/matt/workflow.md`, commit, then re-run `trellis workflow --marketplace ... --force` or `trellis-matt-init --force` in each project.
- **Update Matt skills**: `bash ~/.dsh/scripts/sync-matt-skills.sh`.
- **Pin a version**: `gh:fanjinchi/trellisWorkflow#v1` (branch or tag).
- After a Trellis upgrade: re-run `install.sh` to re-apply the template patch; if `trellis update` overwrites the project's `task_store.py`, re-run `patch-task-store.py`.

## Notes

- The template does not include project specs under `.trellis/spec/`; specs are a separate template type (`trellis init --registry`).
- If your repo is not `fanjinchi/trellisWorkflow`, replace the `--source` value and the URLs in this README with `gh:<owner>/<repo>`.
- Upstream `task_store.py` has no parent/child pointer logic, so the patch in this repo is required. If upstream adds it later, `patch-task-store.py` detects that and skips.

## License

This template is a derivative of the Trellis workflow template
([mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis)), licensed under
AGPL-3.0-only. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
