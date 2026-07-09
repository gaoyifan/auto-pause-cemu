import AutoPauseCore
import Foundation
import XCTest

final class PauseStateTests: XCTestCase {
    func testDisconnectedControllerPausesRunningCemu() {
        var state = PauseState()
        var actions: [ProcessAction] = []

        state.reconcile(
            controllerConnected: false,
            processes: [TargetProcess(pid: 42, isStopped: false)]
        ) {
            actions.append($0)
            return true
        }

        XCTAssertEqual(actions, [.pause(42)])
        XCTAssertEqual(state.managedPIDs, [42])
    }

    func testReconnectResumesOnlyProcessPausedByUs() {
        var state = PauseState()
        state.reconcile(
            controllerConnected: false,
            processes: [
                TargetProcess(pid: 42, isStopped: false),
                TargetProcess(pid: 43, isStopped: true),
            ],
            perform: { _ in true }
        )

        var actions: [ProcessAction] = []
        state.reconcile(
            controllerConnected: true,
            processes: [
                TargetProcess(pid: 42, isStopped: true),
                TargetProcess(pid: 43, isStopped: true),
            ]
        ) {
            actions.append($0)
            return true
        }

        XCTAssertEqual(actions, [.resume(42)])
        XCTAssertTrue(state.managedPIDs.isEmpty)
    }

    func testFailedPauseIsNotTracked() {
        var state = PauseState()
        state.reconcile(
            controllerConnected: false,
            processes: [TargetProcess(pid: 42, isStopped: false)],
            perform: { _ in false }
        )
        XCTAssertTrue(state.managedPIDs.isEmpty)
    }

    func testManagedProcessIsPausedAgainIfExternallyResumed() {
        var state = PauseState()
        state.reconcile(
            controllerConnected: false,
            processes: [TargetProcess(pid: 42, isStopped: false)],
            perform: { _ in true }
        )

        var actions: [ProcessAction] = []
        state.reconcile(
            controllerConnected: false,
            processes: [TargetProcess(pid: 42, isStopped: false)]
        ) {
            actions.append($0)
            return true
        }

        XCTAssertEqual(actions, [.pause(42)])
        XCTAssertEqual(state.managedPIDs, [42])
    }

    func testExitedProcessIsForgottenWithoutSignal() {
        var state = PauseState()
        state.reconcile(
            controllerConnected: false,
            processes: [TargetProcess(pid: 42, isStopped: false)],
            perform: { _ in true }
        )

        var actions: [ProcessAction] = []
        state.reconcile(controllerConnected: true, processes: []) {
            actions.append($0)
            return true
        }

        XCTAssertTrue(actions.isEmpty)
        XCTAssertTrue(state.managedPIDs.isEmpty)
    }

    func testShutdownResumesManagedLiveProcess() {
        var state = PauseState()
        state.reconcile(
            controllerConnected: false,
            processes: [TargetProcess(pid: 42, isStopped: false)],
            perform: { _ in true }
        )

        var actions: [ProcessAction] = []
        state.resumeAll(liveTargetPIDs: [42]) {
            actions.append($0)
            return true
        }

        XCTAssertEqual(actions, [.resume(42)])
        XCTAssertTrue(state.managedPIDs.isEmpty)
    }

    func testManagedPIDStoreRoundTripAndClear() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("managed-pids.json")
        let store = ManagedPIDStore(url: url)
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save([42, 43])
        XCTAssertEqual(store.load(), [42, 43])

        try store.save([])
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
