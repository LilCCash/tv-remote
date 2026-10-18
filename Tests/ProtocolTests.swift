import XCTest
@testable import XiaomiRemote

final class ProtocolTests: XCTestCase {
    func testVarintRoundTrip() {
        for value: UInt64 in [0, 1, 127, 128, 300, 16_384, UInt64(Int32.max)] {
            XCTAssertEqual(Varint.decode(Varint.encode(value), at: 0)?.value, value)
        }
    }

    func testIncompleteVarintIsNil() {
        XCTAssertNil(Varint.decode([0x80], at: 0))
    }

    func testKeyInjectBytes() {
        // RemoteMessage { remote_key_inject (10) { key_code (1) = 19 DPAD_UP, direction (2) = 3 SHORT } }
        XCTAssertEqual(RemoteMessages.key(.up, .short), [0x52, 0x04, 0x08, 0x13, 0x10, 0x03])
    }

    func testPingResponseBytes() {
        XCTAssertEqual(RemoteMessages.pingResponse(5), [0x4A, 0x02, 0x08, 0x05])
    }

    func testDecodePingRequest() throws {
        XCTAssertEqual(try RemoteMessages.decode([0x42, 0x02, 0x08, 0x05]), .ping(5))
    }

    func testDecodeConfigureAndSetActive() throws {
        XCTAssertEqual(try RemoteMessages.decode(RemoteMessages.configure(model: "iPhone")), .configure)
        XCTAssertEqual(try RemoteMessages.decode(RemoteMessages.setActive()), .setActive)
    }

    func testDecodeVolumeAndPower() throws {
        var volume = ProtoWriter()
        volume.message(50) { v in v.int(6, 30); v.int(7, 12); v.bool(8, true) }
        XCTAssertEqual(try RemoteMessages.decode(volume.output),
                       .volume(VolumeInfo(level: 12, max: 30, muted: true)))

        var power = ProtoWriter()
        power.message(40) { p in p.bool(1, true) }
        XCTAssertEqual(try RemoteMessages.decode(power.output), .started(true))
    }

    func testMalformedMessageThrows() {
        XCTAssertThrowsError(try RemoteMessages.decode([0x52, 0x09, 0x08]))   // lunghezza oltre i dati
    }

    func testLaunchEncodesLink() throws {
        let fields = try ProtoReader.parse(RemoteMessages.launch(appLink: "https://www.youtube.com"))
        let inner = try ProtoReader.parse(fields.field(90)?.payload ?? [])
        XCTAssertEqual(inner.field(1)?.string, "https://www.youtube.com")
    }

    func testPairingMessagesDecode() throws {
        let ack = try PairingMessages.decode(pairingReply(field: 11))
        XCTAssertEqual(ack.kind, .requestAck)
        XCTAssertEqual(ack.status, 200)
        XCTAssertEqual(try PairingMessages.decode(pairingReply(field: 31)).kind, .configurationAck)
        XCTAssertEqual(try PairingMessages.decode(pairingReply(field: 41, status: 402)).status, 402)
    }

    func testDERRoundTripOfRSAKey() {
        let der = DER.sequence(DER.integer([0xC1, 0x02, 0x03]), DER.integer([0x01, 0x00, 0x01]))
        let params = DER.parseRSAPublicKey(der)
        XCTAssertEqual(params, RSAKeyParams(modulus: [0xC1, 0x02, 0x03], exponent: [0x01, 0x00, 0x01]))
    }

    func testKeyboardDiff() {
        let added = KeyboardInputService.diff(old: "ab", new: "abc")
        XCTAssertEqual(added.deletions, 0)
        XCTAssertEqual(added.inserted, "c")
        let removed = KeyboardInputService.diff(old: "abc", new: "ab")
        XCTAssertEqual(removed.deletions, 1)
        XCTAssertEqual(removed.inserted, "")
        let replaced = KeyboardInputService.diff(old: "abc", new: "axy")
        XCTAssertEqual(replaced.deletions, 2)
        XCTAssertEqual(replaced.inserted, "xy")
    }

    func testKeyboardMapping() {
        XCTAssertEqual(KeyboardInputService.key(for: "a")?.code, 29)
        XCTAssertEqual(KeyboardInputService.key(for: "Z")?.code, 54)
        XCTAssertEqual(KeyboardInputService.key(for: "0")?.code, 7)
        XCTAssertEqual(KeyboardInputService.key(for: "9")?.code, 16)
        XCTAssertEqual(KeyboardInputService.key(for: " ")?.code, 62)
        XCTAssertEqual(KeyboardInputService.key(for: "è")?.code, 33)      // semplificata in "e"
        XCTAssertNil(KeyboardInputService.key(for: "😀"))
    }

    func testReconnectPolicyBacksOffAndCaps() {
        let policy = ReconnectPolicy()
        XCTAssertEqual(policy.delay(attempt: 1), 1)
        XCTAssertEqual(policy.delay(attempt: 2), 2)
        XCTAssertEqual(policy.delay(attempt: 3), 4)
        XCTAssertEqual(policy.delay(attempt: 4), 8)
        XCTAssertEqual(policy.delay(attempt: 5), 15)
        XCTAssertEqual(policy.delay(attempt: 20), 15)
    }
}
