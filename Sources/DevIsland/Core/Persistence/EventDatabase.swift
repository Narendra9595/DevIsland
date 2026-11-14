import Foundation
import SQLite3

struct SourceCount: Identifiable, Equatable {
    let source: String
    let count: Int
    var id: String { source }
}

struct DailyCount: Identifiable, Equatable {
    let day: Date
    let source: String
    let count: Int
    var id: String { "\(day.timeIntervalSince1970)-\(source)" }
}

/// Saves events in a local SQLite file. Each event is stored as JSON text.
final class EventDatabase {
    let path: String
    private var db: OpaquePointer?

    init?(path: String) {
        self.path = path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, timestamp REAL NOT NULL, json TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS events_by_time ON events (timestamp);
            """, nil, nil, nil)
    }

    deinit { sqlite3_close(db) }

    // MARK: Writing

    func insert(_ event: ActivityEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        run("INSERT OR IGNORE INTO events (id, timestamp, json) VALUES (?, ?, ?)", [
            .text(event.id.uuidString),
            .double(event.timestamp.timeIntervalSince1970),
            .text(String(decoding: data, as: UTF8.self)),
        ])
    }

    func deleteAll() {
        run("DELETE FROM events")
    }

    func prune(olderThan date: Date) {
        run("DELETE FROM events WHERE timestamp < ?", [.double(date.timeIntervalSince1970)])
    }

    // MARK: Reading

    func recent(limit: Int) -> [ActivityEvent] {
        events("SELECT json FROM events ORDER BY timestamp DESC LIMIT ?", [.int(limit)])
    }

    func events(since date: Date, limit: Int = 10_000) -> [ActivityEvent] {
        events("SELECT json FROM events WHERE timestamp >= ? ORDER BY timestamp DESC LIMIT ?",
               [.double(date.timeIntervalSince1970), .int(limit)])
    }

    func allEvents() -> [ActivityEvent] {
        events("SELECT json FROM events ORDER BY timestamp ASC", [])
    }

    /// Searches titles and details, optionally limited to one source.
    func search(text: String, source: String?, limit: Int) -> [ActivityEvent] {
        var conditions: [String] = []
        var values: [Value] = []
        if let source {
            conditions.append("json_extract(json, '$.source') = ?")
            values.append(.text(source))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            conditions.append(#"(json_extract(json, '$.title') LIKE ? ESCAPE '\' OR json_extract(json, '$.detail') LIKE ? ESCAPE '\')"#)
            let pattern = "%" + Self.escapeLike(trimmed) + "%"
            values += [.text(pattern), .text(pattern)]
        }
        let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return events("SELECT json FROM events \(filter) ORDER BY timestamp DESC LIMIT ?", values + [.int(limit)])
    }

    func sources() -> [String] {
        rows("SELECT DISTINCT json_extract(json, '$.source') FROM events ORDER BY 1") { Self.text($0, 0) }
    }

    /// All-time number of saved events per source.
    func countsBySource() -> [SourceCount] {
        let sql = """
            SELECT json_extract(json, '$.source') AS source, COUNT(*) FROM events
            GROUP BY source ORDER BY COUNT(*) DESC
            """
        return rows(sql) { statement in
            Self.text(statement, 0).map { SourceCount(source: $0, count: Int(sqlite3_column_int64(statement, 1))) }
        }
    }

    /// Events per day and source for the last `days` days (local time).
    func dailyCounts(days: Int, now: Date = .now) -> [DailyCount] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let sql = """
            SELECT date(timestamp, 'unixepoch', 'localtime') AS day, json_extract(json, '$.source'), COUNT(*)
            FROM events WHERE timestamp >= ? GROUP BY day, 2 ORDER BY day
            """
        return rows(sql, [.double(start.timeIntervalSince1970)]) { statement in
            guard let dayText = Self.text(statement, 0), let day = formatter.date(from: dayText),
                  let source = Self.text(statement, 1) else { return nil }
            return DailyCount(day: day, source: source, count: Int(sqlite3_column_int64(statement, 2)))
        }
    }

    func totalCount() -> Int {
        rows("SELECT COUNT(*) FROM events") { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    var fileSize: Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: SQLite helpers

    private enum Value {
        case text(String)
        case double(Double)
        case int(Int)
    }

    private func prepare(_ sql: String, _ values: [Value]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return nil
        }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case .double(let number): sqlite3_bind_double(statement, position, number)
            case .int(let number): sqlite3_bind_int64(statement, position, Int64(number))
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Value] = []) {
        guard let statement = prepare(sql, values) else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_step(statement)
    }

    private func rows<T>(_ sql: String, _ values: [Value] = [], _ map: (OpaquePointer) -> T?) -> [T] {
        guard let statement = prepare(sql, values) else { return [] }
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let item = map(statement) { results.append(item) }
        }
        return results
    }

    private func events(_ sql: String, _ values: [Value]) -> [ActivityEvent] {
        let decoder = JSONDecoder()
        return rows(sql, values) { statement in
            guard let text = Self.text(statement, 0) else { return nil }
            return try? decoder.decode(ActivityEvent.self, from: Data(text.utf8))
        }
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: "%", with: #"\%"#)
            .replacingOccurrences(of: "_", with: #"\_"#)
    }

    /// Tells SQLite to copy the strings we bind.
    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
