/// Central pipe for events: sources publish, features subscribe.
@MainActor
final class EventBus {
    private var subscribers: [@MainActor (ActivityEvent) -> Void] = []

    func subscribe(_ handler: @escaping @MainActor (ActivityEvent) -> Void) {
        subscribers.append(handler)
    }

    func publish(_ event: ActivityEvent) {
        subscribers.forEach { $0(event) }
    }
}
