import Foundation
import Testing
@testable import DevIsland

@MainActor
final class EventRecorder {
    private(set) var events: [ActivityEvent] = []
    func record(_ event: ActivityEvent) { events.append(event) }
}

struct EventModelTests {
    @Test func roundTripsThroughJSON() throws {
        let event = ActivityEvent(source: "claude", kind: .completed, sessionID: "s", title: "Finished",
                                  detail: "App · main", duration: 42,
                                  actions: [.init(id: "play", symbol: "play.fill", label: "Play")],
                                  metadata: ["state": "done"])
        let decoded = try JSONDecoder().decode(ActivityEvent.self, from: JSONEncoder().encode(event))
        #expect(decoded == event)
    }

    @Test func toleratesOlderAndUnknownFormats() throws {
        let json = #"{"source":"test","kind":"progress","title":"Old","timestamp":700000000}"#
        let event = try JSONDecoder().decode(ActivityEvent.self, from: Data(json.utf8))
        #expect(event.kind == .update)
        #expect(event.actions.isEmpty)
        #expect(event.priority == .normal)
        #expect(event.metadata.isEmpty)
    }
}

@MainActor
struct ActivityStoreTests {
    @Test func ignoresDuplicateEvents() {
        let store = ActivityStore(database: nil)
        let event = ActivityEvent(source: "test", kind: .started, title: "A")
        store.handle(event)
        store.handle(event)
        #expect(store.history.count == 1)
    }

    @Test func updatesAreLiveButNotSaved() {
        let store = ActivityStore(database: nil)
        store.handle(ActivityEvent(source: "battery", kind: .update, title: "Battery"))
        #expect(store.live.count == 1)
        #expect(store.history.isEmpty)
    }

    @Test func highestPriorityIsCurrentUnlessTheUserPicks() {
        let store = ActivityStore(database: nil)
        store.handle(ActivityEvent(source: "battery", kind: .update, title: "Battery", priority: .low))
        store.handle(ActivityEvent(source: "network", kind: .alert, title: "Offline", priority: .high))
        #expect(store.current?.event.source == "network")
        store.select("battery:")
        #expect(store.current?.event.source == "battery")
    }

    @Test func endedWithoutSessionEndsTheWholeSource() {
        let store = ActivityStore(database: nil)
        store.handle(ActivityEvent(source: "media", kind: .update, sessionID: "Music", title: "A"))
        store.handle(ActivityEvent(source: "media", kind: .update, sessionID: "Spotify", title: "B"))
        store.handle(ActivityEvent(source: "media", kind: .ended, sessionID: "Music", title: "Stopped"))
        #expect(store.live.map(\.key) == ["media:Spotify"])
        store.handle(ActivityEvent(source: "media", kind: .ended, title: "Off"))
        #expect(store.live.isEmpty)
    }

    @Test func respectsExpiry() {
        let store = ActivityStore(database: nil)
        store.handle(ActivityEvent(source: "battery", kind: .update, title: "Battery", expiresAfter: 6))
        store.removeStale(now: .now + 5)
        #expect(store.live.count == 1)
        store.removeStale(now: .now + 7)
        #expect(store.live.isEmpty)
    }

    @Test func finishedWorkLingersForAMinute() {
        let store = ActivityStore(database: nil)
        store.handle(ActivityEvent(source: "timer", kind: .completed, title: "Done"))
        store.removeStale(now: .now + 30)
        #expect(store.live.count == 1)
        store.removeStale(now: .now + 61)
        #expect(store.live.isEmpty)
    }

    @Test func restoresHistoryAfterRelaunch() throws {
        let database = try #require(EventDatabase(path: ":memory:"))
        let event = ActivityEvent(source: "test", kind: .alert, title: "Saved")
        ActivityStore(database: database).handle(event)
        #expect(ActivityStore(database: database).history == [event])
    }

