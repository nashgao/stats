#!/usr/bin/env swift
//
//  audit-power-keys.swift
//  Stats
//
//  Standalone SMC key auditor for diagnosing "stuck" live-metric
//  readouts. Not part of any target — run directly:
//
//      swift Scripts/audit-power-keys.swift scan
//          Enumerate every SMC key (reads #KEY), print all non-zero
//          keys with decoded values, then re-enumerate 8s later and
//          diff: keys whose value changed are LIVE feeds. Keys frozen
//          across both passes are snapshots/cached — never drive a
//          per-second readout from them.
//
//      swift Scripts/audit-power-keys.swift watch KEY [KEY...]
//          Read the given keys once per second for 12s. Combine with a
//          known load step (e.g. 4-6 `yes > /dev/null`, killed by exact
//          PID) to measure a candidate source's step response — a
//          trustworthy live source moves within a second or two; a
//          pinned/slow one does not.
//
//  2026-09-25: used this to establish the menu-watts source table in
//  AGENTS.md (PDTR live on AC, pinned while charging; si10 live SoC
//  power; PPBR garbage on AC).
//

import Foundation
import IOKit

enum SMCDataType: String {
    case UI8 = "ui8 ", UI16 = "ui16", UI32 = "ui32"
    case SP1E = "sp1e", SP3C = "sp3c", SP4B = "sp4b", SP5A = "sp5a"
    case SPA5 = "spa5", SP69 = "sp69", SP78 = "sp78", SP87 = "sp87", SP96 = "sp96"
    case SPB4 = "spb4", SPF0 = "spf0", FLT = "flt ", FPE2 = "fpe2", FP2E = "fp2e", FDS = "{fds"
}

enum SMCKeys: UInt8 {
    case kernelIndex = 2, readBytes = 5, writeBytes = 6, readIndex = 8, readKeyInfo = 9
}

struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)
    struct vers_t { var major: CUnsignedChar = 0; var minor: CUnsignedChar = 0; var build: CUnsignedChar = 0; var reserved: CUnsignedChar = 0; var release: CUnsignedShort = 0 }
    struct LimitData_t { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
    struct keyInfo_t { var dataSize: IOByteCount32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

struct SMCVal_t {
    var key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
    init(_ key: String) { self.key = key }
}

extension FourCharCode {
    init(fromString str: String) {
        self = str.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
    func toString() -> String {
        String(describing: UnicodeScalar(self >> 24 & 0xff)!) +
        String(describing: UnicodeScalar(self >> 16 & 0xff)!) +
        String(describing: UnicodeScalar(self >> 8 & 0xff)!) +
        String(describing: UnicodeScalar(self & 0xff)!)
    }
}

extension UInt16 { init(bytes: (UInt8, UInt8)) { self = UInt16(bytes.0) << 8 | UInt16(bytes.1) } }
extension UInt32 { init(bytes: (UInt8, UInt8, UInt8, UInt8)) { self = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3) } }
extension Float { init?(_ bytes: [UInt8]) { self = bytes.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Self.self) } } }

var conn: io_connect_t = 0
func openSMC() -> Bool {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &it) == kIOReturnSuccess else { return false }
    let dev = IOIteratorNext(it)
    IOObjectRelease(it)
    guard dev != 0 else { return false }
    defer { IOObjectRelease(dev) }
    return IOServiceOpen(dev, mach_task_self_, 0, &conn) == kIOReturnSuccess
}

func call(_ index: UInt8, input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
    let inSize = MemoryLayout<SMCKeyData_t>.stride
    var outSize = MemoryLayout<SMCKeyData_t>.stride
    return IOConnectCallStructMethod(conn, UInt32(index), &input, inSize, &output, &outSize)
}

func read(_ value: inout SMCVal_t) -> kern_return_t {
    var input = SMCKeyData_t(); var output = SMCKeyData_t()
    input.key = FourCharCode(fromString: value.key)
    input.data8 = SMCKeys.readKeyInfo.rawValue
    var r = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
    guard r == kIOReturnSuccess else { return r }
    value.dataSize = UInt32(output.keyInfo.dataSize)
    value.dataType = output.keyInfo.dataType.toString()
    input.keyInfo.dataSize = output.keyInfo.dataSize
    input.data8 = SMCKeys.readBytes.rawValue
    r = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
    guard r == kIOReturnSuccess else { return r }
    memcpy(&value.bytes, &output.bytes, min(Int(value.dataSize), value.bytes.count))
    return kIOReturnSuccess
}

