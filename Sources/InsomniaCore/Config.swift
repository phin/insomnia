import Foundation

/// User preferences, persisted to
/// `~/Library/Application Support/Insomnia/config.json`.
///
/// Note: which agents are *followed* is **not** stored here — it's derived
/// from whether each agent's integration is actually installed (see
/// `AgentInstaller.status`). That avoids the app and the `insomnia-hook` CLI
/// fighting over a shared config field.
public struct Config: Codable, Equatable, Sendable {
    public var version: Int
    /// Seconds to keep the Mac awake after an agent turn ends.
    public var gracePeriodSeconds: TimeInterval
    /// Absolute cap: a session older than this is reaped no matter what
    /// (handles a CLI that crashed without sending an end event).
    public var absoluteSafetyCapSeconds: TimeInterval
    /// An idle session file older than this is deleted to keep the directory tidy.
    public var idleReapSeconds: TimeInterval
    /// When true, never hold the assertion while on battery (unless force-awake).
    public var onACOnly: Bool

    public static let currentVersion = 1

    public static let `default` = Config(
        version: currentVersion,
        gracePeriodSeconds: 300,
        absoluteSafetyCapSeconds: 14_400,
        idleReapSeconds: 3_600,
        onACOnly: false)

    enum CodingKeys: String, CodingKey {
        case version, gracePeriodSeconds, absoluteSafetyCapSeconds
        case idleReapSeconds, onACOnly
    }

    public init(version: Int = Config.currentVersion,
                gracePeriodSeconds: TimeInterval,
                absoluteSafetyCapSeconds: TimeInterval,
                idleReapSeconds: TimeInterval,
                onACOnly: Bool) {
        self.version = version
        self.gracePeriodSeconds = gracePeriodSeconds
        self.absoluteSafetyCapSeconds = absoluteSafetyCapSeconds
        self.idleReapSeconds = idleReapSeconds
        self.onACOnly = onACOnly
    }

    /// Tolerant decoder: missing keys fall back to defaults so config files
    /// written by older or newer versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        gracePeriodSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .gracePeriodSeconds)
            ?? d.gracePeriodSeconds
        absoluteSafetyCapSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .absoluteSafetyCapSeconds)
            ?? d.absoluteSafetyCapSeconds
        idleReapSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .idleReapSeconds)
            ?? d.idleReapSeconds
        onACOnly = try c.decodeIfPresent(Bool.self, forKey: .onACOnly) ?? d.onACOnly
    }

    /// Load from disk, falling back to `.default` if the file is missing or unreadable.
    public static func load() -> Config {
        guard let data = try? Data(contentsOf: Paths.configFile),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return .default
        }
        return config
    }

    /// Persist to disk atomically. Failures are silently ignored — config is
    /// best-effort and reverts to `.default` on next load.
    public func save() {
        try? Paths.ensureAppSupportDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Paths.configFile, options: .atomic)
    }
}
