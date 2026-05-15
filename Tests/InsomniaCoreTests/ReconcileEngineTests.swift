import XCTest
@testable import InsomniaCore

final class ReconcileEngineTests: XCTestCase {

    private let now: TimeInterval = 1_000_000
    private let allAgents: Set<AgentKind> = [.claudeCode, .codex, .geminiCLI]

    /// Config with the documented defaults.
    private func config(onACOnly: Bool = false,
                        grace: TimeInterval = 300,
                        cap: TimeInterval = 14_400,
                        idleReap: TimeInterval = 3_600) -> Config {
        Config(gracePeriodSeconds: grace, absoluteSafetyCapSeconds: cap,
               idleReapSeconds: idleReap, onACOnly: onACOnly)
    }

    private func session(_ agent: AgentKind = .claudeCode,
                         id: String = "s",
                         pid: Int32? = nil,
                         state: SessionActivityState,
                         ageSeconds: TimeInterval) -> LoadedSession {
        LoadedSession(
            state: SessionState(agent: agent, sessionId: id, pid: pid, cwd: "/tmp/\(id)",
                                state: state, updatedAt: now - ageSeconds),
            url: URL(fileURLWithPath: "/tmp/\(agent.rawValue)-\(id).json"))
    }

    private func reconcile(_ sessions: [LoadedSession],
                           config cfg: Config? = nil,
                           followed: Set<AgentKind>? = nil,
                           override: ManualOverride = .none,
                           onAC: Bool = true,
                           alive: @escaping (Int32) -> Bool = { _ in true }) -> ReconcileDecision {
        ReconcileEngine.reconcile(sessions: sessions, config: cfg ?? config(),
                                  followedAgents: followed ?? allAgents,
                                  manualOverride: override, onACPower: onAC,
                                  now: now, isProcessAlive: alive)
    }

    // MARK: - Basic activity

    func testNoSessionsMeansSleep() {
        let d = reconcile([])
        XCTAssertFalse(d.shouldKeepAwake)
        XCTAssertEqual(d.reason, "Insomnia: idle")
        XCTAssertTrue(d.activeSessions.isEmpty)
        XCTAssertTrue(d.filesToDelete.isEmpty)
    }

    func testWorkingSessionKeepsAwake() {
        let d = reconcile([session(state: .working, ageSeconds: 1)])
        XCTAssertTrue(d.shouldKeepAwake)
        XCTAssertEqual(d.activeSessions.count, 1)
        XCTAssertEqual(d.activeSessions.first?.displayState, .working)
        XCTAssertTrue(d.reason.contains("Claude Code working"))
    }

    func testWorkingSessionWithNilPidIsKept() {
        // No PID -> can't liveness-check -> trust the state.
        let d = reconcile([session(pid: nil, state: .working, ageSeconds: 1)],
                          alive: { _ in false })
        XCTAssertTrue(d.shouldKeepAwake)
        XCTAssertTrue(d.filesToDelete.isEmpty)
    }

    func testWorkingSessionWithDeadPidIsReaped() {
        let s = session(pid: 4242, state: .working, ageSeconds: 1)
        let d = reconcile([s], alive: { _ in false })
        XCTAssertFalse(d.shouldKeepAwake)
        XCTAssertEqual(d.filesToDelete, [s.url])
    }

    // MARK: - Grace period

    func testIdleWithinGraceKeepsAwakeWithCountdown() {
        let d = reconcile([session(state: .idle, ageSeconds: 120)])  // grace = 300
        XCTAssertTrue(d.shouldKeepAwake)
        XCTAssertEqual(d.activeSessions.first?.displayState, .grace(secondsRemaining: 180))
        XCTAssertTrue(d.reason.contains("grace period"))
    }

    func testIdlePastGraceButNotReapableSleepsAndKeepsFile() {
        let s = session(state: .idle, ageSeconds: 600)  // > grace 300, < idleReap 3600
        let d = reconcile([s])
        XCTAssertFalse(d.shouldKeepAwake)
        XCTAssertTrue(d.activeSessions.isEmpty)
        XCTAssertTrue(d.filesToDelete.isEmpty, "file kept — session may resume")
    }

