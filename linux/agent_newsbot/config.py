from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

HOME = Path(os.environ.get("AGENT_NEWSBOT_HOME", os.path.expanduser("~/.local/share/agent-news-bot")))
SHARED = Path(os.environ.get("AGENT_NEWSBOT_SHARED", str(HOME / "shared")))
PORT = int(os.environ.get("AGENT_NEWSBOT_PORT", "18765"))
LOOKBACK_HOURS = float(os.environ.get("AGENT_NEWSBOT_LOOKBACK_HOURS", "12"))
MAX_PER_DESK = int(os.environ.get("AGENT_NEWSBOT_MAX_PER_DESK", "20"))
WEATHER_CITY = os.environ.get("AGENT_NEWSBOT_WEATHER_CITY", "New York")
MARKET_SYMBOLS = os.environ.get(
    "AGENT_NEWSBOT_SYMBOLS",
    "^GSPC,^DJI,^IXIC,SPY,QQQ,AAPL,MSFT,NVDA,GOOGL,AMZN,META,TSLA,BTC-USD,ETH-USD",
)
FETCH_INTERVAL = int(os.environ.get("AGENT_NEWSBOT_FETCH_INTERVAL", "900"))
USER_AGENT = (
    "AgentNewsBot/1.0 (+https://github.com/Realbobcorbin/agent-news-bot; Linux) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
)

DESK_TITLES = {
    "breaking": "Breaking",
    "politics": "Politics",
    "world": "World",
    "business": "Business",
    "markets": "Markets",
    "tech": "Tech",
    "ai": "AI",
    "science": "Science",
    "health": "Health",
    "entertainment": "Entertainment",
    "sports": "Sports",
    "hackerNews": "Hacker News",
    "polymarket": "Polymarket",
    "weather": "Weather",
}

DESK_TAGS = {
    "breaking": ["#Breaking", "#News"],
    "politics": ["#Politics"],
    "world": ["#WorldNews"],
    "business": ["#Business"],
    "markets": ["#Markets", "#Stocks"],
    "tech": ["#Technology"],
    "ai": ["#AI", "#ArtificialIntelligence"],
    "science": ["#Science"],
    "health": ["#Health"],
    "entertainment": ["#Entertainment"],
    "sports": ["#Sports"],
    "hackerNews": ["#HackerNews"],
    "polymarket": ["#Polymarket", "#PredictionMarkets"],
    "weather": ["#Weather"],
}

