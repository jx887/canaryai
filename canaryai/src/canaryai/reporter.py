"""Output reporters — ANSI terminal and JSON."""

from __future__ import annotations

import json
import sys

from .models import Alert, ScanResult, Severity


# ANSI color codes
_COLORS = {
    Severity.CRITICAL: "\033[1;91m",  # bold bright red
    Severity.HIGH: "\033[1;31m",       # bold red
    Severity.MEDIUM: "\033[1;33m",     # bold yellow
    Severity.LOW: "\033[36m",          # cyan
}
_RESET = "\033[0m"
_BOLD = "\033[1m"
_DIM = "\033[2m"


def _severity_badge(sev: Severity) -> str:
    color = _COLORS.get(sev, "")
    return f"{color}[{sev.label}]{_RESET}"


class TerminalReporter:
    def __init__(self, verbose: bool = False):
        self.verbose = verbose

    def report(self, result: ScanResult) -> None:
        out = sys.stderr

        print(f"\n{_BOLD}canaryai scan results{_RESET}", file=out)
        print(f"{_DIM}Sessions scanned: {result.sessions_scanned}{_RESET}", file=out)
        print(f"{_DIM}Tool calls analyzed: {result.tool_calls_scanned}{_RESET}", file=out)
        print(file=out)

        if not result.alerts:
            print(f"\033[1;32m  No suspicious activity detected.{_RESET}\n", file=out)
            return

        # Group by severity
        by_sev: dict[Severity, list[Alert]] = {}
        for alert in result.alerts:
            by_sev.setdefault(alert.severity, []).append(alert)

        total = len(result.alerts)
        summary_parts = []
        for sev in (Severity.CRITICAL, Severity.HIGH, Severity.MEDIUM, Severity.LOW):
            count = len(by_sev.get(sev, []))
            if count:
                summary_parts.append(f"{_COLORS[sev]}{count} {sev.label}{_RESET}")
        print(f"  {_BOLD}{total} alert(s):{_RESET} " + ", ".join(summary_parts), file=out)
        print(file=out)

        for alert in result.alerts:
            badge = _severity_badge(alert.severity)
            print(f"  {badge} {_BOLD}{alert.rule_id}{_RESET} {alert.rule_name}", file=out)
            print(f"    {alert.message}", file=out)
            session_id = alert.tool_call.session_id
            print(f"    {_DIM}session: {session_id}  tool: {alert.tool_call.tool_name}  index: {alert.tool_call.index}{_RESET}", file=out)
            if alert.related:
                for rel in alert.related:
                    print(f"    {_DIM}  related: {rel.tool_name} (index {rel.index}){_RESET}", file=out)
            print(file=out)


class JSONReporter:
    def report(self, result: ScanResult) -> None:
        data = {
            "sessions_scanned": result.sessions_scanned,
            "tool_calls_scanned": result.tool_calls_scanned,
            "alert_count": len(result.alerts),
            "alerts": [self._alert_dict(a) for a in result.alerts],
        }
        json.dump(data, sys.stdout, indent=2)
        print()  # trailing newline

    @staticmethod
    def _alert_dict(alert: Alert) -> dict:
        return {
            "rule_id": alert.rule_id,
            "rule_name": alert.rule_name,
            "severity": alert.severity.label,
            "message": alert.message,
            "session_id": alert.tool_call.session_id,
            "tool_name": alert.tool_call.tool_name,
            "tool_index": alert.tool_call.index,
            "related": [
                {"tool_name": r.tool_name, "tool_index": r.index}
                for r in alert.related
            ],
        }
