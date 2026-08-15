import Foundation
import Darwin

final class AgentBridge {
    private var source: DispatchSourceRead?
    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "ai.shadowfetch.agentnewsbot.bridge")

    var port: UInt16 = 18765
    var token: String = ""
    var articlesProvider: () -> [Article] = { [] }
    var desksProvider: () -> [DeskResult] = { [] }

    var endpoint: String { "http://127.0.0.1:\(port)" }

    func start(port: Int, token: String) {
        stop()
        self.port = UInt16(port)
        self.token = token

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = self.port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(sock, 16) == 0 else {
            close(sock)
            return
        }
        fd = sock
        let src = DispatchSource.makeReadSource(fileDescriptor: sock, queue: queue)
        src.setEventHandler { [weak self] in
            self?.acceptOne()
        }
        src.setCancelHandler {
            close(sock)
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fd = -1
    }

    private func acceptOne() {
        var addr = sockaddr()
        var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
        let client = accept(fd, &addr, &len)
        guard client >= 0 else { return }
        queue.async { [weak self] in
            self?.serve(client)
            close(client)
        }
    }

    private func serve(_ client: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { return }
            data.append(buffer, count: n)
            if data.count > 64_000 { return }
        }
        let headerText = String(data: data, encoding: .utf8) ?? ""
        let lines = headerText.split(whereSeparator: \.isNewline).map(String.init)
        let requestLine = lines.first ?? ""
        let parts = requestLine.split(separator: " ")
        let path = parts.dropFirst().first.map(String.init) ?? "/"
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let idx = line.firstIndex(of: ":") {
                let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                headers[key] = value
            }
        }

        let authorized = headers["authorization"] == "Bearer \(token)" || headers["x-agent-token"] == token
        let response: (Int, Data)
        if path == "/health" || path.hasPrefix("/health?") {
            response = json(200, ["ok": true, "app": "Agent News Bot", "bridge": endpoint])
        } else if !authorized {
            response = json(401, ["error": "bearer token required"])
        } else if path.hasPrefix("/v1/fresh") {
            response = json(200, ["count": articlesProvider().count, "articles": articlesProvider().map(encode)])
        } else if path.hasPrefix("/v1/desks") {
            let desks = desksProvider().map { desk -> [String: Any] in
                [
                    "desk": desk.desk.rawValue,
                    "title": desk.desk.title,
                    "fresh": desk.articles.count,
                    "skipped_old": desk.skippedOld,
                    "skipped_dup": desk.skippedDup,
                    "errors": desk.sourceErrors
                ]
            }
            response = json(200, ["desks": desks])
        } else if path.hasPrefix("/v1/status") {
            response = json(200, ["ok": true, "fresh": articlesProvider().count])
        } else {
            response = json(404, ["error": "not found"])
        }
        writeResponse(client, status: response.0, body: response.1)
    }

    private func encode(_ article: Article) -> [String: Any] {
        [
            "id": article.id,
            "desk": article.desk.rawValue,
            "title": article.title,
            "url": article.url,
            "source": article.source,
            "published": article.published.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "summary": article.summary,
            "tweet": article.tweet,
            "tweet_chars": article.tweetChars,
            "hashtags": article.hashtags
        ]
    }

    private func json(_ status: Int, _ object: [String: Any]) -> (Int, Data) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return (status, data)
    }

    private func writeResponse(_ client: Int32, status: Int, body: Data) {
        let reason = status == 200 ? "OK" : status == 401 ? "Unauthorized" : "Error"
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        payload.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var sent = 0
            while sent < payload.count {
                let n = write(client, base + sent, payload.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}
