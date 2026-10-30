import Foundation

var checks = 0

func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
    checks += 1
}

// Startup needs two common frames before the first telemetry value is trusted.
var startup = TelemetryFreshness()
expect(!startup.accepts(inputCounter: 10, systemCounter: 20, now: 0),
       "initial frame establishes a baseline only")
expect(startup.accepts(inputCounter: 11, systemCounter: 21, now: 1),
       "a timely common advance is fresh")

// A frozen, previously-proven frame is usable only inside the six-second age.
expect(startup.accepts(inputCounter: 11, systemCounter: 21, now: 2),
       "a proven frame remains usable while young")
expect(startup.accepts(inputCounter: 11, systemCounter: 21, now: 7),
       "the maximum age is inclusive")
expect(!startup.accepts(inputCounter: 11, systemCounter: 21, now: 8),
       "a frozen frame expires after the maximum age")

// The two counters may be published in separate frames. Neither partial frame
// moves the common baseline, but the later common advance is accepted.
var batched = TelemetryFreshness()
expect(!batched.accepts(inputCounter: 1, systemCounter: 1, now: 0),
       "batched startup baseline")
expect(!batched.accepts(inputCounter: 2, systemCounter: 1, now: 1),
       "input-only advance is not fresh")
expect(batched.accepts(inputCounter: 2, systemCounter: 2, now: 2),
       "system catches up to form a common update")
expect(!batched.accepts(inputCounter: 3, systemCounter: 2, now: 3),
       "another partial update is not fresh")
expect(batched.accepts(inputCounter: 3, systemCounter: 3, now: 4),
       "the next common update is fresh")

// A 60-second jump is a new baseline, not a fresh value. The following
// timely common advance can become fresh.
var longGap = TelemetryFreshness()
expect(!longGap.accepts(inputCounter: 100, systemCounter: 100, now: 0),
       "long-gap baseline startup")
expect(!longGap.accepts(inputCounter: 200, systemCounter: 200, now: 60),
       "long counter jump is rejected")
expect(!longGap.accepts(inputCounter: 200, systemCounter: 200, now: 61),
       "new baseline is not yet proven")
expect(longGap.accepts(inputCounter: 201, systemCounter: 201, now: 62),
       "timely update after the long gap is accepted")

// Backward counters, missing counters, and a backward clock all reset state.
var invalid = TelemetryFreshness()
expect(!invalid.accepts(inputCounter: 5, systemCounter: 5, now: 10),
       "invalid-state baseline")
expect(invalid.accepts(inputCounter: 6, systemCounter: 6, now: 11),
       "invalid-state fresh frame")
expect(!invalid.accepts(inputCounter: 4, systemCounter: 7, now: 12),
       "counter rollback resets and rejects")
expect(!invalid.accepts(inputCounter: 4, systemCounter: 7, now: 13),
       "post-rollback frame is a new baseline")
expect(invalid.accepts(inputCounter: 5, systemCounter: 8, now: 14),
       "freshness recovers after rollback")

expect(!invalid.accepts(inputCounter: nil, systemCounter: 9, now: 15),
       "missing counter resets and rejects")
expect(!invalid.accepts(inputCounter: 5, systemCounter: 9, now: 16),
       "missing-counter recovery starts a baseline")
expect(invalid.accepts(inputCounter: 6, systemCounter: 10, now: 17),
       "missing-counter recovery accepts a timely pair")

var reverseClock = TelemetryFreshness()
expect(!reverseClock.accepts(inputCounter: 1, systemCounter: 1, now: 20),
       "clock baseline")
expect(!reverseClock.accepts(inputCounter: 2, systemCounter: 2, now: 19),
       "backward clock resets and rejects")
expect(!reverseClock.accepts(inputCounter: 2, systemCounter: 2, now: 0),
       "clock recovery starts a new time-axis baseline")
expect(reverseClock.accepts(inputCounter: 3, systemCounter: 3, now: 1),
       "clock recovery accepts a timely pair")

var nonFinite = TelemetryFreshness()
expect(!nonFinite.accepts(inputCounter: 1, systemCounter: 1, now: .nan),
       "NaN timestamp rejects")
expect(!nonFinite.accepts(inputCounter: 1, systemCounter: 1, now: .infinity),
       "infinite timestamp rejects")

nonFinite.reset()
expect(!nonFinite.accepts(inputCounter: 1, systemCounter: 1, now: 0),
       "explicit reset clears the baseline")
expect(nonFinite.accepts(inputCounter: 2, systemCounter: 2, now: 1),
       "explicit reset recovery")

print("Passed \(checks) telemetry freshness checks")
