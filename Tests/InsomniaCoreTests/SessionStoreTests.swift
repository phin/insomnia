import XCTest
@testable import InsomniaCore

final class SessionStoreTests: XCTestCase {
    private var tmpDir: URL!
    private var store: SessionStore!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("insomnia-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = SessionStore(directory: tmpDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testWriteListReadDelete() throws {
        let now = Date().timeIntervalSince1970
        let s = SessionState(agent: .claudeCode, sessionId: "abc-123", pid: 4242,
                             cwd: "/tmp/proj", state: .working, updatedAt: now)
        try store.write(s)

        XCTAssertEqual(store.list().count, 1)
        XCTAssertEqual(store.list().first?.state, s)
        XCTAssertEqual(store.read(forKey: s.storeKey), s)

        store.delete(forKey: s.storeKey)
        XCTAssertNil(store.read(forKey: s.storeKey))
        XCTAssertTrue(store.list().isEmpty)
    }

    func testUpsertCreatesThenMutates() throws {
        try store.upsert(agent: .codex, sessionId: "s1") {
            $0.state = .working
            $0.updatedAt = 1000
        }
        XCTAssertEqual(store.list().first?.state.state, .working)

        try store.upsert(agent: .codex, sessionId: "s1") {
            $0.state = .idle
            $0.updatedAt = 2000
        }
        let loaded = store.list()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.state.state, .idle)
        XCTAssertEqual(loaded.first?.state.updatedAt, 2000)
    }

    func testDistinctAgentsWithSameSessionIdDoNotCollide() throws {
        try store.upsert(agent: .claudeCode, sessionId: "same") { $0.updatedAt = 1 }
        try store.upsert(agent: .codex, sessionId: "same") { $0.updatedAt = 2 }
        XCTAssertEqual(store.list().count, 2)
    }

    func testListSkipsTempAndUnparseableFiles() throws {
        try store.write(SessionState(agent: .claudeCode, sessionId: "good",
                                     state: .idle, updatedAt: 1))
        try Data("not json".utf8).write(to: tmpDir.appendingPathComponent(".good.999.tmp"))
        try Data("not json".utf8).write(to: tmpDir.appendingPathComponent("junk.json"))
        let listed = store.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.state.sessionId, "good")
    }

    func testSweepTempFiles() throws {
        let oldTmp = tmpDir.appendingPathComponent(".old.111.tmp")
        try Data("x".utf8).write(to: oldTmp)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-600)],
            ofItemAtPath: oldTmp.path)
        let freshTmp = tmpDir.appendingPathComponent(".fresh.222.tmp")
        try Data("x".utf8).write(to: freshTmp)

        store.sweepTempFiles(olderThan: 300)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldTmp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshTmp.path))
    }
}
