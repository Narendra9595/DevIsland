import AppKit
import Observation

/// Checks GitHub once a day for a newer DevIsland release. One small request, nothing about you is sent.
@MainActor
@Observable
final class UpdateChecker {
    struct Release: Equatable {
        let version: String
        let page: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate
        case available(Release)
        case failed
    }

    static let releasesAPI = URL(string: "https://api.github.com/repos/Narendra9595/DevIsland/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/Narendra9595/DevIsland/releases/latest")!

    private(set) var state = State.idle
    private(set) var lastChecked: Date?

    var available: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Checks shortly after launch, then once a day, while `isEnabled` says so.
    func start(isEnabled: @escaping () -> Bool) {
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30)) // let launch settle first
            while !Task.isCancelled {
                if isEnabled() { await self?.check() }
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    /// Asks GitHub for the latest release and compares it with this version.
    func check() async {
        state = .checking
        var request = URLRequest(url: Self.releasesAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DevIsland-UpdateCheck", forHTTPHeaderField: "User-Agent")
        struct Latest: Decodable {
            let tagName: String
            let htmlUrl: URL
            let draft: Bool
            let prerelease: Bool
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name", htmlUrl = "html_url", draft, prerelease
            }
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = try? JSONDecoder().decode(Latest.self, from: data), !latest.draft, !latest.prerelease else {
            state = .failed
            return
        }
        lastChecked = .now
        let version = latest.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        state = Self.isNewer(version, than: AppInfo.version) ? .available(Release(version: version, page: latest.htmlUrl)) : .upToDate
    }

    /// "1.10.0" is newer than "1.9.2".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
