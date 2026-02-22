"""Data models for canaryai."""

from __future__ import annotations

import enum
from dataclasses import dataclass, field
from pathlib import Path


class Severity(enum.IntEnum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3
    CRITICAL = 4

    @classmethod
    def from_str(cls, s: str) -> Severity:
        return cls[s.upper()]

    @property
    def label(self) -> str:
        return self.name


@dataclass
class ToolCall:
    tool_name: str
    tool_id: str
    input_data: dict
    output: str
    session_id: str
    session_path: Path
    index: int  # position in session

    @property
    def command(self) -> str:
        """Bash command string, truncated to 10K for regex safety."""
        cmd = self.input_data.get("command", "")
        return cmd[:10_000]

    @property
    def file_path(self) -> str:
        return (
            self.input_data.get("file_path", "")
            or self.input_data.get("path", "")
        )

    @property
    def pattern(self) -> str:
        return self.input_data.get("pattern", "")


@dataclass
class Session:
    session_id: str
    path: Path
    project: str
    tool_calls: list[ToolCall] = field(default_factory=list)


@dataclass
class Alert:
    rule_id: str
    rule_name: str
    severity: Severity
    message: str
    tool_call: ToolCall
    related: list[ToolCall] = field(default_factory=list)


@dataclass
class ScanResult:
    sessions_scanned: int = 0
    tool_calls_scanned: int = 0
    alerts: list[Alert] = field(default_factory=list)

    @property
    def has_alerts(self) -> bool:
        return len(self.alerts) > 0

    def filtered(self, min_severity: Severity) -> list[Alert]:
        return [a for a in self.alerts if a.severity >= min_severity]
