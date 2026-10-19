import Foundation

enum KeyDirection: Int {
    case startLong = 1, endLong = 2, short = 3
}

/// Codice tasto Android (KeyEvent). I valori sono quelli di `RemoteKeyCode`
/// in remotemessage.proto del protocollo Android TV Remote v2.
struct RemoteKey: Hashable {
    let code: Int
    init(_ code: Int) { self.code = code }

    static let home = RemoteKey(3)
    static let back = RemoteKey(4)
    static let up = RemoteKey(19)
    static let down = RemoteKey(20)
    static let left = RemoteKey(21)
    static let right = RemoteKey(22)
    static let center = RemoteKey(23)
    static let volumeUp = RemoteKey(24)
    static let volumeDown = RemoteKey(25)
    static let power = RemoteKey(26)
    static let enter = RemoteKey(66)
    static let delete = RemoteKey(67)
    static let menu = RemoteKey(82)
    static let playPause = RemoteKey(85)
    static let stop = RemoteKey(86)
    static let next = RemoteKey(87)
    static let previous = RemoteKey(88)
    static let rewind = RemoteKey(89)
    static let fastForward = RemoteKey(90)
    static let mute = RemoteKey(164)        // KEYCODE_VOLUME_MUTE (altoparlanti)
    static let liveTV = RemoteKey(170)      // KEYCODE_TV
    static let settings = RemoteKey(176)
    static let tvInput = RemoteKey(178)     // KEYCODE_TV_INPUT
    static let appSwitch = RemoteKey(187)
    static let hdmi1 = RemoteKey(243)
    static let hdmi2 = RemoteKey(244)
    static let hdmi3 = RemoteKey(245)

    // Controlli video avanzati (KEYCODE_* dal protocollo; il supporto dipende da app e TV)
    static let play = RemoteKey(126)
    static let pause = RemoteKey(127)
    static let info = RemoteKey(165)
    static let captions = RemoteKey(175)
    static let guide = RemoteKey(172)
    static let channelUp = RemoteKey(166)
    static let channelDown = RemoteKey(167)
    static let lastChannel = RemoteKey(229)
    static let audioTrack = RemoteKey(222)
    static let zoomMode = RemoteKey(255)
    static let skipForward = RemoteKey(272)
    static let skipBackward = RemoteKey(273)
    static let stepForward = RemoteKey(274)
    static let stepBackward = RemoteKey(275)
}

struct VolumeInfo: Equatable {
    var level: Int
    var max: Int
    var muted: Bool
}

// MARK: - Pairing (porta 6467, messaggi "polo")

struct PairingIncoming: Equatable {
    enum Kind: Equatable { case requestAck, option, configurationAck, secretAck, unknown }
    let status: Int
    let kind: Kind
}

enum PairingMessages {
    static let serviceName = "atvremote"
    static let protocolVersion = 2
    static let statusOK = 200
    static let encodingHexadecimal = 3
    static let symbolLength = 6
    static let roleInput = 1

    private static func envelope(_ build: (inout ProtoWriter) -> Void) -> [UInt8] {
        var w = ProtoWriter()
        w.int(1, protocolVersion)
        w.int(2, statusOK)
        build(&w)
        return w.output
    }

    static func request(clientName: String) -> [UInt8] {
        envelope { w in
            w.message(10) { m in
                m.string(1, serviceName)
                m.string(2, clientName)
            }
        }
    }

    static func option() -> [UInt8] {
        envelope { w in
            w.message(20) { o in
                o.message(1) { e in
                    e.int(1, encodingHexadecimal)
                    e.int(2, symbolLength)
                }
                o.int(3, roleInput)
            }
        }
    }

    static func configuration() -> [UInt8] {
        envelope { w in
            w.message(30) { c in
                c.message(1) { e in
                    e.int(1, encodingHexadecimal)
                    e.int(2, symbolLength)
                }
                c.int(2, roleInput)
            }
        }
    }

    static func secret(_ secret: [UInt8]) -> [UInt8] {
        envelope { w in
            w.message(40) { s in s.data(1, secret) }
        }
    }

    static func decode(_ bytes: [UInt8]) throws -> PairingIncoming {
        let fields = try ProtoReader.parse(bytes)
        let status = fields.field(2)?.int ?? 0
        let kind: PairingIncoming.Kind
        if fields.field(11) != nil { kind = .requestAck }
        else if fields.field(20) != nil { kind = .option }
        else if fields.field(31) != nil { kind = .configurationAck }
        else if fields.field(41) != nil { kind = .secretAck }
        else { kind = .unknown }
        return PairingIncoming(status: status, kind: kind)
    }
}

// MARK: - Controllo remoto (porta 6466)

enum RemoteIncoming: Equatable {
    case configure
    case setActive
    case ping(Int)
    case started(Bool)
    case volume(VolumeInfo)
    case app(package: String, label: String)
    case error
    case other
}

enum RemoteMessages {
    /// Maschera di funzionalità annunciata dai client di riferimento
    /// (include KEY, IME, POWER, VOLUME, APP_LINK).
    static let featureFlags = 622

    static func configure(model: String) -> [UInt8] {
        var w = ProtoWriter()
        w.message(1) { c in
            c.int(1, featureFlags)
            c.message(2) { d in
                d.string(1, model)
                d.string(2, "Apple")
                d.int(3, 1)
                d.string(4, "1")
                d.string(5, "it.example.xiaomiremote")
                d.string(6, "1.0.0")
            }
        }
        return w.output
    }

    static func setActive() -> [UInt8] {
        var w = ProtoWriter()
        w.message(2) { a in a.int(1, featureFlags) }
        return w.output
    }

    static func pingResponse(_ value: Int) -> [UInt8] {
        var w = ProtoWriter()
        w.message(9) { p in p.int(1, value) }
        return w.output
    }

    static func key(_ key: RemoteKey, _ direction: KeyDirection) -> [UInt8] {
        var w = ProtoWriter()
        w.message(10) { k in
            k.int(1, key.code)
            k.int(2, direction.rawValue)
        }
        return w.output
    }

    static func launch(appLink: String) -> [UInt8] {
        var w = ProtoWriter()
        w.message(90) { l in l.string(1, appLink) }
        return w.output
    }

    static func decode(_ bytes: [UInt8]) throws -> RemoteIncoming {
        for f in try ProtoReader.parse(bytes) where f.wire == 2 {
            switch f.number {
            case 1: return .configure
            case 2: return .setActive
            case 3: return .error
            case 8:
                let p = try ProtoReader.parse(f.payload)
                return .ping(p.field(1)?.int ?? 0)
            case 20:
                // RemoteImeKeyInject { app_info (1) { label (10), app_package (12) } }: la TV comunica l'app in primo piano.
                let p = try ProtoReader.parse(f.payload)
                guard let infoField = p.field(1) else { continue }
                let info = try ProtoReader.parse(infoField.payload)
                let package = info.field(12)?.string ?? ""
                if package.isEmpty { continue }
                return .app(package: package, label: info.field(10)?.string ?? "")
            case 40:
                let p = try ProtoReader.parse(f.payload)
                return .started(p.field(1)?.bool ?? false)
            case 50:
                let p = try ProtoReader.parse(f.payload)
                return .volume(VolumeInfo(level: p.field(7)?.int ?? 0,
                                          max: p.field(6)?.int ?? 0,
                                          muted: p.field(8)?.bool ?? false))
            default:
                continue
            }
        }
        return .other
    }
}
