import Foundation

enum RSSClient {
    static func fetch(desk: Desk, lookbackHours: Double, maxItems: Int, store: FreshnessStore) async -> DeskResult {
        var collected: [Article] = []
        var errors: [String] = []
        var skippedOld = 0
        var skippedDup = 0
        var seenURLs = Set<String>()

        for feed in FeedRegistry.feeds(for: desk) {
            do {
                guard let url = URL(string: feed.url) else { continue }
                let data = try await Net.data(
                    from: url,
                    accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, */*"
                )
                let items = RSSParser.parse(data: data)
                for item in items {
                    let link = CanonicalURL.fingerprint(item.link)
                    guard !link.isEmpty, !link.contains("news.google.com") else { continue }
                    if seenURLs.contains(link) {
                        skippedDup += 1
                        continue
                    }
                    seenURLs.insert(link)
                    let published = DateStamp.parse(item.date)
                    if !store.isWithinLookback(published, hours: lookbackHours) {
                        skippedOld += 1
                        continue
                    }
                    let id = FreshnessStore.articleID(url: link, fallback: item.title)
                    if store.hasSeen(id) {
                        skippedDup += 1
                        continue
                    }
                    let title = HTMLText.strip(item.title)
                    guard !title.isEmpty else { continue }
                    let summary = HTMLText.strip(item.summary)
                    let tags = Hashtagger.tags(desk: desk, title: title)
                    let (tweet, chars) = Hashtagger.tweet(title: title, url: link, tags: tags)
                    collected.append(Article(
                        id: id,
                        desk: desk,
                        title: title,
                        url: link,
                        source: feed.label,
                        published: published,
                        summary: summary,
                        tweet: tweet,
                        tweetChars: chars,
                        hashtags: tags,
                        extra: [:]
                    ))
                }
            } catch {
                errors.append("\(feed.label): feed unreachable")
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        collected.sort { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        if collected.count > maxItems { collected = Array(collected.prefix(maxItems)) }
        return DeskResult(desk: desk, articles: collected, skippedOld: skippedOld, skippedDup: skippedDup, sourceErrors: errors)
    }
}

struct RSSItem {
    var title = ""
    var link = ""
    var summary = ""
    var date = ""
}

final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [RSSItem] = []
    private var current = RSSItem()
    private var text = ""
    private var inItem = false
    private var currentElement = ""
    private var linkHref = ""

    static func parse(data: Data) -> [RSSItem] {
        let parser = RSSParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldProcessNamespaces = false
        xml.parse()
        return parser.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        text = ""
        if currentElement == "item" || currentElement == "entry" {
            inItem = true
            current = RSSItem()
        }
        if inItem, currentElement == "link", let href = attributeDict["href"], current.link.isEmpty {
            current.link = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) { text += s }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            switch name {
            case "title": current.title = value
            case "link":
                if current.link.isEmpty { current.link = value }
            case "guid" where current.link.isEmpty && value.hasPrefix("http"):
                current.link = value
            case "id" where current.link.isEmpty && value.hasPrefix("http"):
                current.link = value
            case "description", "summary", "content", "encoded":
                if current.summary.count < value.count { current.summary = value }
            case "pubdate", "published", "updated", "date", "dc:date":
                if current.date.isEmpty { current.date = value }
            default:
                break
            }
        }
        if name == "item" || name == "entry" {
            inItem = false
            if !current.title.isEmpty { items.append(current) }
        }
        text = ""
    }
}
