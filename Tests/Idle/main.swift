import Foundation
var checks = 0
func expect(_ result: Bool, _ message: String) {
    precondition(result, message)
    checks += 1
}
var detector = BatteryIdleDetector()
expect(!detector.update(externalPowerConnected: true, isCharging: false, currentMilliamps: 0), "One zero frame not sufficient")
expect(detector.update(externalPowerConnected: true, isCharging: false, currentMilliamps: 0), "Two idle observations confirm adapter-only power")
for noise in [10.0, -18, 30, -40, 55, 0] {
    expect(detector.update(externalPowerConnected: true, isCharging: false, currentMilliamps: noise), "Hysteresis holds small battery current noise")
}
expect(!detector.update(externalPowerConnected: true, isCharging: false, currentMilliamps: -500), "Real battery supplement exits idle")
expect(!detector.update(externalPowerConnected: true, isCharging: true, currentMilliamps: 2000), "Charging is not suppressed")
expect(!detector.update(externalPowerConnected: true, isCharging: false, currentMilliamps: 0), "Reconfirm after charging")
expect(detector.update(externalPowerConnected: true, isCharging: false, currentMilliamps: 0), "Idle after stopped charge")
expect(!detector.update(externalPowerConnected: false, isCharging: false, currentMilliamps: 0), "Unplugging exits immediately")
expect(!detector.update(externalPowerConnected: true, isCharging: false, currentMilliamps: nil), "Missing current cannot prove idle")
expect(!detector.update(externalPowerConnected: true, isCharging: nil, currentMilliamps: 0), "Missing charge flag cannot prove idle")
expect(!detector.update(externalPowerConnected: true, isCharging: false, currentMilliamps: .nan), "Invalid current rejected")
expect(!detector.update(externalPowerConnected: true, isCharging: true, currentMilliamps: 0), "Stale true flag exact-zero confirmation one")
expect(!detector.update(externalPowerConnected: true, isCharging: true, currentMilliamps: 0), "Stale true flag exact-zero confirmation two")
expect(detector.update(externalPowerConnected: true, isCharging: true, currentMilliamps: 0), "Three live zero observations prove no battery flow")
expect(!detector.update(externalPowerConnected: true, isCharging: true, currentMilliamps: 10), "Actual low-current charging leaves idle")
let idle = BatteryStatus(systemWatts: 12, inputWatts: 14, isBatteryIdle: true)
expect(idle.balance == 2, "Raw difference remains available, never alter the input/system measurements")
expect(idle.displayedBatteryWatts(decimalPlaces: 2) == 0 && idle.powerLabel(decimalPlaces: 2) == "电池功率", "Idle does not use the noisy balance sign")
expect(BatteryStatus(systemWatts: 12, isBatteryIdle: true).displayedBatteryWatts(decimalPlaces: 1) == nil, "Missing power data remains unavailable")
print("Passed \(checks) battery-idle checks")

let pending = BatteryStatus(systemWatts: 12, inputWatts: 14, isBatteryIdlePending: true)
expect(pending.displayedBatteryWatts(decimalPlaces: 1) == nil && pending.powerLabel(decimalPlaces: 1) == "电池功率", "Confirmation must not flash a charge/discharge number")
print("Passed \(checks) checks including pending idle")
