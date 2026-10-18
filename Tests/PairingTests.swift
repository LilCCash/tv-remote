import XCTest
import CryptoKit
@testable import XiaomiRemote

final class PairingTests: XCTestCase {
    private let client = RSAKeyParams(modulus: [0xC1, 0x02, 0x03], exponent: [0x01, 0x00, 0x01])
    private let server = RSAKeyParams(modulus: [0xB4, 0x05, 0x06], exponent: [0x01, 0x00, 0x01])

    /// Codice valido calcolato indipendentemente con CryptoKit (primo byte = primo byte dell'hash).
    private func validCode() -> (code: String, digest: [UInt8]) {
        var hasher = SHA256()
        hasher.update(data: client.modulus + client.exponent + server.modulus + server.exponent + [0xAB, 0xCD])
        let digest = Array(hasher.finalize())
        return (String(format: "%02X", digest[0]) + "ABCD", digest)
    }

    func testSecretMatchesIndependentHash() throws {
        let (code, digest) = validCode()
        XCTAssertEqual(try PairingSecret.compute(client: client, server: server, code: code), digest)
        XCTAssertEqual(try PairingSecret.compute(client: client, server: server, code: code.lowercased()), digest)
    }

    func testWrongAndMalformedCodes() {
        let (code, _) = validCode()
        let flipped = String(format: "%02X", UInt8(code.prefix(2), radix: 16)! ^ 0xFF) + "ABCD"
        XCTAssertThrowsError(try PairingSecret.compute(client: client, server: server, code: flipped)) {
            XCTAssertEqual($0 as? TVError, .wrongCode)
        }
        for bad in ["", "12345", "GGGGGG", "1234567"] {
            XCTAssertThrowsError(try PairingSecret.compute(client: client, server: server, code: bad)) {
                XCTAssertEqual($0 as? TVError, .invalidCode)
            }
        }
    }

    func testFullPairingFlowSendsMessagesInOrder() async throws {
        let channel = FakeChannel(incoming: [pairingReply(field: 11), pairingReply(field: 20), pairingReply(field: 31)])
        let session = PairingSession(channel: channel, clientKey: client, clientName: "Test")
        try await session.begin()

        let (code, digest) = validCode()
        channel.incoming.append(pairingReply(field: 41))
        try await session.complete(code: code)

        XCTAssertEqual(channel.sent.count, 4)
        let fields = try channel.sent.map { try ProtoReader.parse($0) }
        XCTAssertNotNil(fields[0].field(10))   // richiesta di pairing
        XCTAssertNotNil(fields[1].field(20))   // opzioni
        XCTAssertNotNil(fields[2].field(30))   // configurazione
        let secret = try ProtoReader.parse(fields[3].field(40)?.payload ?? [])
        XCTAssertEqual(secret.field(1)?.payload, digest)
    }

    func testTVRejectsRequest() async {
        let channel = FakeChannel(incoming: [pairingReply(field: 11, status: 400)])
        let session = PairingSession(channel: channel, clientKey: client, clientName: "Test")
        do {
            try await session.begin()
            XCTFail("Doveva fallire")
        } catch {
            XCTAssertEqual(error as? TVError, .pairingRejected)
        }
    }

    func testTVSilentCausesTimeout() async {
        let channel = FakeChannel(incoming: [])
        let session = PairingSession(channel: channel, clientKey: client, clientName: "Test")
        do {
            try await session.begin()
            XCTFail("Doveva fallire")
        } catch {
            XCTAssertEqual(error as? TVError, .timeout)
        }
    }

    func testWrongCodeIsLocalAndKeepsSessionUsable() async throws {
        let channel = FakeChannel(incoming: [pairingReply(field: 11), pairingReply(field: 20), pairingReply(field: 31)])
        let session = PairingSession(channel: channel, clientKey: client, clientName: "Test")
        try await session.begin()
        do {
            try await session.complete(code: "000000")
            XCTFail("Doveva fallire")
        } catch {
            XCTAssertEqual(error as? TVError, .wrongCode)
        }
        XCTAssertEqual(channel.sent.count, 3, "Un codice errato non deve inviare nulla alla TV")
    }

    func testTVRejectsSecret() async throws {
        let channel = FakeChannel(incoming: [pairingReply(field: 11), pairingReply(field: 20), pairingReply(field: 31)])
        let session = PairingSession(channel: channel, clientKey: client, clientName: "Test")
        try await session.begin()
        channel.incoming.append(pairingReply(field: 41, status: 402))
        do {
            try await session.complete(code: validCode().code)
            XCTFail("Doveva fallire")
        } catch {
            XCTAssertEqual(error as? TVError, .pairingRejected)
        }
    }
}
