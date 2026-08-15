import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: NewsEngine

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } content: {
            articleList
                .navigationSplitViewColumnWidth(min: 380, ideal: 520)
        } detail: {
            inspector
        }
        .background(Theme.bgDeep)
        .toolbar { toolbar }
    }

    private var sidebar: some View {
        List(selection: $engine.selectedDesk) {
            Section("Desks") {
                Button {
                    engine.selectedDesk = nil
                } label: {
                    Label("All fresh", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                ForEach(Desk.allCases) { desk in
                    if engine.settings.enabledDesks.contains(desk) {
                        let count = engine.articles.filter { $0.desk == desk }.count
                        NavigationLink(value: desk) {
                            Label {
                                HStack {
                                    Text(desk.title)
                                    Spacer()
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(Theme.gold)
                                    }
                                }
                            } icon: {
                                Image(systemName: desk.systemImage)
                            }
                        }
                    }
                }
            }
            Section("Agents") {
                AgentBadge(status: engine.hermes)
                AgentBadge(status: engine.openclaw)
                HStack {
                    Circle().fill(engine.bridgeReady ? Theme.success : Theme.danger).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local bridge")
                        Text(engine.bridge.endpoint)
                            .font(.caption)
                            .foregroundStyle(Theme.textLow)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var articleList: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter titles, sources, tags", text: $engine.search)
                    .textFieldStyle(.roundedBorder)
                Text(engine.status)
                    .font(.caption)
                    .foregroundStyle(Theme.textMed)
                    .lineLimit(2)
            }
            .padding(12)
            Divider()
            if engine.isFetching {
                ProgressView("Fetching unseen stories…")
                    .padding()
                Spacer()
            } else if engine.filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.gold)
                    Text("No fresh stories on this desk")
                        .font(.title3.weight(.semibold))
                    Text("Fetch Fresh scans RSS, Hacker News, Polymarket, markets, and weather. Only unseen items inside the lookback window appear here.")
                        .foregroundStyle(Theme.textMed)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("Fetch Fresh") { Task { await engine.fetchFresh() } }
                        .keyboardShortcut("r", modifiers: [.command])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(engine.filtered, selection: $engine.selected) { article in
                    ArticleRow(article: article)
                        .tag(article)
                        .contextMenu {
                            Button("Copy tweet") { engine.copyTweet(article) }
                            Button("Open story") { engine.openStory(article) }
                            Button("Send to Hermes") { Task { await engine.sendToHermes([article]) } }
                            Button("Send to OpenClaw") { Task { await engine.sendToOpenClaw([article]) } }
                        }
                }
                .listStyle(.inset)
            }
        }
    }

    private var inspector: some View {
        Group {
            if let article = engine.selected ?? engine.filtered.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(article.desk.title.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.gold)
                        Text(article.title)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)
                        Text("\(article.source) · \(DateStamp.age(article.published))")
                            .foregroundStyle(Theme.textMed)
                        if !article.summary.isEmpty {
                            Text(article.summary)
                                .foregroundStyle(Theme.textMed)
                                .textSelection(.enabled)
                        }
                        FlowTags(tags: article.hashtags)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Tweet")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text("\(article.tweetChars) / 280")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(article.tweetChars > 280 ? Theme.danger : Theme.textLow)
                            }
                            Text(article.tweet)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(10)
                                .anbCard()
                        }
                        HStack {
                            Button("Copy tweet") { engine.copyTweet(article) }
                            Button("Open story") { engine.openStory(article) }
                        }
                        HStack {
                            Button("Send to Hermes") { Task { await engine.sendToHermes([article]) } }
                                .disabled(!engine.hermes.ready)
                            Button("Send to OpenClaw") { Task { await engine.sendToOpenClaw([article]) } }
                                .disabled(!engine.openclaw.ready)
                        }
                        if !engine.lastAgentReply.isEmpty {
                            Text("Last agent reply")
                                .font(.caption.weight(.semibold))
                            Text(engine.lastAgentReply)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .anbCard()
                        }
                    }
                    .padding(20)
                }
            } else {
                Text("Select a story")
                    .foregroundStyle(Theme.textLow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bgRaised)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text("Agent News Bot")
                .font(.headline)
                .foregroundStyle(Theme.textHi)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await engine.fetchFresh() }
            } label: {
                Label("Fetch Fresh", systemImage: "arrow.clockwise")
            }
            .disabled(engine.isFetching)
            Button {
                Task { await engine.sendToHermes(Array(engine.filtered.prefix(8))) }
            } label: {
                Label("Send desk to Hermes", systemImage: "paperplane")
            }
            .disabled(!engine.hermes.ready || engine.filtered.isEmpty)
            Button(action: engine.revealExports) {
                Label("Exports", systemImage: "folder")
            }
        }
    }
}

struct AgentBadge: View {
    let status: AgentStatus
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(status.ready ? Theme.success : Theme.warning)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.label)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textLow)
                    .textSelection(.enabled)
            }
        }
    }
}

struct ArticleRow: View {
    let article: Article
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(article.desk.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.gold)
                Text(article.source)
                    .font(.caption)
                    .foregroundStyle(Theme.textLow)
                Spacer()
                Text(DateStamp.age(article.published))
                    .font(.caption)
                    .foregroundStyle(Theme.textLow)
            }
            Text(article.title)
                .font(.headline)
                .foregroundStyle(Theme.textHi)
                .fixedSize(horizontal: false, vertical: true)
            Text(article.hashtags.joined(separator: " "))
                .font(.caption)
                .foregroundStyle(Theme.aqua)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

struct FlowTags: View {
    let tags: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.gold.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }
}
