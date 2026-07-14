---
name: show-codex-usage-widget
description: Show the user's current Codex quota, remaining percentage, usage window, or reset time. Use when the user asks about Codex usage, limits, credits, quota, allowance, or when the quota resets.
---

# Show Codex Usage

1. Call `get_codex_usage` from the `codex-usage-widget` MCP server.
2. Report each available rate-limit window separately.
3. Show used and remaining percentages plus the reset time in the user's local timezone.
4. If credits information is available, report it without guessing a currency or unit.
5. Explain briefly that the value is the newest local Codex snapshot and can lag until Codex writes another usage event.
6. Never inspect or expose `auth.json`, access tokens, or unrelated session content.

