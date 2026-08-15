import Foundation

enum Desk: String, CaseIterable, Identifiable, Codable, Hashable {
    case breaking
    case politics
    case world
    case business
    case markets
    case tech
    case ai
    case science
    case health
    case entertainment
    case sports
    case hackerNews
    case polymarket
    case weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breaking: return "Breaking"
        case .politics: return "Politics"
        case .world: return "World"
        case .business: return "Business"
        case .markets: return "Markets"
        case .tech: return "Tech"
        case .ai: return "AI"
        case .science: return "Science"
        case .health: return "Health"
        case .entertainment: return "Entertainment"
        case .sports: return "Sports"
        case .hackerNews: return "Hacker News"
        case .polymarket: return "Polymarket"
        case .weather: return "Weather"
        }
    }

    var systemImage: String {
        switch self {
        case .breaking: return "bolt.fill"
        case .politics: return "building.columns.fill"
        case .world: return "globe.americas.fill"
        case .business: return "briefcase.fill"
        case .markets: return "chart.line.uptrend.xyaxis"
        case .tech: return "laptopcomputer"
        case .ai: return "cpu.fill"
        case .science: return "atom"
        case .health: return "heart.fill"
        case .entertainment: return "theatermasks.fill"
        case .sports: return "sportscourt.fill"
        case .hackerNews: return "y.circle.fill"
        case .polymarket: return "chart.bar.doc.horizontal.fill"
        case .weather: return "cloud.sun.fill"
        }
    }

    var hashtags: [String] {
        switch self {
        case .breaking: return ["#Breaking", "#News"]
        case .politics: return ["#Politics"]
        case .world: return ["#WorldNews"]
        case .business: return ["#Business"]
        case .markets: return ["#Markets", "#Stocks"]
        case .tech: return ["#Technology"]
        case .ai: return ["#AI", "#ArtificialIntelligence"]
        case .science: return ["#Science"]
        case .health: return ["#Health"]
        case .entertainment: return ["#Entertainment"]
        case .sports: return ["#Sports"]
        case .hackerNews: return ["#HackerNews"]
        case .polymarket: return ["#Polymarket", "#PredictionMarkets"]
        case .weather: return ["#Weather"]
        }
    }
}

struct Article: Identifiable, Hashable, Codable {
    var id: String
    var desk: Desk
    var title: String
    var url: String
    var source: String
    var published: Date?
    var summary: String
    var tweet: String
    var tweetChars: Int
    var hashtags: [String]
    var extra: [String: String]

    var host: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
    }
}

struct DeskResult: Identifiable {
    var id: Desk { desk }
    var desk: Desk
    var articles: [Article]
    var skippedOld: Int
    var skippedDup: Int
    var sourceErrors: [String]
}

struct FetchReport {
    var started: Date
    var finished: Date
    var freshCount: Int
    var scanned: Int
    var desks: [DeskResult]
}

enum AgentKind: String, Codable {
    case hermes
    case openclaw
}

struct AgentStatus: Equatable {
    var kind: AgentKind
    var label: String
    var detail: String
    var ready: Bool
}

enum UserAgent {
    static let current =
        "AgentNewsBot/1.0 (+https://github.com/Realbobcorbin/agent-news-bot; Macintosh) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
}

enum Net {
    static func data(from url: URL, timeout: TimeInterval = 14, accept: String = "*/*") async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(UserAgent.current, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    static func json(from url: URL, timeout: TimeInterval = 14) async throws -> Any {
        let data = try await data(from: url, timeout: timeout, accept: "application/json")
        return try JSONSerialization.jsonObject(with: data)
    }
}

enum HTMLText {
    static func strip(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&#x27;", "'")
        ]
        for (from, to) in entities { text = text.replacingOccurrences(of: from, with: to) }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CanonicalURL {
    static func fingerprint(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return raw.lowercased() }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        components.user = nil
        components.password = nil
        if let items = components.queryItems {
            components.queryItems = items.filter { item in
                let name = item.name.lowercased()
                return !(name.hasPrefix("utm_") || name == "fbclid" || name == "gclid" || name == "ocid")
            }
            if components.queryItems?.isEmpty == true { components.queryItems = nil }
        }
        var result = components.string ?? raw
        if result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

enum DateStamp {
    static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd"
        ] {
            rfc.dateFormat = format
            if let date = rfc.date(from: raw) { return date }
        }
        return nil
    }

    static func age(_ date: Date?) -> String {
        guard let date else { return "undated" }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
