import Foundation
var checks = 0
func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
    checks += 1
}
var reading = BatteryStatus(systemWatts: 12, inputWatts: 70)
expect(reading.balance == 58, "Input minus system gives charging power")
expect(reading.powerLabel(decimalPlaces: 1) == "电池充电功率", "Positive balance is charging")
reading = BatteryStatus(systemWatts: 12, inputWatts: 0)
expect(reading.balance == -12 && reading.powerLabel(decimalPlaces: 1) == "电池放电功率", "Negative balance is discharge")
reading = BatteryStatus(systemWatts: 12, inputWatts: 12)
expect(reading.displayedBatteryWatts(decimalPlaces: 1) == 0, "Balanced input")
reading = BatteryStatus(systemWatts: 12.06, inputWatts: 70.04)
expect(abs(reading.displayedBatteryWatts(decimalPlaces: 1)! - 57.9) < 0.00001, "Visible 70.0 minus 12.1 must show 57.9")
expect(reading.displayedBatteryWatts(decimalPlaces: 0) == 58, "Detail 0")
expect(abs(reading.displayedBatteryWatts(decimalPlaces: 2)! - 57.98) < 0.00001, "Detail 2")
expect(BatteryStatus(systemWatts: 12).balance == nil, "Missing input is not zero")
expect(BatteryStatus(inputWatts: 70).balance == nil, "Missing system is not zero")
expect(BatteryStatus(systemWatts: .nan, inputWatts: 70).balance == nil, "Invalid system")
expect(BatteryStatus(systemWatts: 12, inputWatts: -1).balance == nil, "Invalid input")
print("Passed \(checks) power-balance checks")

for input in [12.29, 12.31] {
    let zero = BatteryStatus(systemWatts: 12.30, inputWatts: input)
    expect(zero.displayedBatteryWatts(decimalPlaces: 1) == 0, "Near-zero rounded power")
    expect(zero.powerLabel(decimalPlaces: 1) == "电池功率", "No direction flicker at displayed zero")
}
expect(BatteryStatus().powerLabel(decimalPlaces: 1) == "电池功率", "Missing data is neutral")
expect(BatteryStatus(systemWatts: 12, inputWatts: 12.1).powerLabel(decimalPlaces: 1) == "电池充电功率", "Nonzero direction retained")
print("Passed \(checks) checks including zero-label regression")
