from __future__ import annotations

import json
import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote

import feedparser
import requests

from . import hashtags
from .config import (
    ALL_DESKS,
    Article,
    DESK_TITLES,
    DeskResult,
    LOOKBACK_HOURS,
    MARKET_SYMBOLS,
    MAX_PER_DESK,
    RSS_FEEDS,
    USER_AGENT,
    WEATHER_CITY,
)
from .store import FreshnessStore, article_id, canonical_url, iso, parse_date, strip_html

log = logging.getLogger("agent_newsbot")
SESSION = requests.Session()
SESSION.headers.update({"User-Agent": USER_AGENT})


def _get(url: str, accept: str = "*/*", timeout: int = 14) -> requests.Response:
    return SESSION.get(url, timeout=timeout, headers={"Accept": accept})


def fetch_rss(desk: str, store: FreshnessStore, lookback: float, limit: int) -> DeskResult:
    collected: list[Article] = []
    errors: list[str] = []
    skipped_old = 0
    skipped_dup = 0
    seen_urls: set[str] = set()
    for url, label in RSS_FEEDS.get(desk, []):
        try:
            resp = _get(url, accept="application/rss+xml, application/atom+xml, application/xml, text/xml, */*")
            resp.raise_for_status()
            parsed = feedparser.parse(resp.content)
            for entry in parsed.entries:
                link = canonical_url(getattr(entry, "link", "") or "")
                if not link or "news.google.com" in link:
                    continue
                if link in seen_urls:
                    skipped_dup += 1
                    continue
                seen_urls.add(link)
                published = parse_date(
                    getattr(entry, "published", None)
                    or getattr(entry, "updated", None)
                    or getattr(entry, "created", None)
                )
                if not store.within_lookback(published, lookback):
                    skipped_old += 1
                    continue
                title = strip_html(getattr(entry, "title", "") or "")
                if not title:
                    continue
                item_id = article_id(link, title)
                if store.has_seen(item_id):
                    skipped_dup += 1
                    continue
                summary = strip_html(getattr(entry, "summary", "") or getattr(entry, "description", "") or "")
                tag_list = hashtags.tags(desk, title)
                tweet, chars = hashtags.tweet(title, link, tag_list)
                collected.append(
                    Article(
                        id=item_id,
                        desk=desk,
                        title=title,
                        url=link,
                        source=label,
                        published=iso(published),
                        summary=summary,
                        tweet=tweet,
                        tweet_chars=chars,
                        hashtags=tag_list,
                    )
                )
        except Exception as exc:
            log.warning("feed failed %s %s: %s", desk, label, exc)
            errors.append(f"{label}: feed unreachable")
        time.sleep(0.12)
    collected.sort(key=lambda a: a.published or "", reverse=True)
    return DeskResult(desk, collected[:limit], skipped_old, skipped_dup, errors)


