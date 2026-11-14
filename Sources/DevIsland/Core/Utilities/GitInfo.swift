import Foundation

/// Reads the current git branch of a working directory (no git binary needed).
enum GitInfo {
    static func branch(at path: String) -> String? {
        let fileManager = FileManager.default
        var directory = path
        for _ in 0..<10 {
            let git = (directory as NSString).appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: git, isDirectory: &isDirectory) {
                guard let head = headFile(git: git, isDirectory: isDirectory.boolValue, in: directory),
                      let contents = try? String(contentsOfFile: head, encoding: .utf8) else { return nil }
                let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "ref: refs/heads/"
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : String(line.prefix(7))
            }
            let parent = (directory as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == directory { break }
            directory = parent
        }
        return nil
    }

    /// Worktrees and submodules use a `.git` file that points at the real git directory.
    private static func headFile(git: String, isDirectory: Bool, in directory: String) -> String? {
        if isDirectory { return (git as NSString).appendingPathComponent("HEAD") }
        guard let text = try? String(contentsOfFile: git, encoding: .utf8),
              let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:") else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let gitDirectory = target.hasPrefix("/") ? target : (directory as NSString).appendingPathComponent(target)
        return (gitDirectory as NSString).appendingPathComponent("HEAD")
    }
}
