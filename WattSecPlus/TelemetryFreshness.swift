import Foundation

/// Tracks whether two Apple power-telemetry counters are current enough to use.
///
/// The counter pair is deliberately kept separate from the sampled watt values:
/// a counter may advance before its partner, so that partial update must not
/// move the common baseline.
struct TelemetryFreshness {
    private let maximumAge: TimeInterval
    private var lastSeenInputCounter: UInt64?
    private var lastSeenSystemCounter: UInt64?
    private var commonInputCounter: UInt64?
    private var commonSystemCounter: UInt64?
    private var commonTime: TimeInterval?
    private var hasProvenFreshFrame = false

    init(maximumAge: TimeInterval = 6) {
        self.maximumAge = maximumAge.isFinite ? max(0, maximumAge) : 6
    }

    mutating func reset() {
        lastSeenInputCounter = nil
        lastSeenSystemCounter = nil
        commonInputCounter = nil
        commonSystemCounter = nil
        commonTime = nil
        lastObservedTime = nil
        hasProvenFreshFrame = false
    }

    /// Records one visible frame and returns whether it may be used now.
    mutating func accepts(inputCounter: UInt64?,
                          systemCounter: UInt64?,
                          now: TimeInterval) -> Bool {
        guard let inputCounter, let systemCounter, now.isFinite else {
            reset()
            return false
        }

        if let lastSeenInputCounter, inputCounter < lastSeenInputCounter {
            reset()
            return false
        }
        if let lastSeenSystemCounter, systemCounter < lastSeenSystemCounter {
            reset()
            return false
        }
        if let lastSeenTime = lastObservedTime, now < lastSeenTime {
            reset()
            return false
        }

        lastSeenInputCounter = inputCounter
        lastSeenSystemCounter = systemCounter
        lastObservedTime = now

        guard let commonInputCounter,
              let commonSystemCounter,
              let commonTime else {
            establishCommonBaseline(inputCounter: inputCounter,
                                    systemCounter: systemCounter,
                                    at: now)
            return false
        }

        let age = now - commonTime
        guard age >= 0, age <= maximumAge else {
            if inputCounter > commonInputCounter && systemCounter > commonSystemCounter {
                establishCommonBaseline(inputCounter: inputCounter,
                                        systemCounter: systemCounter,
                                        at: now)
            }
            return false
        }

        let bothAdvanced = inputCounter > commonInputCounter &&
            systemCounter > commonSystemCounter
        if bothAdvanced {
            establishCommonBaseline(inputCounter: inputCounter,
                                    systemCounter: systemCounter,
                                    at: now)
            hasProvenFreshFrame = true
            return true
        }

        // A one-counter update is not a common update. Keep the common
        // baseline untouched, and do not treat the partial frame as fresh.
        let unchanged = inputCounter == commonInputCounter &&
            systemCounter == commonSystemCounter
        return unchanged && hasProvenFreshFrame
    }

    private var lastObservedTime: TimeInterval?

    private mutating func establishCommonBaseline(inputCounter: UInt64,
                                                  systemCounter: UInt64,
                                                  at time: TimeInterval) {
        commonInputCounter = inputCounter
        commonSystemCounter = systemCounter
        commonTime = time
        hasProvenFreshFrame = false
    }
}
