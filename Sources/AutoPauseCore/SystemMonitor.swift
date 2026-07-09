import AppKit
import Darwin
import Foundation
import IOKit.hid

public final class BluetoothControllerDetector {
    private let manager: IOHIDManager
    private let anyGamepad: Bool
    private let runLoop: CFRunLoop

    public init(anyGamepad: Bool = false) {
        self.anyGamepad = anyGamepad
        runLoop = CFRunLoopGetMain()
        manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(manager, nil)
        // Device enumeration does not require opening every HID device.
        // IOHIDManagerOpen is intentionally avoided because macOS denies it
        // to background LaunchAgents without Input Monitoring permission.
        // Scheduling keeps IOHIDManager's device set current when a controller
        // connects or disconnects after the program has started.
        IOHIDManagerScheduleWithRunLoop(
            manager,
            runLoop,
            CFRunLoopMode.commonModes.rawValue
        )
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            runLoop,
            CFRunLoopMode.commonModes.rawValue
        )
    }

    public func isConnected() -> Bool {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return false
        }
        return devices.contains(where: matches)
    }

    private func matches(_ device: IOHIDDevice) -> Bool {
        guard let transport = stringProperty(device, kIOHIDTransportKey),
              transport.caseInsensitiveCompare("Bluetooth") == .orderedSame else {
            return false
        }

        if anyGamepad {
            let page = intProperty(device, kIOHIDPrimaryUsagePageKey)
            let usage = intProperty(device, kIOHIDPrimaryUsageKey)
            return page == kHIDPage_GenericDesktop
                && (usage == kHIDUsage_GD_GamePad || usage == kHIDUsage_GD_Joystick)
        }

        if stringProperty(device, kIOHIDProductKey)?
            .caseInsensitiveCompare("DualSense Wireless Controller") == .orderedSame {
            return true
        }

        return intProperty(device, kIOHIDVendorIDKey) == 0x054c
            && intProperty(device, kIOHIDProductIDKey) == 0x0ce6
    }

    private func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }
}

public struct CemuProcessFinder {
    public init() {}

    public func processes() -> [TargetProcess] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            let matchesBundle = application.bundleIdentifier == "info.cemu.Cemu"
            let matchesExecutable = application.executableURL?.lastPathComponent
                .caseInsensitiveCompare("Cemu") == .orderedSame
            guard matchesBundle || matchesExecutable else { return nil }

            let pid = application.processIdentifier
            guard pid > 0, let stopped = processIsStopped(pid) else { return nil }
            return TargetProcess(pid: pid, isStopped: stopped)
        }
    }

    private func processIsStopped(_ pid: pid_t) -> Bool? {
        var info = proc_bsdinfo()
        let bytes = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        guard bytes == MemoryLayout<proc_bsdinfo>.size else { return nil }
        return info.pbi_status == UInt32(SSTOP)
    }
}
