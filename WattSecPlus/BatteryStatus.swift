import Foundation

// One sampling cycle contains both sensors so all displays use the same pair.
struct BatteryStatus {
    let systemWatts: Double?
    let inputWatts: Double?
    let inputSourceDescription: String?
    let isBatteryIdle: Bool
    let isBatteryIdlePending: Bool

    init(systemWatts: Double? = nil, inputWatts: Double? = nil, inputSourceDescription: String? = nil, isBatteryIdle: Bool = false, isBatteryIdlePending: Bool = false) {
        self.systemWatts = Self.validPower(systemWatts)
        self.inputWatts = Self.validPower(inputWatts)
        self.inputSourceDescription = inputSourceDescription
        self.isBatteryIdle = isBatteryIdle
        self.isBatteryIdlePending = isBatteryIdlePending
    }

    var balance: Double? {
        guard let systemWatts, let inputWatts else { return nil }
        return inputWatts - systemWatts
    }

    func powerLabel(decimalPlaces: Int) -> String {
        guard let balance = displayedBalance(decimalPlaces: decimalPlaces), balance != 0 else { return "电池功率" }
        return balance < 0 ? "电池放电功率" : "电池充电功率"
    }

    // Subtract the displayed readings, avoiding a 0.1 W mismatch from separate rounding.
    func displayedBatteryWatts(decimalPlaces: Int) -> Double? {
        displayedBalance(decimalPlaces: decimalPlaces).map(abs)
    }

    private func displayedBalance(decimalPlaces: Int) -> Double? {
        guard !isBatteryIdlePending else { return nil }
        guard let systemWatts, let inputWatts,
              let system = Double(String(format: "%.*f", decimalPlaces, systemWatts)),
              let input = Double(String(format: "%.*f", decimalPlaces, inputWatts)) else { return nil }
        if isBatteryIdle { return 0 }
        return input - system
    }

    private static func validPower(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
