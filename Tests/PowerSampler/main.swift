import Foundation
var checks = 0
func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
    checks += 1
}
func frame(_ count: Int, external: Bool? = true) -> MacPowerTelemetry {
    MacPowerTelemetry(values: ["SystemLoad": 12000, "SystemPowerIn": 70000,
        "SystemPowerInAccumulatorCount": count, "SystemLoadAccumulatorCount": count], externalPowerConnected: external)
}
let initial = frame(1)
expect(initial.inputWatts == 70 && initial.systemWatts == 12, "Convert mW to W without offsets")
let invalid = MacPowerTelemetry(values: ["SystemPowerIn": true, "SystemLoad": -1,
    "SystemPowerInAccumulatorCount": -1], externalPowerConnected: nil)
expect(invalid.inputWatts == nil && invalid.systemWatts == nil && invalid.inputCounter == nil, "Reject booleans and negatives")
let rating = MacPowerTelemetry(values: ["Watts": 100, "IPDInputPower": 100000, "AdapterEfficiencyLoss": 2000], externalPowerConnected: true)
expect(rating.inputWatts == nil, "Adapter rating/contract/loss are not actual input watts")
var now = 0.0
var current: MacPowerTelemetry? = initial
var reads = 0
var waits = 0
let sampler = AutomaticPowerSampler(telemetry: { current }, smc: { key in
    reads += 1
    return key == "PDTR" ? 30 : 20
}, clock: { now }, wait: { _ in waits += 1 })
var result = sampler.sample()
expect(result.inputWatts == 30 && result.systemWatts == 20 && reads == 6 && waits == 2, "Unproven frame falls back to full paired SMC window")
expect(result.inputSourceDescription == "SMC（短时平均）", "Identify actual selected source")
now = 1; current = frame(2)
result = sampler.sample()
expect(result.inputWatts == 70 && result.systemWatts == 12 && reads == 6, "Timely joint counters enable telemetry without extra SMC reads")
expect(result.balance == 58 && result.inputSourceDescription == "系统输入遥测", "Telemetry pair preserves difference")
now = 8
result = sampler.sample()
expect(result.inputWatts == 30 && reads == 12, "Frozen telemetry expires")
now = 60; current = frame(61)
result = sampler.sample()
expect(result.inputWatts == 30, "Minute-old batch refresh is not accepted as real time")
now = 61; current = frame(62)
expect(sampler.sample().inputWatts == 70, "Timely telemetry recovers automatically")
current = frame(63, external: false); now = 62
result = sampler.sample()
expect(result.inputWatts == 0 && result.balance == -20, "Unplugged state clears stale input")
current = frame(64); now = 63
expect(sampler.sample().inputWatts == 30, "Reconnect starts with unproven telemetry")
let missing = AutomaticPowerSampler(telemetry: { nil }, smc: { _ in nil }, wait: { _ in })
expect(missing.sample().inputWatts == nil && missing.sample().systemWatts == nil, "Missing readings stay unavailable")
var inputIndex = 0
var systemIndex = 0
let averaged = AutomaticPowerSampler(telemetry: { nil }, smc: { key in
    if key == "PDTR" { inputIndex += 1; return Double(inputIndex) * 10 }
    systemIndex += 1; return Double(systemIndex) * 5
}, wait: { _ in })
result = averaged.sample()
expect(result.inputWatts == 20 && result.systemWatts == 10 && result.balance == 10, "Both channels average the same three-pair window")
var index = 0
let partial = AutomaticPowerSampler(telemetry: { nil }, smc: { key in
    if key == "PDTR" { index += 1; return index == 2 ? nil : 30 }
    return 10
}, wait: { _ in })
result = partial.sample()
expect(result.inputWatts == nil && result.systemWatts == 10 && result.balance == nil, "One failed sample does not become zero or an invented mean")
print("Passed \(checks) automatic power sampling checks")
var liveCurrent: Double? = 0
var connected = true
var charging = false
var liveInput = 22.0
let idleSampler = AutomaticPowerSampler(telemetry: {
    MacPowerTelemetry(values: [:], externalPowerConnected: connected, isCharging: charging)
}, smc: { key in key == "PDTR" ? liveInput : 20 }, wait: { _ in }, batteryCurrent: { liveCurrent })
expect(!idleSampler.sample().isBatteryIdle, "Idle requires confirmation")
let stableIdle = idleSampler.sample()
expect(stableIdle.isBatteryIdle && stableIdle.displayedBatteryWatts(decimalPlaces: 1) == 0, "Adapter-only flow ignores 2W power-sensor mismatch")
for noise in [18.0, -15, 40, -50] {
    liveCurrent = noise
    expect(idleSampler.sample().isBatteryIdle, "Actual battery-current noise does not flap idle")
}
liveCurrent = -500; liveInput = 15
let supplement = idleSampler.sample()
expect(!supplement.isBatteryIdle && supplement.powerLabel(decimalPlaces: 1) == "电池放电功率", "Real supplement is not hidden")
liveCurrent = 2000; charging = true; liveInput = 40
let charge = idleSampler.sample()
expect(!charge.isBatteryIdle && charge.displayedBatteryWatts(decimalPlaces: 1) == 20, "Real charge retains the difference")
charging = false; liveCurrent = 0
_ = idleSampler.sample(); _ = idleSampler.sample()
connected = false
expect(!idleSampler.sample().isBatteryIdle && idleSampler.sample().inputWatts == 0, "Unplugged battery flow is not forced idle")
connected = true; liveCurrent = nil
expect(!idleSampler.sample().isBatteryIdle, "No current proof cannot force zero")
print("Passed \(checks) checks including adapter-only idle")
