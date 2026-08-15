from __future__ import annotations

import json
import logging
import secrets
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from .config import FETCH_INTERVAL, HOME, LOOKBACK_HOURS, PORT, SHARED
from .engine import fetch_all
from .store import FreshnessStore

log = logging.getLogger("agent_newsbot")


class NewsState:
    def __init__(self) -> None:
        HOME.mkdir(parents=True, exist_ok=True)
        SHARED.mkdir(parents=True, exist_ok=True)
        self.store = FreshnessStore(HOME / "seen.sqlite")
        self.token_path = HOME / "export" / "bridge.token"
        self.latest_path = SHARED / "latest.json"
        self.token = self._load_or_create_token()
        self.snapshot: dict = {
            "fetched_at": None,
            "total_articles": 0,
            "articles": [],
            "desks": [],
            "categories": {},
        }
        self.lock = threading.Lock()
        self.fetching = False
        self._load_snapshot()

    def _load_snapshot(self) -> None:
        if self.latest_path.exists():
            try:
                self.snapshot = json.loads(self.latest_path.read_text())
            except Exception:
                pass

    def _load_or_create_token(self) -> str:
        path = self.token_path
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            token = path.read_text().strip()
            if len(token) >= 16:
                return token
        token = secrets.token_hex(16)
        path.write_text(token + "\n")
        path.chmod(0o640)
        return token

    def refresh(self) -> dict:
        with self.lock:
            if self.fetching:
                return self.snapshot
            self.fetching = True
            previous = self.snapshot
        try:
            snapshot = fetch_all(self.store)
            snapshot = self._keep_live_desks(previous, snapshot)
            with self.lock:
                self.snapshot = snapshot
            tmp = self.latest_path.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(snapshot, indent=2))
            tmp.replace(self.latest_path)
            self.latest_path.chmod(0o640)
            log.info("fresh fetch: %s articles", snapshot.get("total_articles"))
            return snapshot
        finally:
            with self.lock:
                self.fetching = False

    def _keep_live_desks(self, previous: dict, snapshot: dict) -> dict:
        """If a desk has no new items, keep still-fresh articles from the last batch."""
        cutoff = datetime.now(timezone.utc) - timedelta(hours=LOOKBACK_HOURS)
        new_by_desk = {row["desk"]: row.get("fresh", 0) for row in snapshot.get("desks") or []}
        kept: list[dict] = list(snapshot.get("articles") or [])
        seen = {item["id"] for item in kept}
        for item in previous.get("articles") or []:
            if new_by_desk.get(item.get("desk"), 1) != 0:
                continue
            if item.get("id") in seen:
                continue
            published = item.get("published") or ""
            try:
                dt = datetime.fromisoformat(published.replace("Z", "+00:00"))
            except Exception:
                dt = datetime.now(timezone.utc)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            if dt >= cutoff:
                kept.append(item)
                seen.add(item["id"])
        kept.sort(key=lambda item: item.get("published") or "", reverse=True)
        snapshot["articles"] = kept
        snapshot["total_articles"] = len(kept)
        categories: dict[str, list] = {}
        for item in kept:
            title = item.get("category") or item.get("desk")
            categories.setdefault(title, []).append(item)
        snapshot["categories"] = categories
        return snapshot


STATE = NewsState()


class Handler(BaseHTTPRequestHandler):
    server_version = "AgentNewsBot/1.0"

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        log.info("%s - " + fmt, self.address_string(), *args)

    def _send(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        auth = self.headers.get("Authorization", "")
        alt = self.headers.get("X-Agent-Token", "")
        return auth == f"Bearer {STATE.token}" or alt == STATE.token

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/health":
            self._send(200, {"ok": True, "app": "Agent News Bot", "bridge": f"http://127.0.0.1:{PORT}"})
            return
        if not self._authorized():
            self._send(401, {"error": "bearer token required"})
            return
        qs = parse_qs(parsed.query)
        if path.startswith("/v1/fresh"):
            with STATE.lock:
                articles = list(STATE.snapshot.get("articles") or [])
            desk = (qs.get("desk") or [None])[0]
            if desk:
                articles = [a for a in articles if a.get("desk") == desk]
            limit = int((qs.get("limit") or ["100"])[0])
            articles = articles[:limit]
            self._send(200, {"count": len(articles), "articles": articles})
            return
        if path.startswith("/v1/desks"):
            with STATE.lock:
                desks = STATE.snapshot.get("desks") or []
            self._send(200, {"desks": desks})
            return
        if path.startswith("/v1/status"):
            with STATE.lock:
                snap = STATE.snapshot
            self._send(
                200,
                {
                    "ok": True,
                    "fresh": snap.get("total_articles", 0),
                    "fetched_at": snap.get("fetched_at"),
                    "fetching": STATE.fetching,
                },
            )
            return
        self._send(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if not self._authorized():
            self._send(401, {"error": "bearer token required"})
            return
        if parsed.path == "/v1/fetch":
            snapshot = STATE.refresh()
            self._send(200, {"ok": True, "total_articles": snapshot.get("total_articles", 0)})
            return
        self._send(404, {"error": "not found"})


def loop_fetch() -> None:
    latest = STATE.latest_path
    if latest.exists():
        age = time.time() - latest.stat().st_mtime
        if age < FETCH_INTERVAL:
            time.sleep(FETCH_INTERVAL - age)
    while True:
        try:
            STATE.refresh()
        except Exception:
            log.exception("periodic fetch failed")
        time.sleep(FETCH_INTERVAL)


def serve() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    threading.Thread(target=loop_fetch, daemon=True, name="fetch-loop").start()
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    log.info("Agent News Bot listening on http://127.0.0.1:%s", PORT)
    httpd.serve_forever()