func decode(_ v: SMCVal_t) -> Double? {
    guard v.dataSize > 0, v.bytes.first(where: { $0 != 0 }) != nil else { return nil }
    switch v.dataType {
    case SMCDataType.UI8.rawValue: return Double(v.bytes[0])
    case SMCDataType.UI16.rawValue: return Double(UInt16(bytes: (v.bytes[0], v.bytes[1])))
    case SMCDataType.UI32.rawValue: return Double(UInt32(bytes: (v.bytes[0], v.bytes[1], v.bytes[2], v.bytes[3])))
    case SMCDataType.SP1E.rawValue: return Double(UInt16(v.bytes[0]) * 256 + UInt16(v.bytes[1])) / 16384
    case SMCDataType.SP3C.rawValue: return Double(UInt16(v.bytes[0]) * 256 + UInt16(v.bytes[1])) / 4096
    case SMCDataType.SP4B.rawValue: return Double(UInt16(v.bytes[0]) * 256 + UInt16(v.bytes[1])) / 2048
    case SMCDataType.SP5A.rawValue: return Double(UInt16(v.bytes[0]) * 256 + UInt16(v.bytes[1])) / 1024
    case SMCDataType.SP69.rawValue: return Double(UInt16(v.bytes[0]) * 256 + UInt16(v.bytes[1])) / 512
    case SMCDataType.SP78.rawValue: return Double(Int(v.bytes[0]) * 256 + Int(v.bytes[1])) / 256
    case SMCDataType.SP87.rawValue: return Double(Int(v.bytes[0]) * 256 + Int(v.bytes[1])) / 128
    case SMCDataType.SP96.rawValue: return Double(Int(v.bytes[0]) * 256 + Int(v.bytes[1])) / 64
    case SMCDataType.SPA5.rawValue: return Double(UInt16(v.bytes[0]) * 256 + UInt16(v.bytes[1])) / 32
    case SMCDataType.SPB4.rawValue: return Double(Int(v.bytes[0]) * 256 + Int(v.bytes[1])) / 16
    case SMCDataType.SPF0.rawValue: return Double(Int(v.bytes[0]) * 256 + Int(v.bytes[1]))
    case SMCDataType.FLT.rawValue: return Float(v.bytes).map(Double.init)
    case SMCDataType.FPE2.rawValue: return Double(UInt16(v.bytes[0]) << 6 | UInt16(v.bytes[1]) >> 2)
    default: return nil
    }
}

func keyAt(_ index: UInt32) -> String? {
    var input = SMCKeyData_t(); var output = SMCKeyData_t()
    input.key = FourCharCode(fromString: "#KEY")
    input.data8 = SMCKeys.readIndex.rawValue
    input.data32 = index
    guard call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output) == kIOReturnSuccess else { return nil }
    return output.key.toString()
}

guard openSMC() else { print("no AppleSMC"); exit(1) }

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "scan" {
    var kv = SMCVal_t("#KEY")
    guard read(&kv) == kIOReturnSuccess, let count = decode(kv) else { print("no #KEY"); exit(1) }
    print("key count: \(Int(count))")
    func snapshot() -> [String: Double] {
        var snap: [String: Double] = [:]
        for i in 0..<UInt32(count) {
            guard let name = keyAt(i) else { continue }
            var v = SMCVal_t(name)
            guard read(&v) == kIOReturnSuccess else { continue }
            if let d = decode(v) { snap[name] = d }
        }
        return snap
    }
    let a = snapshot()
    print("--- pass 1: \(a.count) non-zero keys ---")
    for k in a.keys.sorted() { print("\(k) \(a[k]!)") }
    Thread.sleep(forTimeInterval: 8)
    let b = snapshot()
    print("--- changed between passes (8s apart) ---")
    for k in b.keys.sorted() where a[k] != b[k] {
        print("\(k) \(a[k] ?? -1) -> \(b[k]!)")
    }
} else if args.first == "watch" {
    let keys = Array(args.dropFirst())
    guard !keys.isEmpty else { print("usage: audit-power-keys.swift watch KEY [KEY...]"); exit(2) }
    print("watching: \(keys.joined(separator: " "))")
    for _ in 0..<12 {
        var line = ""
        for k in keys {
            var v = SMCVal_t(k)
            let r = read(&v)
            let d = r == kIOReturnSuccess ? decode(v) : nil
            line += "\(k)=\(d.map { String($0) } ?? "ERR") "
        }
        print(line)
        Thread.sleep(forTimeInterval: 1)
    }
} else {
    print("usage: audit-power-keys.swift scan | watch KEY [KEY...]")
    exit(2)
}