    @Test func prunesOldHistory() throws {
        let database = try #require(EventDatabase(path: ":memory:"))
        let store = ActivityStore(database: database)
        store.handle(ActivityEvent(source: "test", kind: .started, title: "Old", timestamp: .now - 10 * 86_400))
        store.handle(ActivityEvent(source: "test", kind: .started, title: "New"))
        store.pruneHistory(olderThan: .now - 7 * 86_400)
        #expect(store.history.map(\.title) == ["New"])
        #expect(database.totalCount() == 1)
    }
}

struct ActivityStatsTests {
    @Test func summarizesADay() {
        let events = [
            ActivityEvent(source: "claude", kind: .started, sessionID: "a", title: "Session started"),
            ActivityEvent(source: "claude", kind: .completed, sessionID: "a", title: "Finished", duration: 120),
            ActivityEvent(source: "claude", kind: .completed, sessionID: "b", title: "Finished", duration: 60),
            ActivityEvent(source: "claude", kind: .alert, sessionID: "a", title: "Needs you"),
            ActivityEvent(source: "codex", kind: .completed, title: "Turn finished"),
            ActivityEvent(source: "timer", kind: .completed, title: "Focus complete", duration: 1_500, metadata: ["mode": "focus"]),
            ActivityEvent(source: "timer", kind: .completed, title: "Break over", duration: 300, metadata: ["mode": "rest"]),
        ]
        let stats = ActivityStats.day(events)
        #expect(stats.agentTurns == 3)
        #expect(stats.agentActiveTime == 180)
        #expect(stats.agentSessions == 2)
        #expect(stats.agentAlerts == 1)
        #expect(stats.focusSessions == 1)
        #expect(stats.focusTime == 1_500)
        #expect(stats.events == 7)
    }

    @Test func groupsAgentSessionsNewestFirst() {
        let start = Date.now - 3_600
        let events = [
            ActivityEvent(source: "claude", kind: .started, sessionID: "a", title: "Session started",
                          metadata: ["project": "App", "branch": "main"], timestamp: start),
            ActivityEvent(source: "claude", kind: .completed, sessionID: "a", title: "Finished", duration: 90,
                          metadata: ["project": "App", "branch": "feature"], timestamp: start + 600),
            ActivityEvent(source: "claude", kind: .completed, sessionID: "b", title: "Finished", duration: 30,
                          timestamp: start + 1_200),
        ]
        let sessions = ActivityStats.agentSessions(events)
        #expect(sessions.map(\.id) == ["claude:b", "claude:a"])
        #expect(sessions[1].project == "App")
        #expect(sessions[1].branch == "feature")
        #expect(sessions[1].turns == 1)
        #expect(sessions[1].activeTime == 90)
    }

    @Test func countsTurnsByHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let threeAM = Date(timeIntervalSince1970: 3 * 3_600 + 120)
        let counts = ActivityStats.agentTurnsByHour(
            [ActivityEvent(source: "claude", kind: .completed, title: "Finished", timestamp: threeAM)], calendar: calendar)
        #expect(counts.count == 24)
        #expect(counts[3].count == 1)
        #expect(counts.reduce(0) { $0 + $1.count } == 1)
    }
}

struct EventDatabaseTests {
    @Test func savesAndLoadsNewestFirst() throws {
        let database = try #require(EventDatabase(path: ":memory:"))
        let older = ActivityEvent(source: "a", kind: .started, title: "Old", timestamp: .now - 60)
        let newer = ActivityEvent(source: "b", kind: .completed, title: "New")
        database.insert(older)
        database.insert(newer)
        database.insert(newer)
        #expect(database.recent(limit: 10) == [newer, older])
        #expect(database.countsBySource().count == 2)
    }

    @Test func searchesTitlesDetailsAndSources() throws {
        let database = try #require(EventDatabase(path: ":memory:"))
        database.insert(ActivityEvent(source: "claude", kind: .completed, title: "Finished", detail: "Shop · main"))
        database.insert(ActivityEvent(source: "timer", kind: .completed, title: "Focus complete"))
        database.insert(ActivityEvent(source: "claude", kind: .alert, title: "100% done_now"))
        #expect(database.search(text: "shop", source: nil, limit: 10).count == 1)
        #expect(database.search(text: "", source: "claude", limit: 10).count == 2)
        #expect(database.search(text: "%", source: nil, limit: 10).map(\.title) == ["100% done_now"])
        #expect(database.search(text: "_", source: nil, limit: 10).count == 1)
        #expect(database.sources() == ["claude", "timer"])
    }

