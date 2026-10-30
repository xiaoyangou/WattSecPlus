//
//  SMC.swift
//  WattSecPlus
//
//  Original by Serhiy Mytrovtsiy at github.com/exelban/stats
//  Modified by Ben Beutton on 3/4/25.
//

import Foundation
import IOKit
import OSLog

internal enum SMCKeys: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readKeyInfo = 9
}

internal struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)

    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0))
}

internal struct SMCVal_t {
    var key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)

    init(_ key: String) {
        self.key = key
    }
}

extension FourCharCode {
    init(fromString str: String) {
        precondition(str.utf8.count == 4)

        self = str.utf8.reduce(0) { sum, character in
            return sum << 8 | UInt32(character)
        }
    }

    func toString() -> String {
        return String(describing: UnicodeScalar(self >> 24 & 0xff)!) +
               String(describing: UnicodeScalar(self >> 16 & 0xff)!) +
               String(describing: UnicodeScalar(self >> 8  & 0xff)!) +
               String(describing: UnicodeScalar(self       & 0xff)!)
    }
}

/// The SMC protocol only needs a small transport surface here. Keeping it
/// injectable makes protocol validation testable without opening AppleSMC.
internal protocol SMCTransport {
    func open() -> (kern_return_t, io_connect_t)
    func close(_ connection: io_connect_t) -> kern_return_t
    func call(_ connection: io_connect_t,
              index: UInt8,
              input: inout SMCKeyData_t,
              output: inout SMCKeyData_t) -> kern_return_t
}

private struct IOKitSMCTransport: SMCTransport {
    func open() -> (kern_return_t, io_connect_t) {
        var iterator: io_iterator_t = 0
        let matchingDictionary: CFMutableDictionary = IOServiceMatching("AppleSMC")
        let matchingResult = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                          matchingDictionary,
                                                          &iterator)
        guard matchingResult == kIOReturnSuccess else {
            return (matchingResult, 0)
        }
        defer { IOObjectRelease(iterator) }

        let device = IOIteratorNext(iterator)
        guard device != 0 else {
            return (kIOReturnNotFound, 0)
        }
        defer { IOObjectRelease(device) }

        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(device, mach_task_self_, 0, &connection)
        guard openResult == kIOReturnSuccess else {
            return (openResult, 0)
        }
        return (openResult, connection)
    }

    func close(_ connection: io_connect_t) -> kern_return_t {
        guard connection != 0 else {
            return kIOReturnSuccess
        }
        return IOServiceClose(connection)
    }

    func call(_ connection: io_connect_t,
              index: UInt8,
              input: inout SMCKeyData_t,
              output: inout SMCKeyData_t) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        let result = IOConnectCallStructMethod(connection,
                                               UInt32(index),
                                               &input,
                                               inputSize,
                                               &output,
                                               &outputSize)
        guard result == kIOReturnSuccess else {
            return result
        }
        guard outputSize >= inputSize else {
            return kIOReturnError
        }
        return result
    }
}

internal enum SMCSafety {
    static let floatType = FourCharCode(fromString: "flt ")
    static let signed16Type = FourCharCode(fromString: "si16")

    static func isValidDataSize(_ dataSize: UInt32) -> Bool {
        return (1...32).contains(dataSize)
    }

    static func decodeFloat(_ bytes: [UInt8], dataSize: UInt32) -> Double? {
        // Decode from individual bytes so no alignment assumption is made.
        guard dataSize == 4, bytes.count >= 4 else {
            return nil
        }

        let bitPattern = UInt32(bytes[0]) |
            (UInt32(bytes[1]) << 8) |
            (UInt32(bytes[2]) << 16) |
            (UInt32(bytes[3]) << 24)
        let value = Float(bitPattern: bitPattern)
        guard value.isFinite else {
            return nil
        }
        return Double(value)
    }

