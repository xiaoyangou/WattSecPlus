import Foundation

// State detection uses battery current, not the difference of two power sensors.
struct BatteryIdleDetector {
    private var confirmations = 0
    private(set) var isIdle = false
    var isConfirmingIdle: Bool { confirmations > 0 && !isIdle }

    mutating func reset() {
        confirmations = 0
        isIdle = false
    }

    mutating func update(externalPowerConnected: Bool?, isCharging: Bool?, currentMilliamps: Double?) -> Bool {
        guard externalPowerConnected == true, let isCharging,
              let currentMilliamps, currentMilliamps.isFinite else {
            reset()
            return false
        }
        let magnitude = abs(currentMilliamps)
        // A charging indication with measurable positive current must not be hidden.
        let canRest = !isCharging || currentMilliamps == 0
        if isIdle {
            if !canRest || magnitude > 60 { reset() }
        } else if canRest && magnitude <= 20 {
            confirmations += 1
            // An exact zero may override a stale charging flag, with an extra confirmation.
            let required = isCharging ? 3 : 2
            if confirmations >= required { isIdle = true }
        } else {
            confirmations = 0
        }
        return isIdle
    }
}
