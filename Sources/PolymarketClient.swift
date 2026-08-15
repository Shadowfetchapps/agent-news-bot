import Foundation

enum PolymarketClient {
    static func fetch(lookbackHours: Double, maxItems: Int, store: FreshnessStore) async -> DeskResult {
        var errors: [String] = []
        var skippedDup = 0
        var skippedOld = 0
        var articles: [Article] = []

        let urls = [
            "https://gamma-api.polymarket.com/events?limit=40&active=true&closed=false&order=volume24hr&ascending=false",
            "https://gamma-api.polymarket.com/markets?limit=40&active=true&closed=false&order=volume24hr&ascending=false"
        ]

        for raw in urls {
            do {
                let any = try await Net.json(from: URL(string: raw)!)
                let rows = any as? [[String: Any]] ?? []
                for row in rows {
                    let title = string(row["title"] ?? row["question"] ?? row["slug"])
                    guard !title.isEmpty else { continue }
                    let slug = string(row["slug"])
                    let url = slug.isEmpty
                        ? "https://polymarket.com"
                        : "https://polymarket.com/event/\(slug)"
                    let id = FreshnessStore.articleID(url: url, fallback: slug)
                    if store.hasSeen(id) {
                        skippedDup += 1
                        continue
                    }
                    let end = DateStamp.parse(string(row["endDate"] ?? row["end_date_iso"]))
                    if let end, end < Date().addingTimeInterval(-lookbackHours * 3600), end < Date() {
                        skippedOld += 1
                        continue
                    }
                    let volume = number(row["volume24hr"] ?? row["volume"])
                    let price = yesPrice(row)
                    var summaryParts: [String] = []
                    if volume > 0 { summaryParts.append(String(format: "24h volume $%.0f", volume)) }
                    if let price { summaryParts.append(String(format: "Yes %.0f%%", price * 100)) }
                    let summary = summaryParts.joined(separator: " · ")
                    var extraTags: [String] = []
                    if volume >= 100_000 { extraTags.append("#HotMarket") }
                    let tags = Hashtagger.tags(desk: .polymarket, title: title, extra: extraTags)
                    let (tweet, chars) = Hashtagger.tweet(title: title, url: url, tags: tags)
                    articles.append(Article(
                        id: id,
                        desk: .polymarket,
                        title: title,
                        url: url,
                        source: "Polymarket",
                        published: DateStamp.parse(string(row["startDate"] ?? row["createdAt"])) ?? Date(),
                        summary: summary,
                        tweet: tweet,
                        tweetChars: chars,
                        hashtags: tags,
                        extra: ["volume": String(format: "%.0f", volume)]
                    ))
                }
            } catch {
                errors.append("Polymarket: API unreachable")
            }
        }

        var unique: [Article] = []
        var seen = Set<String>()
        for article in articles where seen.insert(article.id).inserted {
            unique.append(article)
        }
        unique.sort { ($0.extra["volume"].flatMap(Double.init) ?? 0) > ($1.extra["volume"].flatMap(Double.init) ?? 0) }
        if unique.count > maxItems { unique = Array(unique.prefix(maxItems)) }
        return DeskResult(desk: .polymarket, articles: unique, skippedOld: skippedOld, skippedDup: skippedDup, sourceErrors: errors)
    }

    private static func string(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    private static func number(_ value: Any?) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }

    private static func yesPrice(_ row: [String: Any]) -> Double? {
        if let prices = row["outcomePrices"] as? String,
           let data = prices.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
           let first = arr.first {
            return number(first)
        }
        if let markets = row["markets"] as? [[String: Any]], let first = markets.first {
            return yesPrice(first)
        }
        return nil
    }
}
