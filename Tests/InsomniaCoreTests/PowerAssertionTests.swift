import XCTest
@testable import InsomniaCore

final class PowerAssertionTests: XCTestCase {
    private let testReason = "Insomnia: unit-test assertion"

    /// Whether `pmset -g assertions` currently lists our test assertion.
    private func pmsetListsTestAssertion() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).contains(testReason)
    }

    func testAcquireShowsInPmsetAndReleaseClearsIt() {
        let assertion = PowerAssertion()
        XCTAssertFalse(assertion.isHeld)
        XCTAssertFalse(pmsetListsTestAssertion())

        assertion.acquire(reason: testReason)
        XCTAssertTrue(assertion.isHeld)
        XCTAssertEqual(assertion.currentReason, testReason)
        XCTAssertTrue(pmsetListsTestAssertion(),
                      "pmset should list the assertion while it is held")

        assertion.release()
        XCTAssertFalse(assertion.isHeld)
        XCTAssertNil(assertion.currentReason)
        XCTAssertFalse(pmsetListsTestAssertion(),
                       "pmset should not list the assertion after release")
    }

    func testAcquireAndReleaseAreIdempotent() {
        let assertion = PowerAssertion()
        assertion.acquire(reason: testReason)
        assertion.acquire(reason: testReason)   // no-op
        XCTAssertTrue(assertion.isHeld)
        assertion.release()
        assertion.release()                     // no-op
        XCTAssertFalse(assertion.isHeld)
    }

    func testReacquireWithNewReasonUpdatesReason() {
        let assertion = PowerAssertion()
        assertion.acquire(reason: testReason)
        assertion.acquire(reason: testReason + " (updated)")
        XCTAssertTrue(assertion.isHeld)
        XCTAssertEqual(assertion.currentReason, testReason + " (updated)")
        assertion.release()
    }

    func testApplyDecisionTogglesAssertion() {
        let assertion = PowerAssertion()
        assertion.apply(ReconcileDecision(shouldKeepAwake: true, reason: testReason,
                                          activeSessions: [], filesToDelete: []))
        XCTAssertTrue(assertion.isHeld)
        assertion.apply(ReconcileDecision(shouldKeepAwake: false, reason: "Insomnia: idle",
                                          activeSessions: [], filesToDelete: []))
        XCTAssertFalse(assertion.isHeld)
    }
}
