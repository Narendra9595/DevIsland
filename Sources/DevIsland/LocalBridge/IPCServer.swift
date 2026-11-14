import Foundation

/// Listens on a Unix domain socket for one-line JSON messages from CLI hooks.
/// Security: owner-only permissions (0600), a 1-second read timeout and a 256 KB limit.
final class IPCServer: @unchecked Sendable {
    enum StartResult: Equatable {
        case listening
        /// Another DevIsland is already listening on this socket.
        case alreadyRunning
        case failed(String)
    }

    static let maxMessageSize = 256 * 1024 // long Claude messages arrive in one piece in some modes

    private let path: String
    private let onMessage: @Sendable (Data) -> Void
    private let onReject: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "DevIsland.IPCServer")
    private var listener: DispatchSourceRead?

    init(path: String,
         onMessage: @escaping @Sendable (Data) -> Void,
         onReject: @escaping @Sendable (String) -> Void) {
        self.path = path
        self.onMessage = onMessage
        self.onReject = onReject
    }

    func start() -> StartResult {
        if FileManager.default.fileExists(atPath: path) {
            if let fd = Self.connect(to: path) {
                close(fd)
                return .alreadyRunning
            }
            unlink(path) // left over from a previous run
        }

        guard var address = Self.address(for: path) else { return .failed("The socket path is too long.") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failed("Couldn't create a socket.") }

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            return .failed(reason)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection(on: fd) }
        source.setCancelHandler { close(fd) }
        source.resume()
        listener = source
        return .listening
    }

    func stop() {
        listener?.cancel()
        listener = nil
        unlink(path)
    }

    /// Sends one message to a running DevIsland (used to hand off to an existing instance).
    @discardableResult
    static func send(_ message: Data, to path: String) -> Bool {
        guard let fd = connect(to: path) else { return false }
        defer { close(fd) }
        var payload = message
        if payload.last != UInt8(ascii: "\n") { payload.append(UInt8(ascii: "\n")) }
        let written = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        return written == payload.count
    }

    private func acceptConnection(on fd: Int32) {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= Self.maxMessageSize {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
            if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                data = data[..<newline]
                break
            }
        }

        if data.count > Self.maxMessageSize {
            onReject("Rejected a hook message larger than 256 KB")
        } else if !data.isEmpty {
            onMessage(Data(data))
        }
    }

    private static func connect(to path: String) -> Int32? {
        guard var address = address(for: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        return address
    }
}
