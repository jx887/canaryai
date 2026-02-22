"""CLI entry point for canaryai."""

from __future__ import annotations

import argparse
import re
import sys
import time

from . import __version__
from .models import Severity
from .reporter import JSONReporter, TerminalReporter
from .scanner import Scanner


def parse_since(value: str) -> float:
    """Parse a relative time string like '7d', '24h', '30m' into a Unix timestamp."""
    m = re.fullmatch(r"(\d+)\s*([dhm])", value.strip().lower())
    if not m:
        raise argparse.ArgumentTypeError(
            f"Invalid time format: {value!r}. Use e.g. '24h', '7d', '30m'."
        )
    amount = int(m.group(1))
    unit = m.group(2)
    seconds = {"d": 86400, "h": 3600, "m": 60}[unit]
    return time.time() - (amount * seconds)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="canaryai",
        description="AI agent security monitor — scan Claude Code sessions for suspicious behaviour",
    )
    parser.add_argument("--version", action="version", version=f"canaryai {__version__}")

    sub = parser.add_subparsers(dest="command")
    scan = sub.add_parser("scan", help="Scan session logs for suspicious activity")

    rules = sub.add_parser("rules", help="Manage detection rules")  # noqa: F841
    rules_sub = rules.add_subparsers(dest="rules_command")
    rules_list = rules_sub.add_parser("list", help="List all loaded rules")
    rules_list.add_argument("--json", action="store_true", dest="json_output",
                            help="Output as JSON")
    rules_add = rules_sub.add_parser("add", help="Install a YAML rule file")
    rules_add.add_argument("file", help="Path to a .yaml rule file")

    scan.add_argument("--all", action="store_true", dest="scan_all",
                       help="Scan all sessions (ignore time filter)")
    scan.add_argument("--project", type=str, default=None,
                       help="Scan sessions for a specific project path")
    scan.add_argument("--session", type=str, default=None,
                       help="Scan a specific session by UUID")
    scan.add_argument("--since", type=str, default=None,
                       help="Time window, e.g. '7d', '24h', '30m'")
    scan.add_argument("--severity", type=str, default=None,
                       help="Minimum severity: low, medium, high, critical")
    scan.add_argument("--json", action="store_true", dest="json_output",
                       help="Output results as JSON")
    scan.add_argument("--verbose", action="store_true",
                       help="Show additional detail")

    return parser


def main(argv: list[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)

    if not args.command:
        parser.print_help()
        sys.exit(0)

    if args.command == "scan":
        _do_scan(args)
    elif args.command == "rules":
        _do_rules(args)


def _do_rules(args: argparse.Namespace) -> None:
    import shutil
    from pathlib import Path
    from .rules.loader import list_rules_info, get_category_counts, _USER_DIR

    sub = getattr(args, "rules_command", None)

    if sub == "list" or sub is None:
        import json as _json
        from .rules import ALL_RULES

        json_output = getattr(args, "json_output", False)

        if json_output:
            print(_json.dumps(get_category_counts(), indent=2))
            return

        python_rules = [r for r in ALL_RULES if not hasattr(r, "source")]
        yaml_info = list_rules_info()

        print(f"\n{'ID':<14} {'Severity':<10} {'Category':<14} Name")
        print("-" * 64)
        for r in python_rules:
            print(f"  {r.rule_id:<12} {r.severity.name:<10} {'Core':<14} {r.name}")
        for info in yaml_info:
            print(f"  {info['id']:<12} {info['severity']:<10} {info['category']:<14} {info['name']}")
        print(f"\nTotal: {len(python_rules) + len(yaml_info)} rules "
              f"({len(python_rules)} Python, {len(yaml_info)} YAML)\n")
        print(f"Add custom rules: ~/.config/canaryai/rules/*.yaml")

    elif sub == "add":
        src = Path(args.file).expanduser().resolve()
        if not src.exists():
            print(f"Error: file not found: {src}", file=sys.stderr)
            sys.exit(2)
        _USER_DIR.mkdir(parents=True, exist_ok=True)
        dest = _USER_DIR / src.name
        shutil.copy2(src, dest)
        print(f"Installed: {dest}")
        print("Run 'canaryai rules list' to verify.")

    else:
        print("Usage: canaryai rules [list|add <file>]")
        sys.exit(2)


def _do_scan(args: argparse.Namespace) -> None:
    # Determine time window
    since: float | None = None
    if args.scan_all or args.session:
        since = None  # no time filter
    elif args.since:
        since = parse_since(args.since)
    else:
        # Default: last 24h
        since = time.time() - 86400

    min_severity: Severity | None = None
    if args.severity:
        try:
            min_severity = Severity.from_str(args.severity)
        except KeyError:
            print(f"Error: unknown severity {args.severity!r}. "
                  f"Use: low, medium, high, critical", file=sys.stderr)
            sys.exit(2)

    scanner = Scanner(
        since=since,
        project=args.project,
        session_id=args.session,
        scan_all=args.scan_all,
        min_severity=min_severity,
        verbose=args.verbose,
    )

    result = scanner.run()

    if args.json_output:
        JSONReporter().report(result)
    else:
        TerminalReporter(verbose=args.verbose).report(result)

    sys.exit(1 if result.has_alerts else 0)
