"""YAML-based rule loader — enables community and custom rules.

Rules are loaded from two locations (both are optional):
  1. src/canaryai/rules/builtin/   — rules shipped with canaryai
  2. ~/.config/canaryai/rules/     — user-defined and community rules

YAML rule format
----------------
Single rule per file or a list of rules per file:

    id: CUSTOM-001
    name: My Custom Rule
    severity: HIGH          # LOW | MEDIUM | HIGH | CRITICAL
    description: Optional longer description
    tools:                  # optional — omit to match any tool
      - Bash
    match:                  # OR logic between blocks
      - field: command      # command | file_path | pattern | output | any
        patterns:
          - "suspicious_pattern"
          - "another_pattern"
    message: "Describe what was detected"
    tags:
      - persistence
      - custom
"""

from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Any

from ..models import Alert, Severity, ToolCall
from . import Rule, _register

logger = logging.getLogger(__name__)

_BUILTIN_DIR = Path(__file__).parent / "builtin"
_USER_DIR = Path.home() / ".config" / "canaryai" / "rules"


def _get_field(tc: ToolCall, field: str) -> str:
    """Extract a string value from a ToolCall for pattern matching."""
    if field == "command":
        return tc.input_data.get("command", "")
    if field == "file_path":
        return tc.input_data.get("file_path", "") or tc.input_data.get("path", "")
    if field == "pattern":
        return tc.input_data.get("pattern", "")
    if field == "output":
        return tc.output or ""
    # "any" — concatenate all searchable fields
    return " ".join([
        tc.input_data.get("command", ""),
        tc.input_data.get("file_path", "") or tc.input_data.get("path", ""),
        tc.input_data.get("pattern", ""),
        tc.output or "",
    ])


class YamlRule(Rule):
    """A detection rule loaded from a YAML definition."""

    def __init__(self, data: dict[str, Any], source: Path) -> None:
        self.rule_id: str = data["id"]
        self.name: str = data["name"]
        self.severity: Severity = Severity.from_str(data["severity"])
        self.description: str = data.get("description", "")
        self.tools: list[str] | None = data.get("tools")
        self.message_template: str = data["message"]
        self.tags: list[str] = data.get("tags", [])
        self.source: Path = source

        # Optional regex matched against tool name (for prefix matches like mcp__)
        tool_pat = data.get("tool_pattern")
        self.tool_pattern: re.Pattern[str] | None = (
            re.compile(tool_pat) if tool_pat else None
        )

        # Compile match conditions — OR logic between blocks
        self._conditions: list[tuple[str, list[re.Pattern[str]]]] = []
        for cond in data.get("match", []):
            field = cond.get("field", "any")
            compiled = [
                re.compile(p, re.IGNORECASE) for p in cond.get("patterns", [])
            ]
            self._conditions.append((field, compiled))

    def check(self, tc: ToolCall) -> Alert | None:
        # Tool name filter — exact list or regex pattern
        if self.tool_pattern:
            if not self.tool_pattern.search(tc.tool_name):
                return None
        elif self.tools:
            if tc.tool_name not in self.tools:
                return None

        # If no match conditions, tool match alone is sufficient
        if not self._conditions:
            return self._alert(tc, self.message_template)

        # Match: any condition block (OR), any pattern within a block (OR)
        for field, patterns in self._conditions:
            value = _get_field(tc, field)
            for pat in patterns:
                if pat.search(value):
                    return self._alert(tc, self.message_template)
        return None


def _load_file(yaml_file: Path, label: str) -> int:
    """Load one YAML file and register all rules within it. Returns count."""
    import yaml  # imported lazily — already confirmed available at this point

    try:
        with yaml_file.open() as f:
            data = yaml.safe_load(f)
        if not data:
            return 0
        rules_data: list[dict] = data if isinstance(data, list) else [data]
        count = 0
        for rule_data in rules_data:
            rule = YamlRule(rule_data, yaml_file)
            _register(rule)
            count += 1
        return count
    except Exception as exc:
        logger.warning("Failed to load rule from %s: %s", yaml_file, exc)
        return 0


def load_yaml_rules(extra_dirs: list[Path] | None = None) -> int:
    """Load YAML rules from builtin + user + any extra directories.

    Returns the total number of rules registered.
    Safe to call even if pyyaml is not installed (logs a warning).
    """
    try:
        import yaml  # noqa: F401
    except ImportError:
        logger.warning(
            "pyyaml not installed — YAML rules disabled. Run: pip install pyyaml"
        )
        return 0

    directories = [_BUILTIN_DIR, _USER_DIR] + (extra_dirs or [])
    total = 0
    for directory in directories:
        if not directory.is_dir():
            continue
        for yaml_file in sorted(directory.glob("*.yaml")) + sorted(directory.glob("*.yml")):
            total += _load_file(yaml_file, directory.name)
    return total


_CATEGORY_NAMES: dict[str, str] = {
    "commands": "Commands",
    "backdoor": "Backdoor",
    "exfiltration": "Exfiltration",
    "recon": "Recon",
    "macos": "macOS",
    "docker": "Docker",
    "network": "Network",
}


def _category_name(stem: str) -> str:
    return _CATEGORY_NAMES.get(stem.lower(), stem.capitalize())


def get_category_counts() -> dict[str, Any]:
    """Return total rule count and per-category breakdown as a dict."""
    from . import ALL_RULES
    from .exfiltration import SSHKeyExfilRule, CredentialExfilRule, SuspiciousPostRule

    python_count = sum(
        1 for r in ALL_RULES
        if isinstance(r, (SSHKeyExfilRule, CredentialExfilRule, SuspiciousPostRule))
    )

    categories: dict[str, int] = {}
    if python_count:
        categories["Core"] = python_count

    try:
        import yaml
    except ImportError:
        return {"total": len(ALL_RULES), "categories": [
            {"name": k, "count": v} for k, v in categories.items()
        ]}

    for directory in [_BUILTIN_DIR, _USER_DIR]:
        if not directory.is_dir():
            continue
        for yaml_file in sorted(directory.glob("*.yaml")) + sorted(directory.glob("*.yml")):
            try:
                with yaml_file.open() as f:
                    data = yaml.safe_load(f)
                if not data:
                    continue
                rules_data: list[dict] = data if isinstance(data, list) else [data]
                name = _category_name(yaml_file.stem)
                categories[name] = categories.get(name, 0) + len(rules_data)
            except Exception:
                pass

    return {
        "total": len(ALL_RULES),
        "categories": [{"name": k, "count": v} for k, v in categories.items()],
    }


def list_rules_info() -> list[dict[str, Any]]:
    """Return metadata for all YAML rule files (for `canaryai rules list`)."""
    try:
        import yaml
    except ImportError:
        return []

    result: list[dict[str, Any]] = []
    for directory, label in [(_BUILTIN_DIR, "built-in"), (_USER_DIR, "user")]:
        if not directory.is_dir():
            continue
        for yaml_file in sorted(directory.glob("*.yaml")) + sorted(directory.glob("*.yml")):
            try:
                with yaml_file.open() as f:
                    data = yaml.safe_load(f)
                if not data:
                    continue
                rules_data: list[dict] = data if isinstance(data, list) else [data]
                for rule_data in rules_data:
                    result.append({
                        "id": rule_data.get("id", "?"),
                        "name": rule_data.get("name", "?"),
                        "severity": rule_data.get("severity", "?"),
                        "source": label,
                        "category": _category_name(yaml_file.stem),
                        "file": str(yaml_file),
                        "tags": rule_data.get("tags", []),
                    })
            except Exception:
                pass
    return result
