import Foundation

enum MarketsClient {
    static func fetch(symbols: String, maxItems: Int, store: FreshnessStore) async -> DeskResult {
        var errors: [String] = []
        var skippedDup = 0
        var articles: [Article] = []
        let list = symbols
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }

        for symbol in list {
            let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
            guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=5d") else { continue }
            do {
                let any = try await Net.json(from: url, timeout: 12)
                guard
                    let root = any as? [String: Any],
                    let chart = root["chart"] as? [String: Any],
                    let result = (chart["result"] as? [[String: Any]])?.first,
                    let meta = result["meta"] as? [String: Any]
                else { throw URLError(.cannotParseResponse) }

                let price = number(meta["regularMarketPrice"])
                let prev = number(meta["chartPreviousClose"]) != 0 ? number(meta["chartPreviousClose"]) : number(meta["previousClose"])
                let name = string(meta["shortName"]).isEmpty ? string(meta["longName"]) : string(meta["shortName"])
                let currency = string(meta["currency"]).isEmpty ? "USD" : string(meta["currency"])
                guard price > 0 else { continue }
                let change = prev > 0 ? (price - prev) / prev : 0
                let payload = String(format: "%.4f|%.5f", price, change)
                if let last = store.lastQuote(symbol), last == payload {
                    skippedDup += 1
                    continue
                }
                let moved = abs(change) >= 0.0015 || store.lastQuote(symbol) == nil
                guard moved else {
                    skippedDup += 1
                    continue
                }
                store.saveQuote(symbol, payload: payload)
                let sign = change >= 0 ? "+" : ""
                let title = "\(display(symbol)) \(String(format: "%.2f", price)) \(sign)\(String(format: "%.2f%%", change * 100))"
                let page = "https://finance.yahoo.com/quote/\(encoded)"
                let id = FreshnessStore.articleID(url: page + payload, fallback: "mkt-\(symbol)-\(payload)")
                let tags = Hashtagger.tags(
                    desk: .markets,
                    title: title,
                    extra: ["$\(display(symbol).replacingOccurrences(of: "^", with: ""))"]
                )
                let (tweet, chars) = Hashtagger.tweet(title: title, url: page, tags: tags)
                articles.append(Article(
                    id: id,
                    desk: .markets,
                    title: title,
                    url: page,
                    source: name.isEmpty ? "Yahoo Finance" : name,
                    published: Date(),
                    summary: "\(currency) · prior close \(String(format: "%.2f", prev))",
                    tweet: tweet,
                    tweetChars: chars,
                    hashtags: tags,
                    extra: ["symbol": symbol, "change": String(format: "%.4f", change)]
                ))
            } catch {
                errors.append("\(symbol): quote failed")
            }
        }

        articles.sort {
            abs(Double($0.extra["change"] ?? "0") ?? 0) > abs(Double($1.extra["change"] ?? "0") ?? 0)
        }
        if articles.count > maxItems { articles = Array(articles.prefix(maxItems)) }
        return DeskResult(desk: .markets, articles: articles, skippedOld: 0, skippedDup: skippedDup, sourceErrors: errors)
    }

    private static func number(_ value: Any?) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }

    private static func string(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private static func display(_ symbol: String) -> String {
        switch symbol {
        case "^GSPC": return "S&P 500"
        case "^DJI": return "Dow"
        case "^IXIC": return "Nasdaq"
        default: return symbol
        }
    }
}
