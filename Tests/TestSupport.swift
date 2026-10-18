import XCTest
import CryptoKit
@testable import XiaomiRemote

/// TV simulata per il pairing: risponde con i messaggi preparati e registra ciò che riceve.
final class FakeChannel: FramedChannel, @unchecked Sendable {
    var sent: [[UInt8]] = []
    var incoming: [[UInt8]]
    var serverKey: RSAKeyParams? = RSAKeyParams(modulus: [0xB4, 0x05, 0x06], exponent: [0x01, 0x00, 0x01])
    var serverFingerprint: Data?
    var closed = false

    init(incoming: [[UInt8]]) { self.incoming = incoming }

    func send(_ payload: [UInt8]) async throws { sent.append(payload) }

    func receive(timeout: TimeInterval) async throws -> [UInt8] {
        guard !incoming.isEmpty else { throw TVError.timeout }   // la TV non risponde
        return incoming.removeFirst()
    }

    func close() { closed = true }
}

/// Risposta di pairing con un solo campo impostato (es. 11 = request ack).
func pairingReply(field: Int, status: Int = 200) -> [UInt8] {
    var w = ProtoWriter()
    w.int(1, 2)
    w.int(2, status)
    w.message(field) { _ in }
    return w.output
}

final class MockSession: RemoteSessionProtocol, @unchecked Sendable {
    var onPower: ((Bool) -> Void)?
    var onVolume: ((VolumeInfo) -> Void)?
    private(set) var sentKeys: [Int] = []
    private(set) var directions: [Int] = []
    private(set) var launched: [String] = []
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        var c: AsyncStream<Void>.Continuation!
        stream = AsyncStream { c = $0 }
        continuation = c
    }

    func send(key: RemoteKey, direction: KeyDirection) async throws {
        sentKeys.append(key.code)
        directions.append(direction.rawValue)
    }
    func launch(appLink: String) async throws { launched.append(appLink) }
    func waitUntilClosed() async { for await _ in stream { break } }
    func close() { continuation.yield(); continuation.finish() }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    private var items: [MockSession] = []

    @discardableResult func increment() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func add(_ s: MockSession) { lock.lock(); items.append(s); lock.unlock() }
    var sessions: [MockSession] { lock.lock(); defer { lock.unlock() }; return items }
}

func makeStorage() -> DeviceStorage {
    DeviceStorage(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
}

@MainActor
func waitFor(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async throws {
    let end = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > end { XCTFail("Timeout in attesa della condizione"); return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
