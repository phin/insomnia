import XCTest
@testable import InsomniaCore

final class ProcessTreeTests: XCTestCase {
    func testParentPIDOfCurrentProcessIsValid() {
        let ppid = ProcessTree.parentPID(of: getpid())
        XCTAssertNotNil(ppid)
        XCTAssertGreaterThan(ppid ?? 0, 0)
    }

    func testExecutableNameOfCurrentProcessIsNonEmpty() {
        let name = ProcessTree.executableName(of: getpid())
        XCTAssertNotNil(name)
        XCTAssertFalse(name?.isEmpty ?? true)
    }

    func testExecutableNameOfBogusPIDIsNil() {
        // PID 0 is the kernel; proc_pidpath should not resolve a path for it.
        XCTAssertNil(ProcessTree.executableName(of: 0))
    }

    func testFindAncestorMatchesCurrentProcess() {
        guard let myName = ProcessTree.executableName(of: getpid()) else {
            return XCTFail("could not resolve own executable name")
        }
        XCTAssertEqual(
            ProcessTree.findAncestor(from: getpid(), matching: [myName.lowercased()]),
            getpid())
    }

    func testFindAncestorReturnsNilWhenNothingMatches() {
        XCTAssertNil(ProcessTree.findAncestor(
            from: getpid(), matching: ["definitely-not-a-real-process-name-xyz"]))
    }

    func testCandidateExecutableNamesPerAgent() {
        XCTAssertTrue(ProcessTree.candidateExecutableNames(for: .codex).contains("codex"))
        XCTAssertTrue(ProcessTree.candidateExecutableNames(for: .claudeCode).contains("node"))
        XCTAssertTrue(ProcessTree.candidateExecutableNames(for: .geminiCLI).contains("node"))
    }
}

final class PowerSourceMonitorTests: XCTestCase {
    func testIsOnACPowerReturnsABoolWithoutCrashing() {
        // Can't assert the value (depends on the test machine), but the call
        // must be safe and total.
        _ = PowerSourceMonitor.isOnACPower
    }
}
