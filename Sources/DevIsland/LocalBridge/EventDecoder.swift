import Foundation

/// A command from another DevIsland process, e.g. {"source":"devisland","payload":{"command":"open-dashboard"}}
struct AppCommand: Decodable {
    let command: String
}

/// Decodes socket messages shaped like: {"source": "claude", "payload": {...}}
enum EventDecoder {
    private struct SourceOnly: Decodable { let source: String }
    private struct Envelope<Payload: Decodable>: Decodable { let payload: Payload }

    static func source(of data: Data) -> String? {
        try? decoder.decode(SourceOnly.self, from: data).source
    }

    static func payload<Payload: Decodable>(_ type: Payload.Type, from data: Data) -> Payload? {
        try? decoder.decode(Envelope<Payload>.self, from: data).payload
    }

    /// Hook JSON uses snake_case (session_id); Swift uses camelCase (sessionId).
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
