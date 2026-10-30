import Foundation
import IOKit
import IOKit.ps

struct MacPowerTelemetry {
    let systemWatts: Double?
    let inputWatts: Double?
    let inputCounter: UInt64?
    let systemCounter: UInt64?
    let externalPowerConnected: Bool?
    let isCharging: Bool?

    init(values: [String: Any], externalPowerConnected: Bool?, isCharging: Bool? = nil) {
        systemWatts = Self.watts(values["SystemLoad"])
        inputWatts = Self.watts(values["SystemPowerIn"])
        inputCounter = Self.counter(values["SystemPowerInAccumulatorCount"])
        systemCounter = Self.counter(values["SystemLoadAccumulatorCount"])
        self.externalPowerConnected = externalPowerConnected
        self.isCharging = isCharging
    }

    private static func number(_ value: Any?) -> NSNumber? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value
    }

    private static func watts(_ value: Any?) -> Double? {
        guard let number = number(value)?.doubleValue, number.isFinite, number >= 0 else { return nil }
        return number / 1_000
    }

    private static func counter(_ value: Any?) -> UInt64? {
        number(value).flatMap { UInt64($0.stringValue) }
    }
}

// Called exclusively by PowerMonitor's serial sampling queue. No offsets are applied.
final class AutomaticPowerSampler {
    static let shared = AutomaticPowerSampler()
    private let telemetry: () -> MacPowerTelemetry?
    private let smc: (String) -> Double?
    private let clock: () -> TimeInterval
    private let wait: (TimeInterval) -> Void
    private var freshness = TelemetryFreshness()
    private var idleDetector = BatteryIdleDetector()
    private let batteryCurrent: () -> Double?

    init(telemetry: @escaping () -> MacPowerTelemetry? = AutomaticPowerSampler.readTelemetry,
         smc: @escaping (String) -> Double? = { SMC.shared.getValue($0) },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
         batteryCurrent: @escaping () -> Double? = { SMC.shared.batteryCurrentMilliamps() }) {
        self.telemetry = telemetry
        self.smc = smc
        self.clock = clock
        self.wait = wait
        self.batteryCurrent = batteryCurrent
    }

    func sample() -> BatteryStatus {
        let frame = telemetry()
        let current = frame?.externalPowerConnected == true && frame?.isCharging != nil ? batteryCurrent() : nil
        let idle = idleDetector.update(externalPowerConnected: frame?.externalPowerConnected,
                                       isCharging: frame?.isCharging, currentMilliamps: current)
        if let frame, frame.externalPowerConnected != false,
           frame.inputWatts != nil, frame.systemWatts != nil {
            if freshness.accepts(inputCounter: frame.inputCounter, systemCounter: frame.systemCounter, now: clock()) {
                return BatteryStatus(systemWatts: frame.systemWatts, inputWatts: frame.inputWatts,
                                     inputSourceDescription: "系统输入遥测", isBatteryIdle: idle, isBatteryIdlePending: idleDetector.isConfirmingIdle)
            }
        } else {
            freshness.reset()
        }

        var system: [Double] = []
        var input: [Double] = []
        for index in 0..<3 {
            let rawInput = frame?.externalPowerConnected == false ? 0 : smc("PDTR")
            let pair = BatteryStatus(systemWatts: smc("PSTR"), inputWatts: rawInput)
            if let value = pair.systemWatts { system.append(value) }
            if let value = pair.inputWatts { input.append(value) }
            if index < 2 { wait(0.05) }
        }
        // Require the whole window; do not replace failed samples with zero or older values.
        let systemMean = system.count == 3 ? system.reduce(0, +) / 3 : nil
        let inputMean = input.count == 3 ? input.reduce(0, +) / 3 : nil
        return BatteryStatus(systemWatts: systemMean, inputWatts: inputMean,
                             inputSourceDescription: "SMC（短时平均）", isBatteryIdle: idle, isBatteryIdlePending: idleDetector.isConfirmingIdle)
    }

    static func readTelemetry() -> MacPowerTelemetry? {
        let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let source = info.flatMap { IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue() as String? }
        let external = source.map { $0 == kIOPSACPowerValue }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return MacPowerTelemetry(values: [:], externalPowerConnected: external)
        }
        defer { IOObjectRelease(service) }
        // Read only these properties; device identity and adapter ratings are never requested.
        let values = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString,
                                                     kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] ?? [:]
        let connected = IORegistryEntryCreateCFProperty(service, "ExternalConnected" as CFString,
                                                        kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
        let charging = IORegistryEntryCreateCFProperty(service, "IsCharging" as CFString,
                                                       kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
        return MacPowerTelemetry(values: values, externalPowerConnected: connected ?? external, isCharging: charging)
    }
}
