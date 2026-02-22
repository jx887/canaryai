"""JSONL session parser — discover sessions and extract ToolCall objects."""

from __future__ import annotations

import json
import time
from pathlib import Path

from .models import ToolCall

CLAUDE_DIR = Path.home() / ".claude" / "projects"

SKIP_TYPES = frozenset({
    "progress", "file-history-snapshot", "system", "queue-operation",
})

META_TOOLS = frozenset({
    "EnterPlanMode", "ExitPlanMode", "AskUserQuestion",
    "TodoWrite", "TodoRead", "TaskCreate", "TaskUpdate", "TaskGet",
    "TaskList", "TaskOutput", "TaskStop", "Skill",
})


def discover_sessions(
    *,
    since: float | None = None,
    project: str | None = None,
    session_id: str | None = None,
    scan_all: bool = False,
) -> list[Path]:
    """Find JSONL session files matching the given filters.

    Args:
        since: Unix timestamp — only sessions modified after this time.
        project: Absolute path to a project directory to scope the scan.
        session_id: Specific session UUID to scan.
        scan_all: If True, ignore time filters.
    """
    if not CLAUDE_DIR.is_dir():
        return []

    if session_id:
        # Search all project dirs for this session
        matches = list(CLAUDE_DIR.glob(f"*/{session_id}.jsonl"))
        return matches

    if project:
        # Build the escaped project dir name Claude uses
        escaped = "-" + project.strip("/").replace("/", "-")
        project_dir = CLAUDE_DIR / escaped
        if not project_dir.is_dir():
            return []
        paths = sorted(project_dir.glob("*.jsonl"))
    else:
        paths = sorted(CLAUDE_DIR.glob("*/*.jsonl"))

    if scan_all or since is None:
        return paths

    return [p for p in paths if p.stat().st_mtime >= since]


def _extract_text(content) -> str:
    """Normalise tool_result content to a string."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                parts.append(item.get("text", ""))
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(parts)
    return str(content)


def parse_tool_calls(path: Path) -> list[ToolCall]:
    """Stream a JSONL session file and return correlated ToolCall objects."""
    session_id = path.stem
    # pending: tool_use_id -> (tool_name, input_data, index)
    pending: dict[str, tuple[str, dict, int]] = {}
    calls: list[ToolCall] = []
    index = 0

    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            entry_type = obj.get("type", "")
            if entry_type in SKIP_TYPES:
                continue

            msg = obj.get("message")
            if not msg or not isinstance(msg, dict):
                continue

            role = msg.get("role", "")
            content = msg.get("content", "")

            if role == "assistant" and isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "tool_use":
                        name = block.get("name", "")
                        if name in META_TOOLS:
                            continue
                        tid = block.get("id", "")
                        inp = block.get("input", {})
                        pending[tid] = (name, inp, index)
                        index += 1

            elif role == "user" and isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "tool_result":
                        tid = block.get("tool_use_id", "")
                        result_text = _extract_text(block.get("content", ""))
                        if tid in pending:
                            name, inp, idx = pending.pop(tid)
                            calls.append(ToolCall(
                                tool_name=name,
                                tool_id=tid,
                                input_data=inp,
                                output=result_text[:10_000],
                                session_id=session_id,
                                session_path=path,
                                index=idx,
                            ))

    # Flush unmatched tool_use entries (no result yet)
    for tid, (name, inp, idx) in pending.items():
        calls.append(ToolCall(
            tool_name=name,
            tool_id=tid,
            input_data=inp,
            output="",
            session_id=session_id,
            session_path=path,
            index=idx,
        ))

    calls.sort(key=lambda c: c.index)
    return calls
