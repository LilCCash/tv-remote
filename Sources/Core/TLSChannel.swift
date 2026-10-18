import Foundation
import Network
import Security
import CryptoKit

/// Canale a messaggi protobuf "length-delimited" (varint di lunghezza + payload).
protocol FramedChannel: AnyObject {
    var serverKey: RSAKeyParams? { get }
    var serverFingerprint: Data? { get }
    func send(_ payload: [UInt8]) async throws
    /// Dopo un timeout il canale viene chiuso.
    func receive(timeout: TimeInterval) async throws -> [UInt8]
    func close()
}

/// Permette di completare una continuation una sola volta.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

/// Memorizza il certificato presentato dalla TV e applica il pinning se presente.
final class CertBox: @unchecked Sendable {
    let pin: Data?
    private let lock = NSLock()
    private var storedDER: Data?
    private var storedMismatch = false

    init(pin: Data?) { self.pin = pin }

    func accept(_ der: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        storedDER = der
        if let pin, Data(SHA256.hash(data: der)) != pin {
            storedMismatch = true
            return false
        }
        return true
    }

    var der: Data? { lock.lock(); defer { lock.unlock() }; return storedDER }
    var mismatch: Bool { lock.lock(); defer { lock.unlock() }; return storedMismatch }
}

/// TLS con certificato client (mutual TLS). La TV usa un certificato self-signed:
/// non è validato dalla catena di sistema ma tramite pinning (SHA-256 del certificato)
/// salvato alla prima connessione dopo il pairing.
final class TLSChannel: FramedChannel, @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let box: CertBox
    private let lock = NSLock()
    private var closed = false
    private var buffer: [UInt8] = []

    init(host: String, port: UInt16, identity: SecIdentity, pin: Data?) {
        let q = DispatchQueue(label: "it.example.xiaomiremote.tls")
        let box = CertBox(pin: pin)

        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        if let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_set_verify_block(sec, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                  let leaf = chain.first else {
                complete(false)
                return
            }
            complete(box.accept(SecCertificateCopyData(leaf) as Data))
        }, q)

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 15
        tcp.noDelay = true

        self.queue = q
        self.box = box
        self.connection = NWConnection(host: NWEndpoint.Host(host),
                                       port: NWEndpoint.Port(rawValue: port) ?? 6466,
                                       using: NWParameters(tls: tls, tcp: tcp))
    }

    var serverKey: RSAKeyParams? {
        guard let der = box.der,
              let cert = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        return try? CertificateManager.publicKeyParams(ofCertificate: cert)
    }

    var serverFingerprint: Data? { box.der.map { Data(SHA256.hash(data: $0)) } }

    private var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }

    private func markClosed() {
        lock.lock(); closed = true; lock.unlock()
        connection.cancel()
    }

    func open(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let gate = Gate()
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if gate.fire() { cont.resume() }
                case .waiting(let e), .failed(let e):
                    if gate.fire() {
                        cont.resume(throwing: self.box.mismatch ? TVError.certificateChanged : ErrorHandler.map(e))
                    }
                    self.markClosed()
                case .cancelled:
                    if gate.fire() {
                        cont.resume(throwing: self.box.mismatch ? TVError.certificateChanged
                                                                 : TVError.connectionFailed("Connessione annullata."))
                    }
                    self.markClosed()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                if gate.fire() {
                    cont.resume(throwing: TVError.timeout)
                    self?.markClosed()
                }
            }
        }
    }

    func send(_ payload: [UInt8]) async throws {
        if isClosed { throw TVError.connectionLost("canale chiuso") }
        let framed = Data(Varint.encode(UInt64(payload.count)) + payload)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: TVError.connectionLost(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    func receive(timeout: TimeInterval) async throws -> [UInt8] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let (rawLen, start) = Varint.decode(buffer, at: 0) {
                guard let len = Int(exactly: rawLen), len < 1_048_576 else {
                    markClosed()
                    throw TVError.protocolError("messaggio troppo grande")
                }
                if buffer.count >= start + len {
                    let message = Array(buffer[start..<start + len])
                    buffer.removeFirst(start + len)
                    return message
                }
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                markClosed()
                throw TVError.timeout
            }
            buffer += try await readChunk(timeout: remaining)
        }
    }

    private func readChunk(timeout: TimeInterval) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            let gate = Gate()
            let timer = DispatchWorkItem { [weak self] in
                if gate.fire() {
                    cont.resume(throwing: TVError.timeout)
                    self?.markClosed()
                }
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                timer.cancel()
                guard gate.fire() else { return }
                if let error {
                    cont.resume(throwing: ErrorHandler.map(error))
                } else if let data, !data.isEmpty {
                    cont.resume(returning: [UInt8](data))
                } else if isComplete {
                    cont.resume(throwing: TVError.connectionLost("la TV ha chiuso la connessione"))
                } else {
                    cont.resume(throwing: TVError.connectionLost("nessun dato"))
                }
            }
        }
    }

    func close() { markClosed() }
}