def fetch_hn(store: FreshnessStore, lookback: float, limit: int) -> DeskResult:
    errors: list[str] = []
    skipped_old = 0
    skipped_dup = 0
    articles: list[Article] = []
    try:
        newest = _get("https://hacker-news.firebaseio.com/v0/newstories.json", accept="application/json").json()
        top = _get("https://hacker-news.firebaseio.com/v0/topstories.json", accept="application/json").json()
        ordered: list[int] = []
        seen: set[int] = set()
        for hid in list(newest[:80]) + list(top[:40]):
            if hid not in seen:
                seen.add(hid)
                ordered.append(hid)
        cutoff = datetime.now(timezone.utc).timestamp() - lookback * 3600
        for hid in ordered:
            if len(articles) >= limit:
                break
            try:
                item = _get(f"https://hacker-news.firebaseio.com/v0/item/{hid}.json", accept="application/json", timeout=8).json()
            except Exception:
                continue
            if not item or item.get("dead") or item.get("deleted"):
                continue
            if item.get("type") not in (None, "story"):
                continue
            title = item.get("title") or ""
            if not title:
                continue
            published_ts = float(item.get("time") or 0)
            if published_ts < cutoff:
                skipped_old += 1
                continue
            url = item.get("url") or f"https://news.ycombinator.com/item?id={hid}"
            if "news.google.com" in url:
                continue
            link = canonical_url(url)
            item_id = article_id(link, f"hn-{hid}")
            if store.has_seen(item_id):
                skipped_dup += 1
                continue
            extra_tags = ["#Trending"] if (item.get("score") or 0) >= 100 else []
            tag_list = hashtags.tags("hackerNews", title, extra_tags)
            tweet, chars = hashtags.tweet(title, link, tag_list)
            articles.append(
                Article(
                    id=item_id,
                    desk="hackerNews",
                    title=title,
                    url=link,
                    source=f"HN · {item.get('by', 'anon')} · {item.get('score', 0)}",
                    published=iso(datetime.fromtimestamp(published_ts, tz=timezone.utc)),
                    summary=strip_html(item.get("text") or ""),
                    tweet=tweet,
                    tweet_chars=chars,
                    hashtags=tag_list,
                    extra={"hn": f"https://news.ycombinator.com/item?id={hid}", "score": str(item.get("score") or 0)},
                )
            )
    except Exception as exc:
        log.warning("hn failed: %s", exc)
        errors.append("Hacker News: API unreachable")
    articles.sort(key=lambda a: a.published or "", reverse=True)
    return DeskResult("hackerNews", articles, skipped_old, skipped_dup, errors)


