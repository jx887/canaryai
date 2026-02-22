"""Scan orchestrator — discover, parse, run rules, collect alerts."""

from __future__ import annotations

from pathlib import Path

from .models import Severity, ScanResult
from .parser import discover_sessions, parse_tool_calls
from .rules import run_all_rules


class Scanner:
    def __init__(
        self,
        *,
        since: float | None = None,
        project: str | None = None,
        session_id: str | None = None,
        scan_all: bool = False,
        min_severity: Severity | None = None,
        verbose: bool = False,
    ):
        self.since = since
        self.project = project
        self.session_id = session_id
        self.scan_all = scan_all
        self.min_severity = min_severity
        self.verbose = verbose

    def run(self) -> ScanResult:
        result = ScanResult()

        paths = discover_sessions(
            since=self.since,
            project=self.project,
            session_id=self.session_id,
            scan_all=self.scan_all,
        )

        for path in paths:
            tool_calls = parse_tool_calls(path)
            result.sessions_scanned += 1
            result.tool_calls_scanned += len(tool_calls)
            alerts = run_all_rules(tool_calls)
            if self.min_severity:
                alerts = [a for a in alerts if a.severity >= self.min_severity]
            result.alerts.extend(alerts)

        # Sort alerts: highest severity first, then by rule_id
        result.alerts.sort(key=lambda a: (-a.severity, a.rule_id))
        return result
