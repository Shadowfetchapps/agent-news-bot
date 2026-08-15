import Foundation

struct FeedSource {
    var url: String
    var label: String
}

enum FeedRegistry {
    static func feeds(for desk: Desk) -> [FeedSource] {
        switch desk {
        case .breaking:
            return [
                .init(url: "https://feeds.npr.org/1001/rss.xml", label: "NPR"),
                .init(url: "https://feeds.bbci.co.uk/news/rss.xml", label: "BBC"),
                .init(url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", label: "NY Times"),
                .init(url: "https://feeds.apnews.com/rss/apf-topnews", label: "AP")
            ]
        case .politics:
            return [
                .init(url: "https://feeds.npr.org/1014/rss.xml", label: "NPR Politics"),
                .init(url: "https://feeds.bbci.co.uk/news/politics/rss.xml", label: "BBC Politics"),
                .init(url: "https://rss.nytimes.com/services/xml/rss/nyt/Politics.xml", label: "NY Times"),
                .init(url: "https://rss.politico.com/politics-news.xml", label: "Politico"),
                .init(url: "https://thehill.com/feed/", label: "The Hill")
            ]
        case .world:
            return [
                .init(url: "https://feeds.bbci.co.uk/news/world/rss.xml", label: "BBC World"),
                .init(url: "https://feeds.npr.org/1004/rss.xml", label: "NPR World"),
                .init(url: "https://rss.nytimes.com/services/xml/rss/nyt/World.xml", label: "NY Times World"),
                .init(url: "https://www.aljazeera.com/xml/rss/all.xml", label: "Al Jazeera"),
                .init(url: "https://rss.dw.com/rdf/rss-en-all", label: "Deutsche Welle"),
                .init(url: "https://feeds.apnews.com/rss/apf-intlnews", label: "AP World")
            ]
        case .business:
            return [
                .init(url: "https://feeds.npr.org/1006/rss.xml", label: "NPR Business"),
                .init(url: "https://feeds.bbci.co.uk/news/business/rss.xml", label: "BBC Business"),
                .init(url: "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664", label: "CNBC"),
                .init(url: "https://finance.yahoo.com/news/rssindex", label: "Yahoo Finance"),
                .init(url: "https://feeds.content.dowjones.io/public/rss/mw_realtimeheadlines", label: "MarketWatch")
            ]
        case .tech:
            return [
                .init(url: "https://feeds.arstechnica.com/arstechnica/index", label: "Ars Technica"),
                .init(url: "https://www.theverge.com/rss/index.xml", label: "The Verge"),
                .init(url: "https://feeds.feedburner.com/TechCrunch", label: "TechCrunch"),
                .init(url: "https://www.wired.com/feed/rss", label: "Wired"),
                .init(url: "https://feeds.bbci.co.uk/news/technology/rss.xml", label: "BBC Technology"),
                .init(url: "https://www.theregister.com/headlines.atom", label: "The Register")
            ]
        case .ai:
            return [
                .init(url: "https://techcrunch.com/category/artificial-intelligence/feed/", label: "TechCrunch AI"),
                .init(url: "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", label: "Verge AI"),
                .init(url: "https://www.technologyreview.com/feed/", label: "MIT Tech Review"),
                .init(url: "https://simonwillison.net/atom/everything/", label: "Simon Willison"),
                .init(url: "https://huggingface.co/blog/feed.xml", label: "Hugging Face"),
                .init(url: "https://blog.google/technology/ai/rss/", label: "Google AI"),
                .init(url: "https://blogs.nvidia.com/blog/category/generative-ai/feed/", label: "NVIDIA AI"),
                .init(url: "https://venturebeat.com/category/ai/feed/", label: "VentureBeat AI"),
                .init(url: "https://rss.arxiv.org/rss/cs.AI", label: "arXiv cs.AI"),
                .init(url: "https://rss.arxiv.org/rss/cs.LG", label: "arXiv cs.LG"),
                .init(url: "https://www.wired.com/feed/tag/ai/latest/rss", label: "Wired AI")
            ]
        case .science:
            return [
                .init(url: "https://feeds.npr.org/1007/rss.xml", label: "NPR Science"),
                .init(url: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", label: "BBC Science"),
                .init(url: "https://rss.nytimes.com/services/xml/rss/nyt/Science.xml", label: "NY Times Science"),
                .init(url: "https://www.sciencedaily.com/rss/all.xml", label: "ScienceDaily"),
                .init(url: "https://www.nasa.gov/rss/dyn/breaking_news.rss", label: "NASA")
            ]
        case .health:
            return [
                .init(url: "https://feeds.npr.org/1128/rss.xml", label: "NPR Health"),
                .init(url: "https://feeds.bbci.co.uk/news/health/rss.xml", label: "BBC Health"),
                .init(url: "https://rss.nytimes.com/services/xml/rss/nyt/Health.xml", label: "NY Times Health"),
                .init(url: "https://www.medicalnewstoday.com/rss", label: "Medical News Today")
            ]
        case .entertainment:
            return [
                .init(url: "https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml", label: "BBC Entertainment"),
                .init(url: "https://variety.com/feed/", label: "Variety"),
                .init(url: "https://deadline.com/feed/", label: "Deadline"),
                .init(url: "https://www.hollywoodreporter.com/feed/", label: "Hollywood Reporter")
            ]
        case .sports:
            return [
                .init(url: "https://feeds.npr.org/1055/rss.xml", label: "NPR Sports"),
                .init(url: "https://feeds.bbci.co.uk/sport/rss.xml", label: "BBC Sport"),
                .init(url: "https://www.espn.com/espn/rss/news", label: "ESPN"),
                .init(url: "https://sports.yahoo.com/rss/", label: "Yahoo Sports")
            ]
        case .markets, .hackerNews, .polymarket, .weather:
            return []
        }
    }
}
