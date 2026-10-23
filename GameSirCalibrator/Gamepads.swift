import Foundation
import IOKit.hid
import Observation

/// One connected controller. `axes` holds every analog axis, normalized to -1...1
/// (HID convention: +x right, +y down), keyed by HID usage.
@Observable
final class Gamepad: Identifiable {
    static let axisNames: [UInt32: String] = [
        0x30: "X", 0x31: "Y", 0x32: "Z", 0x33: "Rx", 0x34: "Ry", 0x35: "Rz",
        0x36: "Slider", 0x37: "Dial", 0x38: "Wheel",
        0xC4: "Accelerator", 0xC5: "Brake",  // Simulation page, used by Xbox pads over Bluetooth
    ]

    @ObservationIgnored let device: IOHIDDevice
    let name: String
    let isSwitchPro: Bool
    var axes: [UInt32: Double] = [:]
    /// Which input path is feeding `axes`, shown in the UI to help with bug reports.
    var source = "HID axes"
    /// DS4-style pads put the right stick on Z/Rz, Switch-style pads on Rx/Ry.
    var rightUsesRxRy: Bool

    var id: ObjectIdentifier { ObjectIdentifier(device) }

    init(device: IOHIDDevice) {
        self.device = device
        name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown controller"
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        isSwitchPro = (vendor == 0x057E && product == 0x2009) || name == "Pro Controller"

        var axes: [UInt32: Double] = [:]
        let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] ?? []
        for element in elements where Self.isAxis(element) {
            var value = Unmanaged<IOHIDValue>.passUnretained(IOHIDValueCreateWithIntegerValue(nil, element, 0, 0))
            let current = IOHIDDeviceGetValue(device, element, &value) == kIOReturnSuccess
                ? Self.normalized(value.takeUnretainedValue()) : 0
            axes[IOHIDElementGetUsage(element)] = current
        }
        self.axes = axes
        rightUsesRxRy = axes[0x32] == nil || axes[0x35] == nil
    }

    var left: SIMD2<Double> { SIMD2(axes[0x30] ?? 0, axes[0x31] ?? 0) }
    var rightUsages: (x: UInt32, y: UInt32) { rightUsesRxRy ? (0x33, 0x34) : (0x32, 0x35) }
    var right: SIMD2<Double> { SIMD2(axes[rightUsages.x] ?? 0, axes[rightUsages.y] ?? 0) }
    /// Both right-stick layouts are present, so the user may need to pick one.
    var rightIsAmbiguous: Bool { [0x32, 0x35, 0x33, 0x34].allSatisfy { axes[$0] != nil } }
    /// Every axis not used by a stick, as 0...1 (triggers, sliders).
    var triggers: [(name: String, value: Double)] {
        let used: Set<UInt32> = [0x30, 0x31, rightUsages.x, rightUsages.y]
        return axes.filter { !used.contains($0.key) }.sorted { $0.key < $1.key }
            .map { (Self.axisNames[$0.key] ?? "Axis", ($0.value + 1) / 2) }
    }

    static func isAxis(_ element: IOHIDElement) -> Bool {
        let page = IOHIDElementGetUsagePage(element), usage = IOHIDElementGetUsage(element)
        return switch page {
        case UInt32(kHIDPage_GenericDesktop): (0x30...0x38).contains(usage)
        case UInt32(kHIDPage_Simulation): usage == 0xC4 || usage == 0xC5
        default: false
        }
    }

    static func normalized(_ value: IOHIDValue) -> Double {
        let element = IOHIDValueGetElement(value)
        let lo = IOHIDElementGetLogicalMin(element), hi = IOHIDElementGetLogicalMax(element)
        guard hi > lo else { return 0 }
        return Double(IOHIDValueGetIntegerValue(value) - lo) / Double(hi - lo) * 2 - 1
    }

    /// Switch Pro "full" input report 0x30: each stick is two packed 12-bit values
    /// (left at bytes 6...8, right at 9...11, report ID at byte 0). Nintendo's Y grows upward,
    /// so it's flipped to match HID's down-positive Y.
    /// ponytail: centred on the nominal 2048; read the pad's SPI factory calibration if pads turn out to centre elsewhere.
    nonisolated static func switchProSticks(_ report: [UInt8]) -> (left: SIMD2<Double>, right: SIMD2<Double>)? {
        guard report.count >= 12, report[0] == 0x30 else { return nil }
        func stick(_ i: Int) -> SIMD2<Double> {
            let x = Int(report[i]) | Int(report[i + 1] & 0x0F) << 8
            let y = Int(report[i + 1] >> 4) | Int(report[i + 2]) << 4
            return SIMD2(Double(x - 2048) / 2048, Double(2048 - y) / 2048)
        }
        return (stick(6), stick(9))
    }
}

/// Watches for gamepads with IOHIDManager. Devices are opened without seizing, so games still see them.
@Observable
final class Gamepads {
    private(set) var pads: [Gamepad] = []
    private(set) var error: String?
    @ObservationIgnored private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    init() {
        let usages = [kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick, kHIDUsage_GD_MultiAxisController]
        let matching = usages.map { [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            // Skip virtual pads (e.g. Steam Input's "GamePad-1"): they copy a real controller and would show up twice.
            guard IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String != "Virtual" else { return }
            MainActor.assumeIsolated { Gamepads.from(context).pads.append(Gamepad(device: device)) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            MainActor.assumeIsolated { Gamepads.from(context).pads.removeAll { $0.device == device } }
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            MainActor.assumeIsolated { Gamepads.from(context).received(value) }
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, _, report, length in
            guard let sender else { return }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { Gamepads.from(context).received(bytes, from: device) }
        }, context)

        // Common modes keep values flowing while a window is being dragged or resized.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            error = "Couldn't open HID devices (IOReturn \(String(result, radix: 16))). Check System Settings › Privacy & Security › Input Monitoring."
        }
    }

    private static func from(_ context: UnsafeMutableRawPointer?) -> Gamepads {
        Unmanaged<Gamepads>.fromOpaque(context!).takeUnretainedValue()
    }

    private func pad(for device: IOHIDDevice) -> Gamepad? { pads.first { $0.device == device } }

    private func received(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard Gamepad.isAxis(element), let pad = pad(for: IOHIDElementGetDevice(element)) else { return }
        pad.axes[IOHIDElementGetUsage(element)] = Gamepad.normalized(value)
    }

    private func received(_ report: [UInt8], from device: IOHIDDevice) {
        guard let pad = pad(for: device), pad.isSwitchPro,
              let sticks = Gamepad.switchProSticks(report) else { return }
        // Over USB these arrive ~1000 times a second; writing only changes keeps an idle pad from redrawing the window.
        let source = "Switch Pro full reports (0x30)"
        if pad.source != source { pad.source = source }
        let values: [UInt32: Double] = [0x30: sticks.left.x, 0x31: sticks.left.y, 0x33: sticks.right.x, 0x34: sticks.right.y]
        for (usage, value) in values where pad.axes[usage] != value { pad.axes[usage] = value }
    }
}