    static func decodeFloat(_ bytes: SMCKeyData_t.SMCBytes_t,
                            dataSize: UInt32) -> Double? {
        let byteArray: [UInt8] = withUnsafeBytes(of: bytes) { Array($0) }
        return decodeFloat(byteArray, dataSize: dataSize)
    }

    static func decodeSignedInt16(_ bytes: [UInt8], dataSize: UInt32) -> Double? {
        guard dataSize == 2, bytes.count >= 2 else {
            return nil
        }

        let bitPattern = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        return Double(Int16(bitPattern: bitPattern))
    }

    static func decodeSignedInt16(_ bytes: SMCKeyData_t.SMCBytes_t,
                                  dataSize: UInt32) -> Double? {
        let byteArray: [UInt8] = withUnsafeBytes(of: bytes) { Array($0) }
        return decodeSignedInt16(byteArray, dataSize: dataSize)
    }
}

public class SMC {
    public static let shared = SMC()
    private static let systemLogger = Logger(subsystem: "io.github.xiaoyangou.WattSecPlus", category: "SMC")

    private struct KeyInfo {
        let dataSize: UInt32
        let dataType: UInt32

        init?(dataSize: UInt32, dataType: UInt32) {
            guard SMCSafety.isValidDataSize(dataSize) else {
                return nil
            }
            self.dataSize = dataSize
            self.dataType = dataType
        }
    }

    private let lock = NSLock()
    private let transport: SMCTransport
    private let reconnectInterval: TimeInterval
    private let connectionLogInterval: TimeInterval
    private let clock: () -> TimeInterval
    private let logger: (String) -> Void

    private var conn: io_connect_t = 0
    private var lastConnectionAttempt: TimeInterval?
    private var lastConnectionLog: TimeInterval?
    private var keyInfoCache: [String: KeyInfo] = [:]

    public init() {
        self.transport = IOKitSMCTransport()
        self.reconnectInterval = 1.0
        self.connectionLogInterval = 30.0
        self.clock = { ProcessInfo.processInfo.systemUptime }
        self.logger = { message in
            SMC.systemLogger.error("\(message, privacy: .public)")
        }
    }

    internal init(transport: SMCTransport,
                  reconnectInterval: TimeInterval = 1.0,
                  connectionLogInterval: TimeInterval = 30.0,
                  clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                  logger: @escaping (String) -> Void = { print($0) }) {
        self.transport = transport
        self.reconnectInterval = max(0, reconnectInterval)
        self.connectionLogInterval = max(0, connectionLogInterval)
        self.clock = clock
        self.logger = logger
    }

    deinit {
        _ = close()
    }

    public func close() -> kern_return_t {
        lock.lock()
        defer { lock.unlock() }

        let connection = conn
        conn = 0
        lastConnectionAttempt = nil
        lastConnectionLog = nil
        keyInfoCache.removeAll(keepingCapacity: true)
        guard connection != 0 else {
            return kIOReturnSuccess
        }
        return transport.close(connection)
    }

    public func getValue(_ key: String) -> Double? {
        guard let keyCode = Self.keyCode(for: key) else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        guard ensureConnection() else {
            return nil
        }
        return readValue(for: key, keyCode: keyCode)
    }

    /// Reads the Apple Silicon battery-current SMC key in signed mA.
    /// Intel SMCs do not share this encoding, so this intentionally has no
    /// fallback guess on other architectures.
    internal func batteryCurrentMilliamps() -> Double? {
#if arch(arm64)
        let key = "B0AC"
        guard let keyCode = Self.keyCode(for: key) else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        guard ensureConnection(),
              let info = keyInfo(for: key, keyCode: keyCode,
                                 accepting: { $0.dataType == SMCSafety.signed16Type &&
                                     $0.dataSize == 2 }),
              let bytes = readBytes(for: key, keyCode: keyCode, info: info) else {
            return nil
        }
        return SMCSafety.decodeSignedInt16(bytes, dataSize: info.dataSize)
#else
        return nil
#endif
    }

