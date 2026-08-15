# Agent News Bot

A local-first **news desk for AI agents**. Agent News Bot scans 14 topic "desks" from public,
key-free sources, filters everything down to *only the stories you have not seen before*, generates
a ready-to-post tweet and hashtags for each item, and serves the fresh batch over a small
token-authenticated HTTP API bound to `127.0.0.1`. An agent, script, or newsroom pipeline can ask
"what's actually new right now?" and get a clean JSON answer instead of re-scraping the open web.

It ships as **two parallel implementations of the same design**:

- **macOS app** (`Sources/`) — a native SwiftUI desktop newsroom with a dark UI, menu-bar extra,
  JSON exports, and optional one-click handoff to local agent runtimes.
- **Linux service** (`linux/agent_newsbot/`) — a headless Python daemon (systemd-friendly) with a
  periodic fetch loop and a `latest.json` file snapshot for file-based consumers.

Both speak the **same HTTP bridge API** and share the same freshness model, so an agent written
against one works against the other.

---

## Table of contents

- [Who it's for](#who-its-for)
- [Key features](#key-features)
- [The 14 desks & their sources](#the-14-desks--their-sources)
- [Architecture](#architecture)
- [The freshness model](#the-freshness-model)
- [The bridge API](#the-bridge-api)
- [Privacy & data model](#privacy--data-model)
- [Build & run — macOS](#build--run--macos)
- [Build & run — Linux](#build--run--linux)
- [Configuration](#configuration)
- [Optional agent integrations](#optional-agent-integrations-macos)
- [Screenshots](#screenshots)
- [Project layout](#project-layout)
- [Contributing](#contributing)
- [License](#license)

---

## Who it's for

- **Agent / automation authors** who need a deduplicated, time-bounded feed of current headlines
  and want to call one localhost endpoint instead of maintaining scrapers.
- **Newsroom / social pipelines** that must avoid re-posting the same story: the built-in freshness
  ledger guarantees each item is served once.
- **Anyone who wants a private, keyless news aggregator** on their own machine — no accounts, no API
  keys, no third-party analytics.

## Key features

- **14 desks** spanning general news, finance, tech/AI, prediction markets, and weather.
- **Key-free sources.** Every source is a public RSS/Atom feed or an open JSON API — no source
  requires an API key or login.
- **"Only what's new."** A SQLite freshness ledger dedupes by canonical URL and enforces a lookback
  window (default 12h). Ask twice and you won't get the same story twice.
- **Social-ready output.** Each article carries a pre-composed `tweet` (280-char aware, counts the
  `t.co` 23-char URL cost) and a `hashtags` list built from desk tags + keyword extraction.
- **Token-authenticated localhost bridge.** `GET /v1/fresh`, `/v1/desks`, `/v1/status`, and
  `POST /v1/fetch`, bound to `127.0.0.1` only, behind a bearer token that is generated on first run.
- **Two runtimes, one contract.** Native macOS app *and* headless Linux daemon expose the same API.
- **Live-desk carry-over (Linux).** If a desk produces nothing new this cycle, still-fresh items from
  the previous batch are retained so the desk never looks empty while it's simply current.

## The 14 desks & their sources

| Desk | Source(s) | API key? |
|------|-----------|----------|
| `breaking` | NPR, BBC, NY Times, AP (RSS) | none |
| `politics` | NPR, BBC, NY Times, Politico, The Hill (RSS) | none |
| `world` | BBC, NPR, NY Times, Al Jazeera, Deutsche Welle, AP (RSS) | none |
| `business` | NPR, BBC, CNBC, Yahoo Finance, MarketWatch (RSS) | none |
| `tech` | Ars Technica, The Verge, TechCrunch, Wired, BBC, The Register (RSS) | none |
| `ai` | TechCrunch AI, Verge AI, MIT Tech Review, Simon Willison, Hugging Face, Google AI, NVIDIA, VentureBeat, arXiv cs.AI/cs.LG, Wired AI (RSS) | none |
| `science` | NPR, BBC, NY Times, ScienceDaily, NASA (RSS) | none |
| `health` | NPR, BBC, NY Times, Medical News Today (RSS) | none |
| `entertainment` | BBC, Variety, Deadline, Hollywood Reporter (RSS) | none |
| `sports` | NPR, BBC Sport, ESPN, Yahoo Sports (RSS) | none |
| `markets` | Yahoo Finance chart API (configurable symbol list) | none |
| `hackerNews` | Hacker News Firebase API (new + top stories) | none |
| `polymarket` | Polymarket Gamma API (events + markets, by 24h volume) | none |
| `weather` | Open-Meteo geocoding + forecast API | none |

> The exact feed URLs live in `linux/agent_newsbot/config.py` (Python) and `Sources/Feeds.swift`
> (Swift). Add or remove feeds by editing those tables.

## Architecture

```
                 ┌────────────────────────────────────────────┐
                 │  Fetch engine (per desk, run concurrently)   │
                 │  RSS/Atom · HN Firebase · Polymarket Gamma   │
                 │  Yahoo Finance · Open-Meteo                  │
                 └───────────────┬──────────────────────────────┘
                                 │ normalize → dedupe → tag → tweet
                                 ▼
                 ┌────────────────────────────────────────────┐
                 │  Freshness ledger (SQLite: seen + quotes)    │
                 │  canonical-URL SHA-256 id · lookback window  │
                 └───────────────┬──────────────────────────────┘
                                 │ fresh batch (snapshot)
                                 ▼
        ┌────────────────────────┴────────────────────────┐
        │  Bridge  (HTTP on 127.0.0.1, bearer-token auth)   │
        │  GET /health  /v1/fresh  /v1/desks  /v1/status    │
        │  POST /v1/fetch                                    │
        └───────┬─────────────────────────────┬─────────────┘
                │                               │
     macOS: SwiftUI UI + JSON export     Linux: latest.json snapshot file
                │                               │
                ▼                               ▼
         agents / scripts read the same JSON contract
```

**macOS implementation (`Sources/`, Swift/SwiftUI):**

- `App.swift` / `ContentView.swift` / `SettingsView.swift` — the desktop UI, menu-bar extra, and
  keyboard commands (⌘R fetch, ⇧⌘H send to Hermes).
- `Engine.swift` — orchestrates concurrent per-desk fetches, merges/sorts, marks items seen, exports
  JSON, and creates/loads the bridge token.
- `AgentBridge.swift` — a tiny hand-rolled `sockaddr_in` HTTP server bound to `127.0.0.1`, serving the
  bridge API.
- `RSSClient`/`HNClient`/`PolymarketClient`/`MarketsClient`/`WeatherClient` — one fetcher per source
  family; `Freshness.swift` is the SQLite ledger; `Hashtagger.swift` builds tags + tweets.
- `SettingsStore.swift` — `UserDefaults` for config, **Keychain** for optional integration tokens.
- `HermesClient.swift` / `OpenClawClient.swift` — optional handoff to local agent runtimes.

**Linux implementation (`linux/agent_newsbot/`, Python 3, stdlib + `feedparser` + `requests`):**

- `server.py` — `ThreadingHTTPServer` on `127.0.0.1`, bearer-token auth, background fetch loop,
  atomic `latest.json` writes.
- `engine.py` — the concurrent fetchers (`ThreadPoolExecutor`), one per desk family.
- `store.py` — the SQLite freshness ledger (`seen` + `quotes` tables), URL canonicalization, date
  parsing, HTML stripping.
- `config.py` — feed tables, desk titles/tags, and all env-var-driven configuration.
- `hashtags.py` — the tag + 280-char tweet composer.
- `__main__.py` — CLI: `serve` | `fetch` | `status`.

## The freshness model

An item's identity is the SHA-256 of its **canonicalized URL** (tracking params like `utm_*`,
`fbclid`, `gclid`, `ocid` stripped; host lowercased; trailing slash removed), truncated to 24 hex
chars. The `seen` table records every id ever served, so an item is emitted **exactly once**. A
configurable **lookback window** (default 12h) drops anything older. For `markets` and `weather`,
a `quotes` table stores the last value so unchanged (or sub-0.15% market) readings are suppressed as
noise. The result: repeated calls return only genuinely new, recent stories, and an empty result
means "the desks are current" — not an error.

## The bridge API

Base URL: `http://127.0.0.1:18765` (port configurable). All endpoints except `/health` require the
bearer token in either an `Authorization: Bearer <token>` header **or** an `X-Agent-Token: <token>`
header. The server binds to loopback only and returns `401` without a valid token.

| Method & path | Auth | Description |
|---------------|------|-------------|
| `GET /health` | no | Liveness probe; returns app name + bridge URL. |
| `GET /v1/fresh?desk=<desk>&limit=<n>` | yes | The current fresh batch. Optional `desk` filter and `limit` (default 100). |
| `GET /v1/desks` | yes | Per-desk counts: fresh, skipped-old, skipped-dup, and source errors. |
| `GET /v1/status` | yes | Snapshot summary: total fresh, `fetched_at`, whether a fetch is in flight. |
| `POST /v1/fetch` | yes | Force an immediate refresh; returns the new total. |

**Example (Linux service, token read from its export file):**

```bash
TOKEN=$(cat "$AGENT_NEWSBOT_HOME/export/bridge.token")
curl -sS -H "Authorization: Bearer $TOKEN" 'http://127.0.0.1:18765/v1/fresh?desk=ai&limit=20'
curl -sS -H "Authorization: Bearer $TOKEN"  'http://127.0.0.1:18765/v1/desks'
curl -sS -X POST -H "Authorization: Bearer $TOKEN" 'http://127.0.0.1:18765/v1/fetch'
```

On macOS the token is shown in **Settings → Bridge** and is written to
`~/Library/Application Support/AgentNewsBot/bridge.token`.

**Article JSON shape:**

```json
{
  "id": "3f2a…", "desk": "ai", "category": "AI",
  "title": "…", "url": "https://…", "source": "TechCrunch AI",
  "published": "2026-08-15T13:04:00+00:00", "summary": "…",
  "tweet": "… https://… #AI #LLM", "tweet_chars": 174,
  "hashtags": ["#AI", "#LLM"]
}
```

## Privacy & data model

- **Local-first.** The service runs on your machine and binds to `127.0.0.1`. Nothing is exposed to
  the network by default.
- **No accounts, no keys, no telemetry.** No source requires credentials; the app phones no analytics
  home.
- **The only persisted state** is a SQLite ledger of story ids/urls/titles you've already seen (for
  dedup) and last market/weather values (for change detection), plus an optional JSON export/snapshot
  of the current batch. No personal data is collected.
- **The bearer token is generated on first run** (macOS: a UUID-derived 32-hex string written 0600;
  Linux: `secrets.token_hex(16)` written 0640) and never leaves the machine. It is **not** in source
  control. Optional integration tokens on macOS are stored in the **Keychain**, not in plists.
- **Content is fetched, not redistributed.** Agent News Bot links to and summarizes third-party
  articles at request time; it stores headlines/links for dedup but is not a content archive. Each
  upstream source's own terms govern use of its feed.

## Build & run — macOS

Requirements: macOS 14+, the Swift toolchain (Xcode or Command Line Tools). No Xcode project and no
third-party Swift packages — it compiles straight from source with `swiftc`.

```bash
./build.sh
open "/Applications/Agent News Bot.app"
```

`build.sh` renders the icon, compiles all `Sources/*.swift` into an app bundle, writes `Info.plist`,
ad-hoc code-signs, and installs to `/Applications`. Launch it, open **Fetch Fresh** (⌘R), and the
bridge starts automatically on `127.0.0.1:18765`.

## Build & run — Linux

Requirements: Python 3.10+, `pip install feedparser requests`.

Run it directly from the package directory:

```bash
cd linux
pip install feedparser requests
python3 -m agent_newsbot serve      # start the API + periodic fetch loop
python3 -m agent_newsbot fetch      # run one fetch, print JSON
python3 -m agent_newsbot status     # show last snapshot counts
```

For a long-running deployment, install it as a systemd service:

```bash
cd linux
sudo ./install.sh          # creates the 'agentnewsbot' user, installs to /opt/agent-news-bot,
                           # state under /var/lib/agent-news-bot, and starts agent-news-bot.service
```

`install.sh` is fully env-var driven — override `PREFIX`, `STATE_DIR`, and `SVC_USER` to install
elsewhere or under a different service account. It builds the unit from
[`agent-news-bot.service.example`](linux/agent-news-bot.service.example) (a plain, path-agnostic
example you can also install by hand). Nothing about any host is baked into these files.

## Configuration

The Linux service is configured entirely through environment variables (all optional):

| Variable | Default | Meaning |
|----------|---------|---------|
| `AGENT_NEWSBOT_HOME` | *(set per install)* | State dir (SQLite ledger + `export/bridge.token`). |
| `AGENT_NEWSBOT_SHARED` | *(set per install)* | Dir where `latest.json` snapshot is written. |
| `AGENT_NEWSBOT_PORT` | `18765` | Bridge port (always bound to `127.0.0.1`). |
| `AGENT_NEWSBOT_LOOKBACK_HOURS` | `12` | Freshness window. |
| `AGENT_NEWSBOT_MAX_PER_DESK` | `20` | Max items kept per desk. |
| `AGENT_NEWSBOT_WEATHER_CITY` | `New York` | City for the weather desk. |
| `AGENT_NEWSBOT_SYMBOLS` | S&P/Dow/Nasdaq/mega-caps/BTC/ETH | Comma-separated market symbols. |
| `AGENT_NEWSBOT_FETCH_INTERVAL` | `900` | Seconds between background fetches. |

On macOS the equivalent settings live in **Settings** (lookback, max per desk, weather city, market
symbols, bridge port, enabled desks) and persist in `UserDefaults`.

## Optional agent integrations (macOS)

The macOS app can hand a selected batch to a **local** agent runtime if one is installed:

- **Hermes** — via a `hermes` CLI on `PATH`, or an OpenAI-compatible chat endpoint (default probe
  `http://127.0.0.1:8642`; optional bearer token stored in Keychain).
- **OpenClaw** — via an `openclaw` CLI, or a local gateway (default `ws://127.0.0.1:18789`).

Both are **optional** and default to localhost. If neither is present, agents can still simply
`GET /v1/fresh` from the bridge — the integrations are a convenience, not a requirement. On launch
the app also writes a small skill descriptor (endpoint + token) to `~/.hermes/skills/` and
`~/.agents/skills/` so a co-located agent can discover the local desk.

## Screenshots

No screenshots are committed to this repository. The only bundled image is the app icon source at
`Resources/icon-1024.png` (used by `build.sh` to generate the `.icns`). If you add screenshots,
place them under a top-level `docs/` or `screenshots/` directory and reference them here.

## Project layout

```
.
├── build.sh                     # macOS build → /Applications
├── Resources/                   # app icon source + icon-drawing script
├── Sources/                     # macOS SwiftUI app (one file per concern)
├── skills/agent-news-bot/       # generic skill descriptor (localhost API)
└── linux/
    ├── agent_newsbot/               # Python package: server, engine, store, config…
    ├── agent-newsbot                # CLI wrapper
    ├── install.sh                   # generic systemd installer (env-var driven)
    ├── agent-news-bot.service.example  # path-agnostic example unit
    └── SKILL.md                     # localhost skill descriptor
```

## Contributing

- Adding a source is usually just a new row in the feed tables (`Sources/Feeds.swift` /
  `linux/agent_newsbot/config.py`) — the RSS path needs no code.
- New source *families* (a non-RSS API) get a small dedicated fetcher mirroring the existing
  `*Client`/`fetch_*` pattern and must respect the freshness ledger.
- Keep the Swift and Python implementations **behaviorally in sync** — they share one API contract.
- Never commit tokens, real hostnames, private paths, or personal data; configuration flows through
  env vars (Linux) and Settings/Keychain (macOS).

## License

Recommended: **MIT** (see repository `LICENSE`). The project uses only system frameworks on macOS and
permissively-licensed Python dependencies (`feedparser`, `requests`), so there is no copyleft
obligation. Agent News Bot fetches and links to third-party news at runtime and redistributes no news
content itself; each upstream source's terms govern use of its feed.