    @Test func countsEventsPerDay() throws {
        let database = try #require(EventDatabase(path: ":memory:"))
        database.insert(ActivityEvent(source: "a", kind: .started, title: "1"))
        database.insert(ActivityEvent(source: "a", kind: .started, title: "2"))
        database.insert(ActivityEvent(source: "b", kind: .started, title: "3", timestamp: .now - 3 * 86_400))
        database.insert(ActivityEvent(source: "b", kind: .started, title: "Too old", timestamp: .now - 30 * 86_400))
        let counts = database.dailyCounts(days: 14)
        #expect(counts.reduce(0) { $0 + $1.count } == 3)
        #expect(Set(counts.map(\.day)).count == 2)
    }
}

struct FormatTests {
    @Test func durations() {
        #expect(Format.duration(0) == "0m")
        #expect(Format.duration(42) == "42s")
        #expect(Format.duration(125) == "2m")
        #expect(Format.duration(3_900) == "1h 5m")
        #expect(Format.duration(7_200) == "2h")
    }

    @Test func clocks() {
        #expect(Format.clock(65) == "1:05")
        #expect(Format.clock(3_725) == "1:02:05")
    }
}

struct IslandGeometryTests {
    @Test func sizesAroundTheNotch() {
        let geometry = IslandGeometry(hasNotch: true, notchSize: CGSize(width: 180, height: 32), topHeight: 32)
        #expect(geometry.compactSize(isLive: false) == CGSize(width: 180, height: 32))
        #expect(geometry.compactSize(isLive: true).width == 180 + IslandGeometry.earWidth * 2)
        #expect(geometry.expandedSize(contentHeight: 88) == CGSize(width: 540, height: 120))
        #expect(geometry.shoulder == 6)
    }

    @Test func floatingIslandIsADetachedCapsule() {
        let geometry = IslandGeometry(hasNotch: false, notchSize: .zero, topHeight: IslandGeometry.capsuleHeight, floating: true)
        #expect(geometry.shoulder == 0)
        #expect(geometry.topGap == 6)
        #expect(geometry.compactRadius == IslandGeometry.capsuleHeight / 2)
    }

    @Test func usesTheMenuBarOnMacsWithoutANotch() {
        let geometry = IslandGeometry(hasNotch: false, notchSize: .zero, topHeight: 24)
        #expect(geometry.shoulder == 0)
        #expect(geometry.compactSize(isLive: false).height == 24)
        #expect(geometry.compactRadius == 12)
    }
}

struct GitInfoTests {
    private func makeRepo(head: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "devisland-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        try head.write(to: root.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func readsTheBranchFromAParentFolder() throws {
        let root = try makeRepo(head: "ref: refs/heads/feature/island\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appending(path: "Sources/App")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(GitInfo.branch(at: nested.path) == "feature/island")
    }

    @Test func shortensADetachedHead() throws {
        let root = try makeRepo(head: "0123456789abcdef\n")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(GitInfo.branch(at: root.path) == "0123456")
    }

    @Test func followsAWorktreeGitFile() throws {
        let realRepo = try makeRepo(head: "ref: refs/heads/main\n")
        let worktree = FileManager.default.temporaryDirectory.appending(path: "devisland-worktree-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: realRepo)
            try? FileManager.default.removeItem(at: worktree)
        }
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(realRepo.appending(path: ".git").path)\n".write(to: worktree.appending(path: ".git"), atomically: true, encoding: .utf8)
        #expect(GitInfo.branch(at: worktree.path) == "main")
    }

    @Test func isNilOutsideARepository() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "devisland-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(GitInfo.branch(at: folder.path) == nil)
    }
}
