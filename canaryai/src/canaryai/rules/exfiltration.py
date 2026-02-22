"""Complex exfiltration rules that require sequence/lookahead logic.

Simple exfiltration rules (CRIT-004, LOW-001, LOW-002) are in builtin/exfiltration.yaml.
"""

from __future__ import annotations

import re

from ..models import Alert, Severity, ToolCall
from . import Rule, _register

_NETWORK_SEND = re.compile(
    r"(curl|wget|nc\b|ncat\b|socat\b|python.{0,30}(requests|urllib|http\.client)|fetch\()"
)
_SSH_KEY_PATH = re.compile(r"[/~].{0,60}\.ssh/(id_|authorized_keys|known_hosts)")
_CRED_FILE_PATH = re.compile(
    r"(\.env|credentials\.json|\.pem|\.key|\.p12|\.pfx|\.aws/credentials|\.netrc|\.npmrc|\.git-credentials)"
)
_LOCALHOST = re.compile(r"(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])")


def _is_network_bash(tc: ToolCall) -> bool:
    return tc.tool_name == "Bash" and bool(_NETWORK_SEND.search(tc.command))


# --- CRIT-002: SSH Key Exfiltration (sequence rule) ---

class SSHKeyExfilRule(Rule):
    rule_id = "CRIT-002"
    name = "SSH Key Exfiltration"
    severity = Severity.CRITICAL

    def check_sequence(self, tool_calls: list[ToolCall]) -> list[Alert]:
        alerts = []
        for i, tc in enumerate(tool_calls):
            path = tc.file_path or tc.command
            if not _SSH_KEY_PATH.search(path):
                continue
            for later in tool_calls[i + 1: i + 16]:
                if _is_network_bash(later):
                    alerts.append(self._alert(
                        tc,
                        f"SSH key read ({(tc.file_path or tc.command)[:80]}) followed by network send",
                        related=[later],
                    ))
                    break
        return alerts


# --- CRIT-003: Credential Exfiltration (sequence rule) ---

class CredentialExfilRule(Rule):
    rule_id = "CRIT-003"
    name = "Credential Exfiltration"
    severity = Severity.CRITICAL

    def check_sequence(self, tool_calls: list[ToolCall]) -> list[Alert]:
        alerts = []
        for i, tc in enumerate(tool_calls):
            path = tc.file_path or tc.command
            if not _CRED_FILE_PATH.search(path):
                continue
            for later in tool_calls[i + 1: i + 16]:
                if _is_network_bash(later):
                    alerts.append(self._alert(
                        tc,
                        f"Credential file read ({(tc.file_path or tc.command)[:80]}) followed by network send",
                        related=[later],
                    ))
                    break
        return alerts


# --- HIGH-004: Suspicious POST (localhost exclusion can't be expressed in YAML) ---

_SUSPICIOUS_POST = [
    re.compile(r"curl\s+.{0,400}(-d\s|--data|--data-binary|-F\s|--form).{0,400}https?://", re.DOTALL),
    re.compile(r"wget\s+.{0,200}--post-data.{0,200}https?://", re.DOTALL),
]


class SuspiciousPostRule(Rule):
    rule_id = "HIGH-004"
    name = "Suspicious POST"
    severity = Severity.HIGH

    def check(self, tc: ToolCall) -> Alert | None:
        if tc.tool_name != "Bash":
            return None
        for pat in _SUSPICIOUS_POST:
            m = pat.search(tc.command)
            if m and not _LOCALHOST.search(m.group(0)):
                return self._alert(tc, f"Suspicious POST request: {tc.command[:200]}")
        return None


_register(
    SSHKeyExfilRule(),
    CredentialExfilRule(),
    SuspiciousPostRule(),
)
