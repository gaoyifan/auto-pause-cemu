import AppKit
import Darwin
import Foundation
import IOKit.hid

public struct ControllerSelector: Sendable {
    public var name: String?
    public var vendorID: Int?
    public var productID: Int?
    public var anyGamepad: Bool

    public init(
        name: String? = "DualSense Wireless Controller",
        vendorID: Int? = 0x054c,
        productID: Int? = 0x0ce6,
        anyGamepad: Bool = false
    ) {
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.anyGamepad = anyGamepad
    }
}

public final class BluetoothControllerDetector {
    private let manager: IOHIDManager
    private let selector: ControllerSelector
    private let runLoop: CFRunLoop

    public init(selector: ControllerSelector) throws {
        self.selector = selector
        runLoop = CFRunLoopGetMain()
        manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(manager, nil)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw MonitorError.hidManagerOpen(result)
        }
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
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
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

        if selector.anyGamepad {
            let page = intProperty(device, kIOHIDPrimaryUsagePageKey)
            let usage = intProperty(device, kIOHIDPrimaryUsageKey)
            return page == kHIDPage_GenericDesktop
                && (usage == kHIDUsage_GD_GamePad || usage == kHIDUsage_GD_Joystick)
        }

        if let expectedName = selector.name,
           let actualName = stringProperty(device, kIOHIDProductKey),
           actualName.caseInsensitiveCompare(expectedName) == .orderedSame {
            return true
        }

        if let expectedVendor = selector.vendorID,
           let expectedProduct = selector.productID {
            return intProperty(device, kIOHIDVendorIDKey) == expectedVendor
                && intProperty(device, kIOHIDProductIDKey) == expectedProduct
        }

        return false
    }

    private func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }
}

public struct CemuProcessFinder {
    public var bundleIdentifier: String
    public var executableName: String

    public init(
        bundleIdentifier: String = "info.cemu.Cemu",
        executableName: String = "Cemu"
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
    }

    public func processes() -> [TargetProcess] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            let matchesBundle = application.bundleIdentifier == bundleIdentifier
            let matchesExecutable = application.executableURL?.lastPathComponent
                .caseInsensitiveCompare(executableName) == .orderedSame
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

public enum MonitorError: LocalizedError {
    case hidManagerOpen(IOReturn)

    public var errorDescription: String? {
        switch self {
        case let .hidManagerOpen(code):
            return "无法打开 HID 管理器（IOKit 错误 \(code)）"
        }
    }
}
