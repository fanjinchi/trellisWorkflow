#!/usr/bin/env python3
"""给 Trellis 生成的 task_store.py 打上“父子 pointer”补丁。

背景：workflow 约定 child 任务的 `prd.md` 里只写 `## Upstream Contracts`
指针，父任务的契约只写一次。Trellis 0.6.17 上游的 `_default_prd_content`
不会种这一节，所以 `task.py create --parent` 生成出来的 child 是空的。
本脚本把该函数替换成带 `parent_name` 参数的版本。

幂等：函数里已经出现 `parent_name` 就跳过。
用法：
    python3 patch-task-store.py <task_store.py>
    python3 patch-task-store.py --check <task_store.py>
"""

import re
import sys
from pathlib import Path

NEW_FUNC = r'''def _default_prd_content(
    title: str, description: str | None = None, parent_name: str | None = None
) -> str:
    """Return the default PRD skeleton created with every task.

    A child task seeded with ``parent_name`` gets an ``Upstream Contracts``
    section that points at the parent instead of copying it: cross-child facts
    (formulas, thresholds, config keys, contracts) are stated once in the
    parent, and the child only references them. Seeding the pointer here is
    deliberate -- it belongs in ``prd.md``, the first artifact an implementer
    reads, and NOT in ``implement.jsonl``, where any ``file`` row counts as a
    curated entry and would defeat the zero-spec-context start gate.
    """
    goal = (description or "").strip() or "TBD."
    heading = title.strip() or "Untitled task"
    upstream_block = ""
    if parent_name:
        upstream_block = (
            f"\n## Upstream Contracts\n\n"
            f"- Parent task: `.trellis/tasks/{parent_name}/` "
            "(`prd.md` / `design.md` / `implement.md`).\n"
            "- Read it before this task's artifacts: cross-child facts "
            "(formulas, thresholds, config keys, contracts) are stated in full "
            "there once.\n"
            "- Point at them (`see .trellis/tasks/<owner>/<file>.md \u00a7<n>`) "
            "instead of restating them here.\n"
            "- If the parent has been archived, look under "
            "`.trellis/tasks/archive/<YYYY-MM>/`.\n"
        )
    return f"""# {heading}
{upstream_block}
## Goal

{goal}

## Requirements

- TBD

## Acceptance Criteria

- [ ] TBD

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
"""'''


OLD_CALL = """_default_prd_content(args.title, description),"""
NEW_CALL = """_default_prd_content(
                args.title, description, parent_dir.name if parent_dir else None
            ),"""


def has_patch(text: str) -> bool:
    return "parent_name" in text and NEW_CALL in text


def main() -> int:
    args = [a for a in sys.argv[1:]]
    check_only = "--check" in args
    args = [a for a in args if a != "--check"]
    if len(args) != 1:
        print("用法: patch-task-store.py [--check] <task_store.py>", file=sys.stderr)
        return 2

    target = Path(args[0])
    if not target.is_file():
        print(f"错误: 找不到 {target}", file=sys.stderr)
        return 2
    text = target.read_text(encoding="utf-8")

    if "def _default_prd_content(" not in text:
        print(f"错误: {target} 里没有 _default_prd_content，版本可能不兼容", file=sys.stderr)
        return 1
    if has_patch(text):
        print(f"已是带 parent 指针的版本: {target}")
        return 0
    if check_only:
        print(f"未打补丁: {target}")
        return 1

    start = text.index("def _default_prd_content(")
    # 函数后面紧跟模块级分节注释，用它确定函数结束位置，避免依赖具体函数体。
    m = re.search(r"\n\n\n# =+", text[start:])
    if not m:
        print(f"错误: {target} 的函数边界无法确定", file=sys.stderr)
        return 1
    end = start + m.start()
    text = text[:start] + NEW_FUNC + text[end:]

    if OLD_CALL in text:
        text = text.replace(OLD_CALL, NEW_CALL, 1)
    elif NEW_CALL not in text:
        print(f"错误: {target} 的 cmd_create 调用点没找到", file=sys.stderr)
        return 1

    target.write_text(text, encoding="utf-8")
    print(f"已打补丁: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
