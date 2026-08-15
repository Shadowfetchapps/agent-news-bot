from __future__ import annotations

import re

from .config import DESK_TAGS

SKIP = {
    "about", "after", "their", "there", "these", "those", "would", "could",
    "should", "might", "latest", "report", "reports", "update", "into",
    "from", "with", "that", "this", "have", "will", "your", "what", "when",
    "where", "which", "while", "over", "under", "more", "than", "been",
    "were", "they", "them", "just", "also", "says", "said",
}

KNOWN = {
    "ai": "AI", "llm": "LLM", "gpt": "GPT", "openai": "OpenAI",
    "nvidia": "NVIDIA", "apple": "Apple", "google": "Google",
    "microsoft": "Microsoft", "meta": "Meta", "tesla": "Tesla",
    "fed": "Fed", "sec": "SEC", "fcc": "FCC", "nasa": "NASA",
    "bbc": "BBC", "npr": "NPR", "cnn": "CNN", "nyc": "NYC",
    "usa": "USA", "uk": "UK", "eu": "EU", "un": "UN",
    "ipo": "IPO", "etf": "ETF", "btc": "BTC", "eth": "ETH",
    "spacex": "SpaceX",
}


def tags(desk: str, title: str, extra: list[str] | None = None) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []

    def add(tag: str) -> None:
        key = tag.lower()
        if key in seen:
            return
        seen.add(key)
        out.append(tag if tag.startswith("#") or tag.startswith("$") else f"#{tag}")

    for tag in DESK_TAGS.get(desk, []):
        add(tag)
    for tag in extra or []:
        add(tag)
    for token in _keywords(title):
        if len(out) >= 6:
            break
        add(token)
    return out[:6]


def tweet(title: str, url: str, tag_list: list[str]) -> tuple[str, int]:
    tag_str = " ".join(tag_list)
    url_cost = 23
    limit = 280
    fixed = 1 + url_cost + (0 if not tag_str else 1 + len(tag_str))
    comment = title.strip()
    available = max(0, limit - fixed)
    if len(comment) > available:
        comment = comment[: max(0, available - 1)].rstrip() + "…"
    parts = [p for p in (comment, url, tag_str) if p]
    text = " ".join(parts)
    counted = len(comment) + 1 + url_cost + (0 if not tag_str else 1 + len(tag_str))
    return text, counted


def _keywords(title: str) -> list[str]:
    words = re.findall(r"[A-Za-z0-9]+", title)
    found: list[str] = []
    for word in words:
        lower = word.lower()
        if lower in KNOWN:
            found.append(f"#{KNOWN[lower]}")
            continue
        if len(word) >= 5 and word[0].isupper() and lower not in SKIP:
            found.append(f"#{word}")
    return found
