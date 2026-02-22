# Contributing Rules to CanaryAI

Community rules live in this directory (built-in) or in `~/.config/canaryai/rules/` (user-local).

## Rule Format

Create a `.yaml` file with one or more rules:

```yaml
- id: CUSTOM-001
  name: My Detection Rule
  severity: HIGH           # LOW | MEDIUM | HIGH | CRITICAL
  description: >
    Optional longer description of what this rule detects
    and why it's suspicious.
  tools:                   # optional — omit to match any tool
    - Bash
    - Write
  match:                   # OR logic between blocks
    - field: command       # command | file_path | pattern | output | any
      patterns:
        - "suspicious_regex_1"
        - "suspicious_regex_2"
  message: "Short description shown in the alert"
  tags:
    - persistence
    - your-category
```

## Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique rule ID, e.g. `HIGH-101`. Use `CUSTOM-` prefix for personal rules |
| `name` | Yes | Short human-readable name |
| `severity` | Yes | `LOW`, `MEDIUM`, `HIGH`, or `CRITICAL` |
| `description` | No | Longer explanation |
| `tools` | No | List of tool names to match (`Bash`, `Read`, `Write`, `Glob`, `Grep`, etc.). Omit to match all tools |
| `match` | Yes | List of match conditions (OR between blocks) |
| `match[].field` | Yes | What to match against: `command`, `file_path`, `pattern`, `output`, or `any` |
| `match[].patterns` | Yes | List of Python regex patterns (OR between patterns, case-insensitive) |
| `message` | Yes | Alert message shown to the user |
| `tags` | No | List of category tags |

## Adding User-Local Rules

```bash
mkdir -p ~/.config/canaryai/rules/
cp my-rule.yaml ~/.config/canaryai/rules/
canaryai rules list   # verify it loaded
```

## Submitting Community Rules

1. Fork `github.com/canaryai/canaryai`
2. Add your `.yaml` file to `src/canaryai/rules/builtin/`
3. Open a pull request with a description of what the rule detects
