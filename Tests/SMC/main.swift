import Foundation
import IOKit

private var checks = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

private func floatBytes(_ value: Float) -> [UInt8] {
    let bits = value.bitPattern
    return [UInt8(truncatingIfNeeded: bits),
            UInt8(truncatingIfNeeded: bits >> 8),
            UInt8(truncatingIfNeeded: bits >> 16),
            UInt8(truncatingIfNeeded: bits >> 24)]
}

private struct FakeResponse {
    var kernelResult: kern_return_t = kIOReturnSuccess
    var protocolResult: UInt8 = 0
    var dataSize: UInt32 = 4
    var dataType: UInt32 = SMCSafety.floatType
    var bytes = floatBytes(12.5)
}

private final class FakeTransport: SMCTransport {
    var openResults: [(kern_return_t, io_connect_t)] = []
    var metadata = FakeResponse()
    var bytes = FakeResponse()
    var openCount = 0
    var closeCount = 0
    var metadataCallCount = 0
    var bytesCallCount = 0
    var closedConnections: [io_connect_t] = []

    func open() -> (kern_return_t, io_connect_t) {
        openCount += 1
        if !openResults.isEmpty {
            return openResults.removeFirst()
        }
        return (kIOReturnSuccess, io_connect_t(openCount))
    }

    func close(_ connection: io_connect_t) -> kern_return_t {
        guard connection != 0 else {
            return kIOReturnSuccess
        }
        closeCount += 1
        closedConnections.append(connection)
        return kIOReturnSuccess
    }

    func call(_ connection: io_connect_t,
              index: UInt8,
              input: inout SMCKeyData_t,
              output: inout SMCKeyData_t) -> kern_return_t {
        precondition(connection != 0)
        precondition(index == SMCKeys.kernelIndex.rawValue)

        let response: FakeResponse
        if input.data8 == SMCKeys.readKeyInfo.rawValue {
            metadataCallCount += 1
            response = metadata
            output.keyInfo.dataSize = IOByteCount32(response.dataSize)
            output.keyInfo.dataType = response.dataType
        } else if input.data8 == SMCKeys.readBytes.rawValue {
            bytesCallCount += 1
            response = bytes
            write(response.bytes, to: &output.bytes)
        } else {
            preconditionFailure("unexpected SMC operation")
        }

        output.result = response.protocolResult
        return response.kernelResult
    }

    private func write(_ bytes: [UInt8], to destination: inout SMCKeyData_t.SMCBytes_t) {
        withUnsafeMutableBytes(of: &destination) { rawBuffer in
            for (index, byte) in bytes.prefix(rawBuffer.count).enumerated() {
                rawBuffer[index] = byte
            }
        }
    }
}

// Pure wire checks: legal protocol bounds, unaligned-safe decoding, and
// rejection of non-finite values.
expect(SMCSafety.isValidDataSize(1), "one-byte data is in the protocol range")
expect(SMCSafety.isValidDataSize(32), "32-byte data is in the protocol range")
expect(!SMCSafety.isValidDataSize(0), "zero-byte data is rejected")
expect(!SMCSafety.isValidDataSize(33), "oversized data is rejected")
expect(SMCSafety.decodeFloat(floatBytes(12.5), dataSize: 4) == 12.5,
       "little-endian float decodes without alignment assumptions")
expect(SMCSafety.decodeFloat(floatBytes(12.5), dataSize: 3) == nil,
       "float data must be exactly four bytes")
expect(SMCSafety.decodeFloat(floatBytes(Float.nan), dataSize: 4) == nil,
       "NaN is rejected")
expect(SMCSafety.decodeFloat(floatBytes(Float.infinity), dataSize: 4) == nil,
       "infinity is rejected")

