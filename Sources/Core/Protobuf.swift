import Foundation

/// Codifica/decodifica protobuf minimale (nessuna dipendenza esterna).
/// Supporta solo ciò che serve al protocollo Android TV Remote v2.
enum Varint {
    static func encode(_ value: UInt64) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    /// Restituisce nil se i dati sono incompleti o non validi.
    static func decode(_ bytes: [UInt8], at start: Int) -> (value: UInt64, next: Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = start
        while i < bytes.count {
            let b = bytes[i]
            result |= UInt64(b & 0x7F) << shift
            i += 1
            if b & 0x80 == 0 { return (result, i) }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}

struct ProtoWriter {
    private(set) var output: [UInt8] = []

    private mutating func tag(_ field: Int, _ wire: Int) {
        output += Varint.encode(UInt64(field << 3 | wire))
    }

    mutating func int(_ field: Int, _ value: Int) {
        tag(field, 0)
        output += Varint.encode(UInt64(bitPattern: Int64(value)))
    }

    mutating func bool(_ field: Int, _ value: Bool) { int(field, value ? 1 : 0) }

    mutating func data(_ field: Int, _ value: [UInt8]) {
        tag(field, 2)
        output += Varint.encode(UInt64(value.count))
        output += value
    }

    mutating func string(_ field: Int, _ value: String) { data(field, Array(value.utf8)) }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var inner = ProtoWriter()
        build(&inner)
        data(field, inner.output)
    }
}

struct ProtoField {
    let number: Int
    let wire: Int
    let varint: UInt64
    let payload: [UInt8]

    var int: Int { Int(truncatingIfNeeded: Int64(bitPattern: varint)) }
    var bool: Bool { varint != 0 }
    var string: String { String(decoding: payload, as: UTF8.self) }
}

enum ProtoReader {
    static func parse(_ bytes: [UInt8]) throws -> [ProtoField] {
        var i = 0
        var out: [ProtoField] = []
        while i < bytes.count {
            guard let (key, afterKey) = Varint.decode(bytes, at: i) else {
                throw TVError.protocolError("campo non valido")
            }
            i = afterKey
            let number = Int(truncatingIfNeeded: key >> 3)
            let wire = Int(key & 7)
            switch wire {
            case 0:
                guard let (v, next) = Varint.decode(bytes, at: i) else {
                    throw TVError.protocolError("varint non valido")
                }
                i = next
                out.append(ProtoField(number: number, wire: 0, varint: v, payload: []))
            case 1:
                guard i + 8 <= bytes.count else { throw TVError.protocolError("fixed64 troncato") }
                i += 8
            case 5:
                guard i + 4 <= bytes.count else { throw TVError.protocolError("fixed32 troncato") }
                i += 4
            case 2:
                guard let (rawLen, next) = Varint.decode(bytes, at: i),
                      let len = Int(exactly: rawLen),
                      next + len <= bytes.count else {
                    throw TVError.protocolError("lunghezza non valida")
                }
                out.append(ProtoField(number: number, wire: 2, varint: 0, payload: Array(bytes[next..<next + len])))
                i = next + len
            default:
                throw TVError.protocolError("wire type \(wire) non supportato")
            }
        }
        return out
    }
}

extension Array where Element == ProtoField {
    func field(_ number: Int) -> ProtoField? { first(where: { $0.number == number }) }
}
