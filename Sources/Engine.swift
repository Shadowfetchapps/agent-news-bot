import Foundation
import Combine
import AppKit

@MainActor
final class NewsEngine: ObservableObject {
    static let shared = NewsEngine()

    @Published var articles: [Article] = []
    @Published var desks: [DeskResult] = []
    @Published var selectedDesk: Desk? = .breaking
    @Published var selected: Article?
    @Published var isFetching = false
    @Published var status = "Ready. Fetch Fresh pulls only unseen stories inside the lookback window."
    @Published var report: FetchReport?
    @Published var hermes = AgentStatus(kind: .hermes, label: "Hermes", detail: "Checking…", ready: false)
    @Published var openclaw = AgentStatus(kind: .openclaw, label: "OpenClaw", detail: "Checking…", ready: false)
    @Published var bridgeReady = false
    @Published var lastAgentReply = ""
    @Published var search = ""

    let settings = SettingsStore.shared
    let store = FreshnessStore(path: AppPaths.seenDB)
    let bridge = AgentBridge()

    nonisolated(unsafe) var snapshotArticles: [Article] = []
    nonisolated(unsafe) var snapshotDesks: [DeskResult] = []

    var filtered: [Article] {
        var items = articles
        if let desk = selectedDesk {
            items = items.filter { $0.desk == desk }
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.title.lowercased().contains(q)
                    || $0.source.lowercased().contains(q)
                    || $0.hashtags.joined().lowercased().contains(q)
            }
        }
        return items
    }

    var bridgeToken: String { loadOrCreateToken() }

    func start() {
        settings.save()
        bridge.articlesProvider = { [weak self] in
            self?.snapshotArticles ?? []
        }
        bridge.desksProvider = { [weak self] in
            self?.snapshotDesks ?? []
        }
        bridge.start(port: settings.bridgePort, token: bridgeToken)
        bridgeReady = true
        Task { await refreshAgents() }
        installHermesSkill()
    }

    func fetchFresh() async {
        guard !isFetching else { return }
        isFetching = true
        status = "Scanning desks for unseen stories…"
        let started = Date()
        let lookback = settings.lookbackHours
        let maxItems = settings.maxPerDesk
        let city = settings.weatherCity
        let symbols = settings.marketSymbols
        let enabled = settings.enabledDesks
        await refreshAgents()

        var results: [DeskResult] = []
        await withTaskGroup(of: DeskResult.self) { group in
            for desk in Desk.allCases where enabled.contains(desk) {
                group.addTask {
                    switch desk {
                    case .hackerNews:
                        return await HNClient.fetch(lookbackHours: lookback, maxItems: maxItems, store: self.store)
                    case .polymarket:
                        return await PolymarketClient.fetch(lookbackHours: lookback, maxItems: maxItems, store: self.store)
                    case .markets:
                        return await MarketsClient.fetch(symbols: symbols, maxItems: maxItems, store: self.store)
                    case .weather:
                        return await WeatherClient.fetch(city: city, store: self.store)
                    default:
                        return await RSSClient.fetch(desk: desk, lookbackHours: lookback, maxItems: maxItems, store: self.store)
                    }
                }
            }
            for await result in group {
                results.append(result)
            }
        }

        results.sort { $0.desk.title < $1.desk.title }
        var merged: [Article] = []
        for result in results {
            merged.append(contentsOf: result.articles)
            for article in result.articles {
                store.mark(id: article.id, url: article.url, title: article.title, desk: article.desk.rawValue)
            }
        }
        merged.sort { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }

        desks = results
        articles = merged
        selected = merged.first
        snapshotArticles = merged
        snapshotDesks = results

        let scanned = results.reduce(0) { $0 + $1.articles.count + $1.skippedOld + $1.skippedDup }
        report = FetchReport(started: started, finished: Date(), freshCount: merged.count, scanned: scanned, desks: results)
        exportJSON()
        let errors = results.flatMap(\.sourceErrors).count
        status = merged.isEmpty
            ? "No fresh stories in the last \(Int(lookback))h. Desks are current."
            : "\(merged.count) fresh stories · \(errors) source warnings"
        isFetching = false
    }

    func copyTweet(_ article: Article) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(article.tweet, forType: .string)
        status = "Copied tweet for \(article.source)"
    }

    func openStory(_ article: Article) {
        if let url = URL(string: article.url) {
            NSWorkspace.shared.open(url)
        }
    }

    func sendToHermes(_ items: [Article]? = nil) async {
        let payload = items ?? (selected.map { [$0] } ?? Array(articles.prefix(8)))
        guard !payload.isEmpty else { return }
        status = "Sending \(payload.count) item(s) to Hermes…"
        do {
            let reply = try await HermesClient.send(articles: payload, settings: settings)
            lastAgentReply = reply
            status = "Hermes accepted \(payload.count) item(s)"
        } catch {
            status = "Hermes send failed: \(error.localizedDescription)"
        }
    }

    func sendToOpenClaw(_ items: [Article]? = nil) async {
        let payload = items ?? (selected.map { [$0] } ?? Array(articles.prefix(8)))
        guard !payload.isEmpty else { return }
        status = "Sending \(payload.count) item(s) to OpenClaw…"
        do {
            let reply = try await OpenClawClient.send(articles: payload, settings: settings)
            lastAgentReply = reply
            status = "OpenClaw accepted \(payload.count) item(s)"
        } catch {
            status = "OpenClaw send failed: \(error.localizedDescription)"
        }
    }

    func refreshAgents() async {
        hermes = await HermesClient.probe(settings: settings)
        openclaw = await OpenClawClient.probe(settings: settings)
    }

    func revealExports() {
        NSWorkspace.shared.open(AppPaths.exports)
    }

    private func exportJSON() {
        let payload: [String: Any] = [
            "fetched_at": ISO8601DateFormatter().string(from: Date()),
            "total_articles": articles.count,
            "lookback_hours": settings.lookbackHours,
            "categories": Dictionary(uniqueKeysWithValues: Desk.allCases.map { desk in
                (desk.title, articles.filter { $0.desk == desk }.map { article -> [String: Any] in
                    [
                        "title": article.title,
                        "url": article.url,
                        "source": article.source,
                        "category": article.desk.title,
                        "published": article.published.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                        "summary": article.summary,
                        "tweet": article.tweet,
                        "tweet_chars": article.tweetChars,
                        "hashtags": article.hashtags
                    ]
                })
            })
        ]
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]
        let name = "agentnewsbot_\(Int(Date().timeIntervalSince1970)).json"
        let url = AppPaths.exports.appendingPathComponent(name)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    private func loadOrCreateToken() -> String {
        let url = AppPaths.tokenFile
        if let existing = try? String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 16 {
            return existing
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try? token.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }

    private func installHermesSkill() {
        let dest = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/skills/agent-news-bot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let skill = """
        ---
        name: agent-news-bot
        description: Pull only fresh, unseen news from the local Agent News Bot desk (RSS, AI, HN, Polymarket, markets, weather) over localhost HTTP.
        version: 1.0.0
        ---

        # Agent News Bot

        Agent News Bot is a macOS newsroom on this machine. It keeps a freshness ledger and only serves stories that have not been shown before and are inside the lookback window.

        Base URL: \(bridge.endpoint)
        Auth: `Authorization: Bearer \(bridgeToken)`

        ## When to use
        Use this when you need current headlines, AI/tech stories, Hacker News, Polymarket, stock moves, or weather for social or newsroom work.

        ## Calls
        - `GET /health`
        - `GET /v1/fresh` — current unseen batch
        - `GET /v1/desks` — per-desk counts and source errors

        Do not invent URLs. Prefer the tweet and hashtags fields when drafting social posts. Never print the bearer token in public channels.
        """
        try? skill.write(to: dest.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let agents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills/agent-news-bot", isDirectory: true)
        try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try? skill.write(to: agents.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
