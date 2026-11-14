import AppKit

/// A 25-minute focus timer with pause and resume. Started from the menu bar; shown in the island.
final class TimerIntegration: Integration {
    nonisolated static let sourceID = "timer"

    enum Mode: String {
        case focus

        var title: String { "Focus" }
        var completedTitle: String { "Focus complete" }
        var symbol: String { "brain.head.profile" }
        var duration: TimeInterval { 25 * 60 }
    }

    private enum State {
        case idle
        case running(Mode, end: Date, total: TimeInterval)
        case paused(Mode, remaining: TimeInterval, total: TimeInterval)
    }

    let id = TimerIntegration.sourceID
    let name = "Focus Timer"
    let summary = "A 25-minute focus timer with pause and resume. Start it from the menu bar."
    let symbol = "timer"

    private var publish: Publish?
    private var state = State.idle
    private var task: Task<Void, Never>?

    func start(publish: @escaping Publish) {
        self.publish = publish
    }

    func stop() {
        task?.cancel()
        state = .idle
        publish = nil
    }

    func perform(action: String) {
        switch action {
        case "focus": run(.focus, remaining: Mode.focus.duration, total: Mode.focus.duration, kind: .started)
        case "pause": pause()
        case "resume": resume()
        case "stop":
            task?.cancel()
            state = .idle
            publish?(ActivityEvent(source: id, kind: .ended, title: "Timer stopped"))
        default:
            break
        }
    }

    private func run(_ mode: Mode, remaining: TimeInterval, total: TimeInterval, kind: ActivityEvent.Kind) {
        task?.cancel()
        let end = Date.now.addingTimeInterval(remaining)
        state = .running(mode, end: end, total: total)
        publish?(ActivityEvent(
            source: id,
            kind: kind,
            title: mode.title,
            detail: "Ends at \(end.formatted(date: .omitted, time: .shortened))",
            symbol: mode.symbol,
            endDate: end,
            duration: total,
            expiresAfter: remaining + 120,
            actions: [
                .init(id: "pause", symbol: "pause.fill", label: "Pause"),
                .init(id: "stop", symbol: "stop.fill", label: "Stop"),
            ],
            metadata: ["mode": mode.rawValue]))

        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            self.finish(mode, total: total)
        }
    }

    private func pause() {
        guard case let .running(mode, end: end, total: total) = state else { return }
        task?.cancel()
        let remaining = max(0, end.timeIntervalSinceNow)
        state = .paused(mode, remaining: remaining, total: total)
        publish?(ActivityEvent(
            source: id,
            kind: .update,
            title: mode.title,
            detail: "Paused · \(Format.clock(remaining)) left",
            symbol: mode.symbol,
            progress: total > 0 ? 1 - remaining / total : 0,
            duration: total,
            expiresAfter: 12 * 3600,
            actions: [
                .init(id: "resume", symbol: "play.fill", label: "Resume"),
                .init(id: "stop", symbol: "stop.fill", label: "Stop"),
            ],
            metadata: ["mode": mode.rawValue]))
    }

    private func resume() {
        guard case let .paused(mode, remaining: remaining, total: total) = state else { return }
        run(mode, remaining: remaining, total: total, kind: .update)
    }

    private func finish(_ mode: Mode, total: TimeInterval) {
        state = .idle
        NSSound(named: "Glass")?.play()
        publish?(ActivityEvent(
            source: id,
            kind: .completed,
            title: mode.completedTitle,
            detail: "Nice work. Time for a short break.",
            symbol: "checkmark.circle.fill",
            duration: total,
            priority: .high,
            metadata: ["mode": mode.rawValue]))
    }
}
