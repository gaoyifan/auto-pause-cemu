import Darwin
import Foundation

public struct ManagedPIDStore: Sendable {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AutoPauseCemu", isDirectory: true)
            .appendingPathComponent("managed-pids.json")
    }

    public func load() -> Set<pid_t> {
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([Int32].self, from: data) else {
            return []
        }
        return Set(values)
    }

    public func save(_ pids: Set<pid_t>) throws {
        if pids.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(pids.sorted())
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