def _num(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def fetch_polymarket(store: FreshnessStore, lookback: float, limit: int) -> DeskResult:
    errors: list[str] = []
    skipped_dup = 0
    skipped_old = 0
    articles: list[Article] = []
    urls = [
        "https://gamma-api.polymarket.com/events?limit=40&active=true&closed=false&order=volume24hr&ascending=false",
        "https://gamma-api.polymarket.com/markets?limit=40&active=true&closed=false&order=volume24hr&ascending=false",
    ]
    for url in urls:
        try:
            rows = _get(url, accept="application/json").json()
            if not isinstance(rows, list):
                continue
            for row in rows:
                title = str(row.get("title") or row.get("question") or row.get("slug") or "")
                if not title:
                    continue
                slug = str(row.get("slug") or "")
                page = f"https://polymarket.com/event/{slug}" if slug else "https://polymarket.com"
                item_id = article_id(page, slug or title)
                if store.has_seen(item_id):
                    skipped_dup += 1
                    continue
                end = parse_date(str(row.get("endDate") or row.get("end_date_iso") or ""))
                now = datetime.now(timezone.utc)
                if end and end < now and not store.within_lookback(end, lookback):
                    skipped_old += 1
                    continue
                volume = _num(row.get("volume24hr") or row.get("volume"))
                summary_parts = []
                if volume > 0:
                    summary_parts.append(f"24h volume ${volume:.0f}")
                extra = ["#HotMarket"] if volume >= 100_000 else []
                tag_list = hashtags.tags("polymarket", title, extra)
                tweet, chars = hashtags.tweet(title, page, tag_list)
                articles.append(
                    Article(
                        id=item_id,
                        desk="polymarket",
                        title=title,
                        url=page,
                        source="Polymarket",
                        published=iso(parse_date(str(row.get("startDate") or row.get("createdAt") or "")) or now),
                        summary=" · ".join(summary_parts),
                        tweet=tweet,
                        tweet_chars=chars,
                        hashtags=tag_list,
                        extra={"volume": f"{volume:.0f}"},
                    )
                )
        except Exception as exc:
            log.warning("polymarket failed: %s", exc)
            errors.append("Polymarket: API unreachable")
    unique: list[Article] = []
    seen: set[str] = set()
    for article in articles:
        if article.id in seen:
            continue
        seen.add(article.id)
        unique.append(article)
    unique.sort(key=lambda a: float(a.extra.get("volume") or 0), reverse=True)
    return DeskResult("polymarket", unique[:limit], skipped_old, skipped_dup, errors)


SYMBOL_NAMES = {"^GSPC": "S&P 500", "^DJI": "Dow", "^IXIC": "Nasdaq"}


def fetch_markets(store: FreshnessStore, symbols: str, limit: int) -> DeskResult:
    errors: list[str] = []
    skipped_dup = 0
    articles: list[Article] = []
    for symbol in [s.strip().upper() for s in symbols.split(",") if s.strip()]:
        encoded = quote(symbol, safe="")
        url = f"https://query1.finance.yahoo.com/v8/finance/chart/{encoded}?interval=1d&range=5d"
        try:
            payload = _get(url, accept="application/json", timeout=12).json()
            meta = payload["chart"]["result"][0]["meta"]
            price = _num(meta.get("regularMarketPrice"))
            prev = _num(meta.get("chartPreviousClose")) or _num(meta.get("previousClose"))
            if price <= 0:
                continue
            change = (price - prev) / prev if prev else 0.0
            snapshot = f"{price:.4f}|{change:.5f}"
            last = store.last_quote(symbol)
            if last == snapshot:
                skipped_dup += 1
                continue
            if abs(change) < 0.0015 and last is not None:
                skipped_dup += 1
                continue
            store.save_quote(symbol, snapshot)
            name = SYMBOL_NAMES.get(symbol) or meta.get("shortName") or meta.get("longName") or "Yahoo Finance"
            sign = "+" if change >= 0 else ""
            title = f"{name} {price:.2f} {sign}{change * 100:.2f}%"
            page = f"https://finance.yahoo.com/quote/{encoded}"
            item_id = article_id(page + snapshot, f"mkt-{symbol}-{snapshot}")
            cash = name.replace("^", "").replace(" ", "")
            tag_list = hashtags.tags("markets", title, [f"${cash}"])
            tweet, chars = hashtags.tweet(title, page, tag_list)
            currency = meta.get("currency") or "USD"
            articles.append(
                Article(
                    id=item_id,
                    desk="markets",
                    title=title,
                    url=page,
                    source=str(name),
                    published=iso(datetime.now(timezone.utc)),
                    summary=f"{currency} · prior close {prev:.2f}",
                    tweet=tweet,
                    tweet_chars=chars,
                    hashtags=tag_list,
                    extra={"symbol": symbol, "change": f"{change:.4f}"},
                )
            )
        except Exception as exc:
            log.warning("market %s failed: %s", symbol, exc)
            errors.append(f"{symbol}: quote failed")
    articles.sort(key=lambda a: abs(float(a.extra.get("change") or 0)), reverse=True)
    return DeskResult("markets", articles[:limit], 0, skipped_dup, errors)


WX = {
    0: "Clear",
    1: "Mostly clear",
    2: "Mostly clear",
    3: "Overcast",
    45: "Fog",
    48: "Fog",
    51: "Drizzle",
    53: "Drizzle",
    55: "Drizzle",
    61: "Rain",
    63: "Rain",
    65: "Rain",
    71: "Snow",
    73: "Snow",
    75: "Snow",
    80: "Showers",
    81: "Showers",
    82: "Showers",
    95: "Thunderstorm",
    96: "Thunderstorm",
    99: "Thunderstorm",
}


def fetch_weather(store: FreshnessStore, city: str) -> DeskResult:
    query = city.strip()
    if not query:
        return DeskResult("weather", [], 0, 0, ["Set AGENT_NEWSBOT_WEATHER_CITY"])
    try:
        geo = _get(
            f"https://geocoding-api.open-meteo.com/v1/search?name={quote(query)}&count=1&language=en&format=json",
            accept="application/json",
        ).json()
        first = (geo.get("results") or [None])[0]
        if not first:
            return DeskResult("weather", [], 0, 0, [f"Could not geocode {query}"])
        lat, lon = first["latitude"], first["longitude"]
        place = ", ".join(p for p in [first.get("name"), first.get("admin1"), first.get("country")] if p)
        wx = _get(
            "https://api.open-meteo.com/v1/forecast"
            f"?latitude={lat}&longitude={lon}"
            "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m"
            "&daily=temperature_2m_max,temperature_2m_min"
            "&forecast_days=2&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto",
            accept="application/json",
        ).json()
        current = wx.get("current") or {}
        daily = wx.get("daily") or {}
        temp = _num(current.get("temperature_2m"))
        feel = _num(current.get("apparent_temperature"))
        wind = _num(current.get("wind_speed_10m"))
        code = int(_num(current.get("weather_code")))
        high = (daily.get("temperature_2m_max") or [temp])[0]
        low = (daily.get("temperature_2m_min") or [temp])[0]
        payload = f"{temp:.0f}|{code}|{high:.0f}"
        key = f"weather:{place}"
        if store.last_quote(key) == payload:
            return DeskResult("weather", [], 0, 1, [])
        store.save_quote(key, payload)
        condition = WX.get(code, "Mixed")
        title = f"{place}: {int(temp)}°F {condition}"
        summary = f"Feels like {int(feel)}° · Wind {int(wind)} mph · Today {int(high)}/{int(low)}°F"
        page = f"https://open-meteo.com/en/forecast?latitude={lat}&longitude={lon}"
        item_id = article_id(page + payload, f"wx-{place}-{payload}")
        tag_list = hashtags.tags("weather", title, ["#Forecast"])
        tweet, chars = hashtags.tweet(title, page, tag_list)
        article = Article(
            id=item_id,
            desk="weather",
            title=title,
            url=page,
            source="Open-Meteo",
            published=iso(datetime.now(timezone.utc)),
            summary=summary,
            tweet=tweet,
            tweet_chars=chars,
            hashtags=tag_list,
            extra={"city": place},
        )
        return DeskResult("weather", [article], 0, 0, [])
    except Exception as exc:
        log.warning("weather failed: %s", exc)
        return DeskResult("weather", [], 0, 0, ["Weather: Open-Meteo unreachable"])


def fetch_desk(desk: str, store: FreshnessStore) -> DeskResult:
    if desk == "hackerNews":
        return fetch_hn(store, LOOKBACK_HOURS, MAX_PER_DESK)
    if desk == "polymarket":
        return fetch_polymarket(store, LOOKBACK_HOURS, MAX_PER_DESK)
    if desk == "markets":
        return fetch_markets(store, MARKET_SYMBOLS, MAX_PER_DESK)
    if desk == "weather":
        return fetch_weather(store, WEATHER_CITY)
    return fetch_rss(desk, store, LOOKBACK_HOURS, MAX_PER_DESK)


def fetch_all(store: FreshnessStore) -> dict[str, Any]:
    started = datetime.now(timezone.utc)
    results: list[DeskResult] = []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(fetch_desk, desk, store): desk for desk in ALL_DESKS}
        for fut in as_completed(futures):
            results.append(fut.result())
    results.sort(key=lambda r: DESK_TITLES.get(r.desk, r.desk))
    articles: list[Article] = []
    for result in results:
        articles.extend(result.articles)
        for article in result.articles:
            store.mark(article.id, article.url, article.title, article.desk)
    articles.sort(key=lambda a: a.published or "", reverse=True)
    scanned = sum(len(r.articles) + r.skipped_old + r.skipped_dup for r in results)
    return {
        "fetched_at": iso(started),
        "finished_at": iso(datetime.now(timezone.utc)),
        "lookback_hours": LOOKBACK_HOURS,
        "total_articles": len(articles),
        "scanned": scanned,
        "articles": [a.as_dict() for a in articles],
        "desks": [
            {
                "desk": r.desk,
                "title": DESK_TITLES.get(r.desk, r.desk),
                "fresh": len(r.articles),
                "skipped_old": r.skipped_old,
                "skipped_dup": r.skipped_dup,
                "errors": r.source_errors,
            }
            for r in results
        ],
        "categories": {
            DESK_TITLES.get(r.desk, r.desk): [a.as_dict() for a in r.articles] for r in results
        },
    }