    private func ensureConnection() -> Bool {
        guard conn == 0 else {
            return true
        }

        let now = clock()
        if let lastAttempt = lastConnectionAttempt,
           max(0, now - lastAttempt) < reconnectInterval {
            return false
        }
        lastConnectionAttempt = now

        let (result, connection) = transport.open()
        guard result == kIOReturnSuccess, connection != 0 else {
            conn = 0
            keyInfoCache.removeAll(keepingCapacity: true)
            logConnectionFailure(result, now: now)
            return false
        }

        conn = connection
        keyInfoCache.removeAll(keepingCapacity: true)
        return true
    }

    private func readValue(for key: String, keyCode: UInt32) -> Double? {
        guard let info = keyInfo(for: key, keyCode: keyCode,
                                 accepting: { $0.dataType == SMCSafety.floatType &&
                                     $0.dataSize == 4 }),
              let bytes = readBytes(for: key, keyCode: keyCode, info: info) else {
            return nil
        }
        return SMCSafety.decodeFloat(bytes, dataSize: info.dataSize)
    }

    private func keyInfo(for key: String,
                         keyCode: UInt32,
                         accepting: (KeyInfo) -> Bool) -> KeyInfo? {
        if let cachedInfo = keyInfoCache[key] {
            return accepting(cachedInfo) ? cachedInfo : nil
        }

        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = keyCode
        input.data8 = SMCKeys.readKeyInfo.rawValue

        guard invoke(index: SMCKeys.kernelIndex.rawValue,
                     input: &input,
                     output: &output),
              let fetchedInfo = KeyInfo(dataSize: UInt32(output.keyInfo.dataSize),
                                        dataType: output.keyInfo.dataType),
              accepting(fetchedInfo) else {
            return nil
        }
        keyInfoCache[key] = fetchedInfo
        return fetchedInfo
    }

    private func readBytes(for key: String,
                           keyCode: UInt32,
                           info: KeyInfo) -> SMCKeyData_t.SMCBytes_t? {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = keyCode
        input.keyInfo.dataSize = IOByteCount32(info.dataSize)
        input.data8 = SMCKeys.readBytes.rawValue

        guard invoke(index: SMCKeys.kernelIndex.rawValue,
                     input: &input,
                     output: &output) else {
            // A cached key can become unavailable independently of the
            // connection, so do not keep retrying the stale metadata forever.
            keyInfoCache.removeValue(forKey: key)
            return nil
        }

        return output.bytes
    }

    /// Validate both the IOKit return code and the SMC protocol result byte.
    private func invoke(index: UInt8,
                        input: inout SMCKeyData_t,
                        output: inout SMCKeyData_t) -> Bool {
        guard conn != 0 else {
            return false
        }

        let result = transport.call(conn,
                                    index: index,
                                    input: &input,
                                    output: &output)
        guard result == kIOReturnSuccess else {
            invalidateConnection(result)
            return false
        }
        return output.result == 0
    }

    private func invalidateConnection(_ result: kern_return_t) {
        let connection = conn
        conn = 0
        keyInfoCache.removeAll(keepingCapacity: true)
        if connection != 0 {
            _ = transport.close(connection)
        }
        let now = clock()
        lastConnectionAttempt = now
        logConnectionFailure(result, now: now)
    }

    private func logConnectionFailure(_ result: kern_return_t, now: TimeInterval) {
        if let lastLog = lastConnectionLog,
           max(0, now - lastLog) < connectionLogInterval {
            return
        }
        lastConnectionLog = now
        let description = String(cString: mach_error_string(result),
                                 encoding: .ascii) ?? "unknown error"
        logger("SMC connection unavailable: \(description)")
    }

    private static func keyCode(for key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else {
            return nil
        }
        return bytes.reduce(0) { result, byte in
            (result << 8) | UInt32(byte)
        }
    }
}
