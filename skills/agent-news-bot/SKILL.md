---
name: agent-news-bot
description: Pull only fresh, unseen news from the local Agent News Bot Mac app (RSS, AI, HN, Polymarket, markets, weather) over localhost HTTP.
version: 1.0.0
---

# Agent News Bot

Agent News Bot is a native macOS newsroom. It keeps a local freshness ledger and only serves stories that have not been shown before and are inside the lookback window.

The live skill with the current bearer token is written to `~/.hermes/skills/agent-news-bot/SKILL.md` when the app launches.

## Default endpoint

- `GET http://127.0.0.1:18765/health`
- `GET http://127.0.0.1:18765/v1/fresh`
- `GET http://127.0.0.1:18765/v1/desks`

Header: `Authorization: Bearer <token from the app Settings>`

Do not invent URLs. Use `tweet` and `hashtags` when drafting social posts.
