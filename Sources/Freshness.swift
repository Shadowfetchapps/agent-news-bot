import Foundation
import SQLite3
import CryptoKit

final class FreshnessStore: @unchecked Sendable {
    private let lock = NSLock()
    private var db: OpaquePointer?

    init(path: URL) {
        if sqlite3_open(path.path, &db) != SQLITE_OK {
            db = nil
            return
        }
        exec("""
        CREATE TABLE IF NOT EXISTS seen (
            id TEXT PRIMARY KEY,
            url TEXT,
            title TEXT,
            desk TEXT,
            seen_at REAL
        );
        CREATE TABLE IF NOT EXISTS quotes (
            symbol TEXT PRIMARY KEY,
            payload TEXT,
            updated_at REAL
        );
        """)
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    func hasSeen(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM seen WHERE id = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    func mark(id: String, url: String, title: String, desk: String) {
        lock.lock()
        defer { lock.unlock() }
        exec(
            "INSERT OR REPLACE INTO seen(id, url, title, desk, seen_at) VALUES (?,?,?,?,?)",
            bind: { stmt in
                self.bind(stmt, 1, id)
                self.bind(stmt, 2, url)
                self.bind(stmt, 3, title)
                self.bind(stmt, 4, desk)
                sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
            }
        )
    }

    func lastQuote(_ symbol: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT payload FROM quotes WHERE symbol = ?", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        bind(stmt, 1, symbol)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    func saveQuote(_ symbol: String, payload: String) {
        lock.lock()
        defer { lock.unlock() }
        exec(
            "INSERT OR REPLACE INTO quotes(symbol, payload, updated_at) VALUES (?,?,?)",
            bind: { stmt in
                self.bind(stmt, 1, symbol)
                self.bind(stmt, 2, payload)
                sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            }
        )
    }

    func isWithinLookback(_ published: Date?, hours: Double) -> Bool {
        guard let published else { return true }
        return published >= Date().addingTimeInterval(-hours * 3600)
    }

    static func articleID(url: String, fallback: String) -> String {
        let canon = CanonicalURL.fingerprint(url)
        let digest = SHA256.hash(data: Data(canon.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex.isEmpty ? fallback : String(hex.prefix(24))
    }

    private func bind(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func exec(_ sql: String, bind: ((OpaquePointer?) -> Void)? = nil) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        bind?(stmt)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }
}
