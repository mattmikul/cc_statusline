# Claude Code Status Line

Custom status line script for Claude Code showing current directory, context window usage, and plan quota usage.

Similar to what shows in `/usage`

```
~/code/myproject  context:14%/200k  quota: 18% of 5h, 9% of 7d
```

- **context** — context window used for the current session
- **5h** — 5-hour rolling session quota (matches `/status` > Usage)
- **7d** — 7-day all-models quota (matches `/status` > Usage)

## How it works

The quota percentages are fetched from `https://api.anthropic.com/api/oauth/usage` using the OAuth token Claude Code stores locally — the macOS Keychain on macOS, or `~/.claude/.credentials.json` on Linux. Results are cached for 60 seconds to avoid hammering the API.

Note: this endpoint is undocumented and may change. Once Anthropic exposes quota data in the official statusLine JSON ([issue #27915](https://github.com/anthropics/claude-code/issues/27915)), this workaround can be removed.

## Install

1. Clone or copy `statusline.sh` to a permanent location.

2. Add to `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/code/cc_statusline/statusline.sh"
}
```

## Requirements

- macOS or Linux
- `jq`, `curl`, and `python3`
- Claude Code logged in via OAuth (not API key)
