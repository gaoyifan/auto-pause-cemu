import Darwin
import Foundation

public struct TargetProcess: Equatable, Sendable {
    public let pid: pid_t
    public let isStopped: Bool

    public init(pid: pid_t, isStopped: Bool) {
        self.pid = pid
        self.isStopped = isStopped
    }
}

public enum ProcessAction: Equatable, Sendable {
    case pause(pid_t)
    case resume(pid_t)
}

/// Tracks only processes paused by this program, so a process that was already
/// stopped by the user is never resumed accidentally.
public struct PauseState: Sendable {
    public private(set) var managedPIDs: Set<pid_t> = []

    public init(managedPIDs: Set<pid_t> = []) {
        self.managedPIDs = managedPIDs
    }

    public mutating func reconcile(
        controllerConnected: Bool,
        processes: [TargetProcess],
        perform: (ProcessAction) -> Bool
    ) {
        let livePIDs = Set(processes.map(\.pid))
        managedPIDs.formIntersection(livePIDs)

        if controllerConnected {
            for pid in managedPIDs.sorted() where perform(.resume(pid)) {
                managedPIDs.remove(pid)
            }
            return
        }

        for process in processes.sorted(by: { $0.pid < $1.pid }) {
            // A process stopped before we observed it is not ours to resume.
            if process.isStopped && !managedPIDs.contains(process.pid) {
                continue
            }

            // Re-apply SIGSTOP if something resumed a process while the
            // controller is still disconnected.
            if !process.isStopped, perform(.pause(process.pid)) {
                managedPIDs.insert(process.pid)
            }
        }
    }

    public mutating func resumeAll(
        liveTargetPIDs: Set<pid_t>,
        perform: (ProcessAction) -> Bool
    ) {
        managedPIDs.formIntersection(liveTargetPIDs)
        for pid in managedPIDs.sorted() where perform(.resume(pid)) {
            managedPIDs.remove(pid)
        }
    }
}
