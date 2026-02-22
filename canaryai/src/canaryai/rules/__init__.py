"""Rule engine — base class and registry."""

from __future__ import annotations

from abc import ABC, abstractmethod

from ..models import Alert, Severity, ToolCall


class Rule(ABC):
    rule_id: str
    name: str
    severity: Severity

    def check(self, tc: ToolCall) -> Alert | None:
        """Check a single tool call. Return an Alert or None."""
        return None

    def check_sequence(self, tool_calls: list[ToolCall]) -> list[Alert]:
        """Check patterns across a sequence of tool calls."""
        return []

    def _alert(self, tc: ToolCall, message: str, related: list[ToolCall] | None = None) -> Alert:
        return Alert(
            rule_id=self.rule_id,
            rule_name=self.name,
            severity=self.severity,
            message=message,
            tool_call=tc,
            related=related or [],
        )


# Populated at import time by each rule module
ALL_RULES: list[Rule] = []


def _register(*rules: Rule) -> None:
    ALL_RULES.extend(rules)


def run_all_rules(tool_calls: list[ToolCall]) -> list[Alert]:
    """Run every registered rule against a session's tool calls."""
    alerts: list[Alert] = []
    for rule in ALL_RULES:
        # Single-call checks
        for tc in tool_calls:
            alert = rule.check(tc)
            if alert:
                alerts.append(alert)
        # Sequence checks
        alerts.extend(rule.check_sequence(tool_calls))
    return alerts


# Import Python rules that require sequence/complex logic
from . import exfiltration  # noqa: E402, F401

# Load YAML rules (builtin + user ~/.config/canaryai/rules/)
from .loader import load_yaml_rules  # noqa: E402, F401
load_yaml_rules()