    func testIdlePastIdleReapIsDeleted() {
        let s = session(state: .idle, ageSeconds: 4_000)  // > idleReap 3600
        let d = reconcile([s])
        XCTAssertFalse(d.shouldKeepAwake)
        XCTAssertEqual(d.filesToDelete, [s.url])
    }

    // MARK: - Safety cap

    func testWorkingSessionOverSafetyCapIsReaped() {
        let s = session(pid: 1, state: .working, ageSeconds: 20_000)  // > cap 14400
        let d = reconcile([s], alive: { _ in true })
        XCTAssertFalse(d.shouldKeepAwake)
        XCTAssertEqual(d.filesToDelete, [s.url])
    }

    // MARK: - Unfollowed agents

    func testUnfollowedAgentSessionIsIgnoredButRecentFileKept() {
        let s = session(.codex, state: .working, ageSeconds: 10)
        let d = reconcile([s], followed: [.claudeCode])
        XCTAssertFalse(d.shouldKeepAwake)
        XCTAssertTrue(d.filesToDelete.isEmpty)
    }

    func testUnfollowedAgentStaleFileIsReaped() {
        let s = session(.codex, state: .idle, ageSeconds: 5_000)  // > idleReap
        let d = reconcile([s], followed: [.claudeCode])
        XCTAssertEqual(d.filesToDelete, [s.url])
    }

    // MARK: - Manual overrides

    func testForceAwakeKeepsAwakeWithNoSessions() {
        let d = reconcile([], override: .forceAwake)
        XCTAssertTrue(d.shouldKeepAwake)
        XCTAssertEqual(d.reason, "Insomnia: manual override (keep awake)")
    }

    func testForceAllowSleepOverridesWorkingSession() {
        let d = reconcile([session(state: .working, ageSeconds: 1)], override: .forceAllowSleep)
        XCTAssertFalse(d.shouldKeepAwake)
    }

    // MARK: - On-AC-only

    func testOnACOnlyOnBatterySleepsDespiteWork() {
        let d = reconcile([session(state: .working, ageSeconds: 1)],
                          config: config(onACOnly: true), onAC: false)
        XCTAssertFalse(d.shouldKeepAwake)
    }

    func testOnACOnlyOnPowerStillKeepsAwake() {
        let d = reconcile([session(state: .working, ageSeconds: 1)],
                          config: config(onACOnly: true), onAC: true)
        XCTAssertTrue(d.shouldKeepAwake)
    }

    func testForceAwakeBeatsOnACOnlyOnBattery() {
        let d = reconcile([], config: config(onACOnly: true), override: .forceAwake, onAC: false)
        XCTAssertTrue(d.shouldKeepAwake)
    }

    // MARK: - Multiple sessions

    func testMultipleWorkingSessionsCountedInReason() {
        let d = reconcile([
            session(.claudeCode, id: "a", state: .working, ageSeconds: 1),
            session(.codex, id: "b", state: .working, ageSeconds: 2),
        ])
        XCTAssertTrue(d.shouldKeepAwake)
        XCTAssertEqual(d.activeSessions.count, 2)
        XCTAssertTrue(d.reason.contains("(2 sessions)"))
        XCTAssertTrue(d.reason.contains("Claude Code"))
        XCTAssertTrue(d.reason.contains("Codex"))
    }

    func testWorkingTakesPrecedenceOverGraceInReason() {
        let d = reconcile([
            session(id: "a", state: .working, ageSeconds: 1),
            session(id: "b", state: .idle, ageSeconds: 100),
        ])
        XCTAssertTrue(d.shouldKeepAwake)
        XCTAssertTrue(d.reason.contains("working"))
        XCTAssertEqual(d.activeSessions.count, 2)
    }
}
