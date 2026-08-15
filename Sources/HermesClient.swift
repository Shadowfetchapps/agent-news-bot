import Foundation

enum HermesClient {
    @MainActor
    static func probe(settings: SettingsStore) async -> AgentStatus {
        let cli = which("hermes")
        var apiReady = false
        if let base = URL(string: settings.hermesAPIURL) {
            let health = base.appendingPathComponent("health")
            if let _ = try? await Net.data(from: health, timeout: 2, accept: "application/json") {
                apiReady = true
            } else {
                let alt = base.appendingPathComponent("v1/models")
                var request = URLRequest(url: alt, timeoutInterval: 2)
                request.setValue(UserAgent.current, forHTTPHeaderField: "User-Agent")
                if !settings.hermesToken.isEmpty {
                    request.setValue("Bearer \(settings.hermesToken)", forHTTPHeaderField: "Authorization")
                }
                if let (_, response) = try? await URLSession.shared.data(for: request),
                   let http = response as? HTTPURLResponse,
                   (200..<500).contains(http.statusCode) {
                    apiReady = http.statusCode < 500
                }
            }
        }

        if cli != nil && settings.hermesUseCLI {
            return AgentStatus(
                kind: .hermes,
                label: "Hermes CLI",
                detail: apiReady ? "CLI + API \(settings.hermesAPIURL)" : cli!,
                ready: true
            )
        }
        if apiReady {
            return AgentStatus(kind: .hermes, label: "Hermes API", detail: settings.hermesAPIURL, ready: true)
        }
        if cli != nil {
            return AgentStatus(kind: .hermes, label: "Hermes CLI", detail: cli!, ready: true)
        }
        return AgentStatus(
            kind: .hermes,
            label: "Hermes",
            detail: "Not detected. Install Hermes or start `hermes gateway`.",
            ready: false
        )
    }

    @MainActor
    static func send(articles: [Article], settings: SettingsStore) async throws -> String {
        let body = brief(articles)
        if settings.hermesUseCLI, let path = which("hermes") {
            return try runCLI(path: path, prompt: body)
        }
        return try await runAPI(prompt: body, settings: settings)
    }

    static func brief(_ articles: [Article]) -> String {
        var lines = [
            "Agent News Bot fresh desk handoff. These items passed the freshness filter (new URL, inside the lookback window). Prepare social copy or a newsroom brief. Do not invent facts. Keep source URLs.",
            ""
        ]
        for article in articles.prefix(12) {
            lines.append("Desk: \(article.desk.title)")
            lines.append("Title: \(article.title)")
            lines.append("Source: \(article.source)")
            lines.append("URL: \(article.url)")
            lines.append("Published: \(article.published.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown")")
            lines.append("Hashtags: \(article.hashtags.joined(separator: " "))")
            lines.append("Tweet: \(article.tweet)")
            if !article.summary.isEmpty {
                lines.append("Summary: \(article.summary.prefix(400))")
            }
            lines.append("---")
        }
        return lines.joined(separator: "\n")
    }

    private static func runCLI(path: String, prompt: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["chat", "-Q", "-q", prompt, "--max-turns", "4"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "Hermes", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr])
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private static func runAPI(prompt: String, settings: SettingsStore) async throws -> String {
        guard let base = URL(string: settings.hermesAPIURL) else {
            throw URLError(.badURL)
        }
        let url = base.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.hermesToken.isEmpty {
            request.setValue("Bearer \(settings.hermesToken)", forHTTPHeaderField: "Authorization")
        }
        let payload: [String: Any] = [
            "model": "hermes-agent",
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return (message?["content"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
    }

    static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PATH": "/Users/\(NSUserName())/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        ]) { _, new in new }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        let fallback = "/Users/\(NSUserName())/.local/bin/\(name)"
        return FileManager.default.isExecutableFile(atPath: fallback) ? fallback : nil
    }
}
