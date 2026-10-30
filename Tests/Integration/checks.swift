// Appended to WattSecPlusApp.swift by run.py so these checks can access private UI state.
final class IntegrationReport {
    var failures: [String] = []
    var checks = 0
    func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures.append(message); print("FAIL:", message) }
    }
}
final class SampleCounter {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
func spin(_ duration: TimeInterval) {
    let end = Date().addingTimeInterval(duration)
    while Date() < end {
        RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.05))
    }
}
@main struct IntegrationRunner {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let report = IntegrationReport()
        let delegate = AppDelegate()
        delegate.verifyOptimizations(report)
        for failure in report.failures { print("FAIL:", failure) }
        print("Integration:", report.checks, "checks,", report.failures.count, "failures")
        if !report.failures.isEmpty { exit(1) }
    }
}
extension AppDelegate {
    fileprivate func verifyOptimizations(_ report: IntegrationReport) {
        let defaults = UserDefaults.standard
        let saved = ["detailLevel", "paceLevel", "widthMode"].map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        setupMenuBar()
        calculateWidestWidths()
        bindToPowerMonitor()
        PowerMonitor.shared.battery = BatteryStatus()
        report.expect(statusItem?.button?.title == "—", "Missing system reading must show dash")
        report.expect(batteryPowerItem.title == "电池功率：不可用", "Missing battery estimate is neutral")
        report.expect(inputPowerItem.title == "电源输入功率：不可用", "Missing input is unavailable")
        widthMode = .fixed
        for watts in [120.0, 1200, 8.5] {
            for level in DetailLevel.allCases {
                detailLevel = level
                PowerMonitor.shared.battery = BatteryStatus(systemWatts: watts, inputWatts: 10)
                let button = statusItem!.button!
                let required = ceil(estimateTextWidth(button.title, font: button.font!)) + 8
                report.expect(statusItem!.length >= required, "Fixed width must fit \(button.title)")
            }
        }
        highWattageTimestamp = Date().addingTimeInterval(-61)
        updateWattageDisplay()
        report.expect(highWattageTimestamp == nil, "Held width must expire")
        let widthItem = NSMenuItem()
        widthItem.representedObject = WidthMode.dynamic.rawValue
        changeWidthMode(sender: widthItem)
        report.expect(statusItem?.length == NSStatusItem.variableLength, "Dynamic width restored")
        detailLevel = .medium
        for input in [12.29, 12.31] {
            PowerMonitor.shared.battery = BatteryStatus(systemWatts: 12.30, inputWatts: input)
            report.expect(batteryPowerItem.title == "电池功率：0.0 W", "No charge/discharge label at displayed zero")
        }
        PowerMonitor.shared.battery = BatteryStatus(systemWatts: 12, inputWatts: 70, inputSourceDescription: "SMC（短时平均）")
        report.expect(inputPowerItem.title == "电源输入功率：70.0 W", "No manual offsets applied")
        report.expect(batteryPowerItem.title == "电池充电功率：58.0 W", "Automatic reading retains balance formula")
        report.expect(inputPowerItem.toolTip == nil, "Input row must not show a hover popup")
        for input in [10.0, 14.0] {
            PowerMonitor.shared.battery = BatteryStatus(systemWatts: 12, inputWatts: input, isBatteryIdle: true)
            report.expect(batteryPowerItem.title == "电池功率：0.0 W", "Confirmed idle ignores either sign of sensor mismatch")
            report.expect(inputPowerItem.title == String(format: "电源输入功率：%.1f W", input), "Idle must not rewrite input sensor")
        }
        report.expect(batteryPowerItem.toolTip == nil, "Idle battery row must not show a hover popup")
        PowerMonitor.shared.battery = BatteryStatus(systemWatts: 12, inputWatts: 14, isBatteryIdlePending: true)
        report.expect(batteryPowerItem.title == "电池功率：—", "Pending idle must not flash false charging")
        let counter = SampleCounter()
        let monitor = PowerMonitor(sampler: {
            let count = counter.next()
            Thread.sleep(forTimeInterval: 0.1)
            return count == 1 ? BatteryStatus() : BatteryStatus(systemWatts: 12.06, inputWatts: 70.04)
        }, startsTimer: false)
        var publications = 0
        let observer = monitor.$battery.dropFirst().sink { _ in publications += 1 }
        for _ in 0..<100 { monitor.fetchWattage() }
        spin(0.35)
        report.expect(counter.value == 1 && publications == 1, "Burst requests must be coalesced")
        for _ in 0..<100 { monitor.fetchWattage() }
        spin(0.35)
        report.expect(counter.value == 2 && publications == 2 && monitor.battery.balance != nil, "Recover after failed sample, still coalesce")
        observer.cancel()
        for pace in [PaceLevel.fast, .medium, .slow] {
            let paceItem = NSMenuItem()
            paceItem.representedObject = pace.rawValue
            changePace(sender: paceItem)
            var times: [Date] = []
            let subscription = PowerMonitor.shared.$battery.dropFirst().sink { reading in
                times.append(Date())
                // Combine subscriber order is unspecified; inspect UI after all sinks execute.
                RunLoop.main.perform(inModes: [.common]) {
                    let expectedBattery = reading.isBatteryIdlePending ? "—" : (reading.displayedBatteryWatts(decimalPlaces: self.detailLevel.rawValue)
                        .map { String(format: "%.*f W", self.detailLevel.rawValue, $0) } ?? "不可用")
                    report.expect(self.batteryPowerItem.title == reading.powerLabel(decimalPlaces: self.detailLevel.rawValue) + "：" + expectedBattery,
                                  "Battery row and snapshot must match")
                    let expectedInput = reading.inputWatts.map { String(format: "%.*f W", self.detailLevel.rawValue, $0) } ?? "不可用"
                    report.expect(self.inputPowerItem.title == "电源输入功率：" + expectedInput, "Input row and snapshot must match")
                    print("Pace=\(pace.rawValue)s | \(self.statusItem!.button!.title) | \(self.batteryPowerItem.title) | \(self.inputPowerItem.title)")
                }
            }
            spin(Double(pace.rawValue) * 2 + 0.4)
            subscription.cancel()
            report.expect(times.count >= 2, "Pace must publish at least twice")
            if times.count >= 2 {
                let interval = times[times.count - 1].timeIntervalSince(times[times.count - 2])
                report.expect(abs(interval - Double(pace.rawValue)) < 0.7, "Pace interval \(interval) must match \(pace.rawValue)")
                print("PASS interval:", interval)
            }
        }
        for level in DetailLevel.allCases {
            let item = NSMenuItem()
            item.representedObject = level.rawValue
            changeDetailLevel(sender: item)
            print("Detail=\(level.rawValue) | \(batteryPowerItem.title) | \(inputPowerItem.title)")
        }
        report.expect(statusItem?.menu?.items.count == 9, "Keep original menu with only two added metrics")
    }
}
