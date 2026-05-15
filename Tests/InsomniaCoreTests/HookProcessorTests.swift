import XCTest
@testable import InsomniaCore

final class HookProcessorTests: XCTestCase {
    private var tmpDir: URL!
    private var store: SessionStore!
    private var proc: HookProcessor!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("insomnia-hp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = SessionStore(directory: tmpDir)
        proc = HookProcessor(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testSessionStartCreatesIdleSession() throws {
        try proc.apply(agent: .claudeCode, event: .sessionStart,
                       sessionId: "s", cwd: "/tmp/p", pid: nil, now: 100)
        let s = store.list().first?.state
        XCTAssertEqual(s?.state, .idle)
        XCTAssertEqual(s?.cwd, "/tmp/p")
        XCTAssertEqual(s?.updatedAt, 100)
    }

    func testWorkingThenIdlePreservesEarlierData() throws {
        try proc.apply(agent: .codex, event: .working,
                       sessionId: "s", cwd: "/tmp/q", pid: 42, now: 100)
        XCTAssertEqual(store.list().first?.state.state, .working)
        XCTAssertEqual(store.list().first?.state.pid, 42)

        // Idle event without cwd/pid must not erase what working recorded.
        try proc.apply(agent: .codex, event: .idle,
                       sessionId: "s", cwd: nil, pid: nil, now: 200)
        let s = store.list().first?.state
        XCTAssertEqual(s?.state, .idle)
        XCTAssertEqual(s?.updatedAt, 200)
        XCTAssertEqual(s?.pid, 42)
        XCTAssertEqual(s?.cwd, "/tmp/q")
    }

    func testSessionEndDeletesSession() throws {
        try proc.apply(agent: .geminiCLI, event: .sessionStart,
                       sessionId: "s", cwd: nil, pid: nil, now: 1)
        XCTAssertEqual(store.list().count, 1)
        try proc.apply(agent: .geminiCLI, event: .sessionEnd,
                       sessionId: "s", cwd: nil, pid: nil, now: 2)
        XCTAssertEqual(store.list().count, 0)
    }

    func testSessionEndOnUnknownSessionIsHarmless() throws {
        try proc.apply(agent: .codex, event: .sessionEnd,
                       sessionId: "never-seen", cwd: nil, pid: nil)
        XCTAssertEqual(store.list().count, 0)
    }

    func testHookPayloadExtractsKnownFields() {
        let p = HookPayload(jsonData: Data(
            #"{"session_id":"abc","cwd":"/x","hook_event_name":"Stop"}"#.utf8))
        XCTAssertEqual(p.sessionId, "abc")
        XCTAssertEqual(p.cwd, "/x")
    }

    func testHookPayloadGarbageIsAllNil() {
        let p = HookPayload(jsonData: Data("not json at all".utf8))
        XCTAssertNil(p.sessionId)
        XCTAssertNil(p.cwd)
    }

    func testHookPayloadEmptyIsAllNil() {
        let p = HookPayload(jsonData: Data())
        XCTAssertNil(p.sessionId)
        XCTAssertNil(p.cwd)
    }

    func testHookPayloadMissingFieldsAreNil() {
        let p = HookPayload(jsonData: Data(#"{"hook_event_name":"Stop"}"#.utf8))
        XCTAssertNil(p.sessionId)
        XCTAssertNil(p.cwd)
    }
}