// A successful key-info result is cached, while each read still validates the
// SMC protocol result byte.
do {
    let transport = FakeTransport()
    let smc = SMC(transport: transport, logger: { _ in })
    expect(smc.getValue("PSTR") == 12.5, "first float value is read")
    expect(smc.getValue("PSTR") == 12.5, "cached float value is read")
    expect(transport.openCount == 1, "successful connection is reused")
    expect(transport.metadataCallCount == 1, "key metadata is cached")
    expect(transport.bytesCallCount == 2, "data is read on each sample")
}

do {
    let transport = FakeTransport()
    transport.metadata.protocolResult = 1
    let smc = SMC(transport: transport, logger: { _ in })
    expect(smc.getValue("PSTR") == nil, "metadata protocol failure returns nil")
    expect(transport.bytesCallCount == 0, "metadata protocol failure stops before data read")
}

do {
    let transport = FakeTransport()
    transport.bytes.protocolResult = 1
    let smc = SMC(transport: transport, logger: { _ in })
    expect(smc.getValue("PSTR") == nil, "data protocol failure returns nil")
    transport.bytes.protocolResult = 0
    expect(smc.getValue("PSTR") == 12.5, "protocol failure does not poison the next metadata lookup")
    expect(transport.metadataCallCount == 2, "failed cached key metadata is refreshed")
}

for invalidSize in [UInt32(0), 3, 33] {
    let transport = FakeTransport()
    transport.metadata.dataSize = invalidSize
    let smc = SMC(transport: transport, logger: { _ in })
    expect(smc.getValue("PSTR") == nil, "invalid data size \(invalidSize) returns nil")
    expect(transport.bytesCallCount == 0, "invalid metadata size stops before data read")
}

do {
    let transport = FakeTransport()
    transport.metadata.dataType = FourCharCode(fromString: "ui32")
    let smc = SMC(transport: transport, logger: { _ in })
    expect(smc.getValue("PSTR") == nil, "unsupported SMC type returns nil")
}

// A kernel failure invalidates the connection and permits a later retry;
// repeated open failures are rate-limited by the injected clock.
do {
    var now = 0.0
    let transport = FakeTransport()
    transport.metadata.kernelResult = kIOReturnError
    let smc = SMC(transport: transport,
                  reconnectInterval: 1.0,
                  clock: { now },
                  logger: { _ in })
    expect(smc.getValue("PSTR") == nil, "kernel failure returns nil")
    expect(transport.closeCount == 1, "kernel failure closes the stale connection")
    transport.metadata.kernelResult = kIOReturnSuccess
    now = 2.0
    expect(smc.getValue("PSTR") == 12.5, "connection is reopened after the retry interval")
    expect(transport.openCount == 2, "stale connection is not reused")
}

do {
    var now = 0.0
    let transport = FakeTransport()
    transport.openResults = [(kIOReturnError, 0), (kIOReturnSuccess, 9)]
    let smc = SMC(transport: transport,
                  reconnectInterval: 1.0,
                  clock: { now },
                  logger: { _ in })
    expect(smc.getValue("PSTR") == nil, "open failure returns nil")
    expect(smc.getValue("PSTR") == nil, "open failure is rate-limited")
    expect(transport.openCount == 1, "same-time reads do not reopen repeatedly")
    now = 1.1
    expect(smc.getValue("PSTR") == 12.5, "open is retried after the interval")
    expect(transport.openCount == 2, "retry opens one new connection")
}

do {
    let transport = FakeTransport()
    let smc = SMC(transport: transport, logger: { _ in })
    expect(smc.getValue("PSTR") == 12.5, "value is available before close")
    expect(smc.close() == kIOReturnSuccess, "close reports success")
    expect(transport.closeCount == 1, "close releases the active connection")
    expect(smc.close() == kIOReturnSuccess, "repeated close is harmless")
    expect(transport.closeCount == 1, "repeated close does not reuse the zero handle")
    expect(smc.getValue("PSTR") == 12.5, "close clears cache and allows reopen")
    expect(transport.metadataCallCount == 2, "reopened connection refreshes metadata")
}

expect(SMC.shared.getValue("BAD") == nil, "malformed keys return nil")
print("Passed \(checks) SMC safety checks")
