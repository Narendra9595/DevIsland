import AppKit

/// Live download progress from your Downloads folder (Safari, Chrome, Firefox, Edge), then "Downloaded" with Show in Finder.
/// Off by default: macOS asks for Downloads folder access the first time. Only file names and sizes are read.
final class DownloadsIntegration: Integration {
    let id = "downloads"
    let name = "Downloads"
    let summary = "Download progress beside the notch, then a quick Show in Finder."
    let symbol = "arrow.down.circle"
    let enabledByDefault = false

    /// Partial-download extensions used by browsers.
    private static let partials = ["download", "crdownload", "part", "partial", "opdownload"]
    private let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
    private var task: Task<Void, Never>?
    private var active: Set<String> = []
    /// Bytes last reported per download, so unchanged ones aren't re-sent.
    private var reported: [String: Int64] = [:]

    func start(publish: @escaping Publish) {
        active = []
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.scan(publish: publish)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// "reveal:/path" or "open:/path".
    func perform(action: String) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let url = URL(filePath: parts[1])
        if parts[0] == "reveal" { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSWorkspace.shared.open(url) }
    }

    private func scan(publish: Publish) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])) ?? []
        let partials = files.filter { Self.partials.contains($0.pathExtension.lowercased()) }
        var seen: Set<String> = []

        for partial in partials {
            let key = partial.lastPathComponent
            seen.insert(key)
            let name = partial.deletingPathExtension().lastPathComponent
            let (done, total) = Self.progress(of: partial)
            guard reported[key] != done else { continue }
            reported[key] = done
            let detail = total.map { "\(Format.bytes(done)) of \(Format.bytes($0))" } ?? Format.bytes(done)
            publish(ActivityEvent(source: id, kind: active.contains(key) ? .update : .started, sessionID: key,
                                  title: name, detail: detail, symbol: "arrow.down.circle.fill",
                                  progress: total.map { $0 > 0 ? Double(done) / Double($0) : 0 },
                                  expiresAfter: 60, metadata: ["state": "downloading"]))
        }

        // A partial file that went away: finished (if the final file is there) or cancelled.
        for key in active.subtracting(seen) {
            let finished = folder.appending(path: (key as NSString).deletingPathExtension)
            if FileManager.default.fileExists(atPath: finished.path) {
                publish(ActivityEvent(source: id, kind: .completed, sessionID: key, title: finished.lastPathComponent,
                                      detail: "Downloaded", symbol: "checkmark.circle.fill", progress: 1, expiresAfter: 20,
                                      actions: [.init(id: "reveal:\(finished.path)", symbol: "folder", label: "Show in Finder"),
                                                .init(id: "open:\(finished.path)", symbol: "arrow.up.forward.app", label: "Open")]))
            } else {
                publish(ActivityEvent(source: id, kind: .ended, sessionID: key, title: "Cancelled"))
            }
        }
        active = seen
        reported = reported.filter { seen.contains($0.key) }
    }

    /// Bytes so far and, when the browser records it (Safari), the total.
    private static func progress(of url: URL) -> (Int64, Int64?) {
        let info = url.appending(path: "Info.plist")
        if let plist = NSDictionary(contentsOf: info) {
            let done = (plist["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
            let total = (plist["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
            return (done, total.flatMap { $0 > 0 ? $0 : nil })
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return (Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0), nil)
    }
}
