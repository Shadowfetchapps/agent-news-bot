import Foundation

enum AppPaths {
    static let appName = "Agent News Bot"
    static let bundleId = "ai.shadowfetch.agentnewsbot"

    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentNewsBot", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var exports: URL {
        let url = support.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var seenDB: URL { support.appendingPathComponent("seen.sqlite") }
    static var tokenFile: URL { support.appendingPathComponent("bridge.token") }
}
