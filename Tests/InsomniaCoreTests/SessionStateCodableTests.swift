import XCTest
@testable import InsomniaCore

final class SessionStateCodableTests: XCTestCase {
    func testRoundTrip() throws {
        let s = SessionState(agent: .geminiCLI, sessionId: "x", pid: 7,
                             cwd: "/a", state: .working, updatedAt: 123.0)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SessionState.self, from: data)
        XCTAssertEqual(s, back)
    }

    func testNilFieldsRoundTrip() throws {
        let s = SessionState(agent: .claudeCode, sessionId: "x", pid: nil,
                             cwd: nil, state: .idle, updatedAt: 1)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SessionState.self, from: data)
        XCTAssertEqual(s, back)
        XCTAssertNil(back.pid)
    }

    func testStoreKeyIsFilesystemSafeAndAgentScoped() {
        let s = SessionState(agent: .claudeCode, sessionId: "weird/id:with spaces",
                             state: .idle, updatedAt: 0)
        XCTAssertFalse(s.storeKey.contains("/"))
        XCTAssertFalse(s.storeKey.contains(":"))
        XCTAssertFalse(s.storeKey.contains(" "))
        XCTAssertTrue(s.storeKey.hasPrefix("claude-code-"))
    }

    func testConfigTolerantDecodingOfMissingKeys() throws {
        let json = #"{"version":1,"gracePeriodSeconds":120}"#
        let cfg = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(cfg.gracePeriodSeconds, 120)
        XCTAssertEqual(cfg.onACOnly, Config.default.onACOnly)
        XCTAssertEqual(cfg.idleReapSeconds, Config.default.idleReapSeconds)
    }

    func testConfigRoundTrip() throws {
        let cfg = Config(gracePeriodSeconds: 600, absoluteSafetyCapSeconds: 7200,
                         idleReapSeconds: 1800, onACOnly: true)
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(cfg, back)
    }
}