RSS_FEEDS = {
    "breaking": [
        ("https://feeds.npr.org/1001/rss.xml", "NPR"),
        ("https://feeds.bbci.co.uk/news/rss.xml", "BBC"),
        ("https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", "NY Times"),
        ("https://feeds.apnews.com/rss/apf-topnews", "AP"),
    ],
    "politics": [
        ("https://feeds.npr.org/1014/rss.xml", "NPR Politics"),
        ("https://feeds.bbci.co.uk/news/politics/rss.xml", "BBC Politics"),
        ("https://rss.nytimes.com/services/xml/rss/nyt/Politics.xml", "NY Times"),
        ("https://rss.politico.com/politics-news.xml", "Politico"),
        ("https://thehill.com/feed/", "The Hill"),
    ],
    "world": [
        ("https://feeds.bbci.co.uk/news/world/rss.xml", "BBC World"),
        ("https://feeds.npr.org/1004/rss.xml", "NPR World"),
        ("https://rss.nytimes.com/services/xml/rss/nyt/World.xml", "NY Times World"),
        ("https://www.aljazeera.com/xml/rss/all.xml", "Al Jazeera"),
        ("https://rss.dw.com/rdf/rss-en-all", "Deutsche Welle"),
        ("https://feeds.apnews.com/rss/apf-intlnews", "AP World"),
    ],
    "business": [
        ("https://feeds.npr.org/1006/rss.xml", "NPR Business"),
        ("https://feeds.bbci.co.uk/news/business/rss.xml", "BBC Business"),
        ("https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664", "CNBC"),
        ("https://finance.yahoo.com/news/rssindex", "Yahoo Finance"),
        ("https://feeds.content.dowjones.io/public/rss/mw_realtimeheadlines", "MarketWatch"),
    ],
    "tech": [
        ("https://feeds.arstechnica.com/arstechnica/index", "Ars Technica"),
        ("https://www.theverge.com/rss/index.xml", "The Verge"),
        ("https://feeds.feedburner.com/TechCrunch", "TechCrunch"),
        ("https://www.wired.com/feed/rss", "Wired"),
        ("https://feeds.bbci.co.uk/news/technology/rss.xml", "BBC Technology"),
        ("https://www.theregister.com/headlines.atom", "The Register"),
    ],
    "ai": [
        ("https://techcrunch.com/category/artificial-intelligence/feed/", "TechCrunch AI"),
        ("https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", "Verge AI"),
        ("https://www.technologyreview.com/feed/", "MIT Tech Review"),
        ("https://simonwillison.net/atom/everything/", "Simon Willison"),
        ("https://huggingface.co/blog/feed.xml", "Hugging Face"),
        ("https://blog.google/technology/ai/rss/", "Google AI"),
        ("https://blogs.nvidia.com/blog/category/generative-ai/feed/", "NVIDIA AI"),
        ("https://venturebeat.com/category/ai/feed/", "VentureBeat AI"),
        ("https://rss.arxiv.org/rss/cs.AI", "arXiv cs.AI"),
        ("https://rss.arxiv.org/rss/cs.LG", "arXiv cs.LG"),
        ("https://www.wired.com/feed/tag/ai/latest/rss", "Wired AI"),
    ],
    "science": [
        ("https://feeds.npr.org/1007/rss.xml", "NPR Science"),
        ("https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", "BBC Science"),
        ("https://rss.nytimes.com/services/xml/rss/nyt/Science.xml", "NY Times Science"),
        ("https://www.sciencedaily.com/rss/all.xml", "ScienceDaily"),
        ("https://www.nasa.gov/rss/dyn/breaking_news.rss", "NASA"),
    ],
    "health": [
        ("https://feeds.npr.org/1128/rss.xml", "NPR Health"),
        ("https://feeds.bbci.co.uk/news/health/rss.xml", "BBC Health"),
        ("https://rss.nytimes.com/services/xml/rss/nyt/Health.xml", "NY Times Health"),
        ("https://www.medicalnewstoday.com/rss", "Medical News Today"),
    ],
    "entertainment": [
        ("https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml", "BBC Entertainment"),
        ("https://variety.com/feed/", "Variety"),
        ("https://deadline.com/feed/", "Deadline"),
        ("https://www.hollywoodreporter.com/feed/", "Hollywood Reporter"),
    ],
    "sports": [
        ("https://feeds.npr.org/1055/rss.xml", "NPR Sports"),
        ("https://feeds.bbci.co.uk/sport/rss.xml", "BBC Sport"),
        ("https://www.espn.com/espn/rss/news", "ESPN"),
        ("https://sports.yahoo.com/rss/", "Yahoo Sports"),
    ],
}

RSS_DESKS = list(RSS_FEEDS)
ALL_DESKS = RSS_DESKS + ["markets", "hackerNews", "polymarket", "weather"]


@dataclass
class Article:
    id: str
    desk: str
    title: str
    url: str
    source: str
    published: str | None
    summary: str
    tweet: str
    tweet_chars: int
    hashtags: list[str]
    extra: dict = field(default_factory=dict)

    def as_dict(self) -> dict:
        return {
            "id": self.id,
            "desk": self.desk,
            "title": self.title,
            "url": self.url,
            "source": self.source,
            "published": self.published or "",
            "summary": self.summary,
            "tweet": self.tweet,
            "tweet_chars": self.tweet_chars,
            "hashtags": self.hashtags,
            "category": DESK_TITLES.get(self.desk, self.desk),
        }


@dataclass
class DeskResult:
    desk: str
    articles: list[Article]
    skipped_old: int = 0
    skipped_dup: int = 0
    source_errors: list[str] = field(default_factory=list)
