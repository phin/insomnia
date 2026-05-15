import Foundation

/// A `SessionState` paired with the file it was loaded from.
public struct LoadedSession: Equatable, Sendable {
    public let state: SessionState
    public let url: URL
    public init(state: SessionState, url: URL) {
        self.state = state
        self.url = url
    }
}

/// Reads and writes per-session JSON files in a directory. The directory is
/// injectable so tests can run against a temp directory.
public struct SessionStore {
    public let directory: URL

    public init(directory: URL = Paths.sessionsDir) {
        self.directory = directory
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).json", isDirectory: false)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    /// Atomically write a session file: write a pid-tagged temp file, then
    /// `rename()` it over the target. The rename is a directory-level event,
    /// which is what triggers the menu bar app's directory watcher.
    public func write(_ state: SessionState) throws {
        try ensureDirectory()
        let data = try encoder.encode(state)
        let target = fileURL(forKey: state.storeKey)
        let tmp = directory.appendingPathComponent(
            ".\(state.storeKey).\(ProcessInfo.processInfo.processIdentifier).tmp",
            isDirectory: false)
        try data.write(to: tmp, options: [])
        if rename(tmp.path, target.path) != 0 {
            let code = errno
            try? FileManager.default.removeItem(at: tmp)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey:
                            "rename failed: \(String(cString: strerror(code)))"])
        }
    }

    public func read(forKey key: String) -> SessionState? {
        try? read(url: fileURL(forKey: key))
    }

    public func read(url: URL) throws -> SessionState {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SessionState.self, from: data)
    }

    /// Every parseable session file in the directory. Skips dotfiles, temp
    /// files, and anything that isn't valid `SessionState` JSON.
    public func list() -> [LoadedSession] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        var result: [LoadedSession] = []
        for url in entries {
            guard url.pathExtension == "json",
                  !url.lastPathComponent.hasPrefix(".") else { continue }
            if let state = try? read(url: url) {
                result.append(LoadedSession(state: state, url: url))
            }
        }
        return result
    }

    public func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    public func delete(forKey key: String) {
        delete(fileURL(forKey: key))
    }

    /// Read-modify-write a session file, creating an idle session if absent.
    public func upsert(agent: AgentKind,
                       sessionId: String,
                       mutate: (inout SessionState) -> Void) throws {
        let key = SessionState.storeKey(agent: agent, sessionId: sessionId)
        var state = read(forKey: key)
            ?? SessionState(agent: agent, sessionId: sessionId, state: .idle,
                            updatedAt: Date().timeIntervalSince1970)
        mutate(&state)
        try write(state)
    }

    /// Remove stale `.<key>.<pid>.tmp` files left behind by killed processes.
    public func sweepTempFiles(olderThan maxAge: TimeInterval, now: Date = Date()) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in entries where url.lastPathComponent.hasPrefix(".")
            && url.pathExtension == "tmp" {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let mod, now.timeIntervalSince(mod) > maxAge {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
