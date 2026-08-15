---
name: agent-news-bot
description: Pull only fresh, unseen news from the local Agent News Bot desk (RSS, AI, HN, Polymarket, markets, weather) over localhost HTTP.
version: 1.0.0
---

# Agent News Bot (Linux)

Agent News Bot runs on this machine as `agent-news-bot.service`. It keeps a freshness ledger and only serves stories that have not been shown before and are inside the 12-hour lookback window.

Do not invent URLs. Prefer `tweet` and `hashtags` when drafting social posts. Never print the bearer token in logs, chat, or any public channel.

## Endpoint

Base URL: `http://127.0.0.1:18765`

Token file (path is set by `$AGENT_NEWSBOT_HOME`):

```text
$AGENT_NEWSBOT_HOME/export/bridge.token
```

File snapshot (same payload, no HTTP; path set by `$AGENT_NEWSBOT_SHARED`):

```text
$AGENT_NEWSBOT_SHARED/latest.json
```

## Calls

```bash
TOKEN=$(cat "$AGENT_NEWSBOT_HOME/export/bridge.token")
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:18765/health
curl -sS -H "Authorization: Bearer $TOKEN" 'http://127.0.0.1:18765/v1/fresh?limit=30'
curl -sS -H "Authorization: Bearer $TOKEN" 'http://127.0.0.1:18765/v1/fresh?desk=ai'
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:18765/v1/desks
curl -sS -X POST -H "Authorization: Bearer $TOKEN" http://127.0.0.1:18765/v1/fetch
```

Desks: `breaking`, `politics`, `world`, `business`, `markets`, `tech`, `ai`, `science`, `health`, `entertainment`, `sports`, `hackerNews`, `polymarket`, `weather`.

## Who should use it

Any local agent or script that needs a deduplicated feed of what is actually new this cycle — a newsroom pipeline, a social drafter, or a briefing job. Start here before open-web search, and corroborate anything you publish with at least one additional named HTTPS source. If `/v1/fresh` returns zero items, the desks are current — do not recycle old stories to fill a quota.
