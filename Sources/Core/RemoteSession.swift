import Foundation

/// Sessione di controllo attiva con la TV (astrazione usata da manager, servizi e test).
protocol RemoteSessionProtocol: AnyObject, Sendable {
    var onPower: ((Bool) -> Void)? { get set }
    var onVolume: ((VolumeInfo) -> Void)? { get set }
    func send(key: RemoteKey, direction: KeyDirection) async throws
    func launch(appLink: String) async throws
    func waitUntilClosed() async
    func close()
}

/// Implementazione del protocollo Android TV Remote v2 (porta 6466, TLS con certificato client).
final class RemoteSession: RemoteSessionProtocol, @unchecked Sendable {
    private let channel: FramedChannel
    private let lock = NSLock()
    private var _onPower: ((Bool) -> Void)?
    private var _onVolume: ((VolumeInfo) -> Void)?
    private var lastPower: Bool?
    private var lastVolume: VolumeInfo?
    private var configured = false
    private var active = false
    private var loop: Task<Void, Never>?
    private let closedStream: AsyncStream<Void>
    private let closedContinuation: AsyncStream<Void>.Continuation

    init(channel: FramedChannel) {
        self.channel = channel
        var continuation: AsyncStream<Void>.Continuation!
        self.closedStream = AsyncStream { continuation = $0 }
        self.closedContinuation = continuation
    }

    // I valori già ricevuti vengono "riprodotti" quando si imposta il callback,
    // così non si perde lo stato iniziale inviato subito dopo l'handshake.
    var onPower: ((Bool) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onPower }
        set {
            lock.lock(); _onPower = newValue; let last = lastPower; lock.unlock()
            if let last, let newValue { newValue(last) }
        }
    }

    var onVolume: ((VolumeInfo) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onVolume }
        set {
            lock.lock(); _onVolume = newValue; let last = lastVolume; lock.unlock()
            if let last, let newValue { newValue(last) }
        }
    }

    /// Handshake: la TV invia la configurazione e la richiesta di attivazione,
    /// il client risponde a entrambe. Dopo questo scambio i comandi sono accettati.
    func handshake(timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(configured && active) {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw TVError.timeout }
            let raw = try await channel.receive(timeout: remaining)
            try await handle(try RemoteMessages.decode(raw))
        }
    }

    func startLoop() {
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    // La TV invia un ping circa ogni 5 s: 30 s di silenzio = connessione morta.
                    let raw = try await self.channel.receive(timeout: 30)
                    try await self.handle(try RemoteMessages.decode(raw))
                } catch {
                    break
                }
            }
            self?.finish()
        }
    }

    private func handle(_ message: RemoteIncoming) async throws {
        switch message {
        case .configure:
            try await channel.send(RemoteMessages.configure(model: "iPhone"))
            configured = true
        case .setActive:
            try await channel.send(RemoteMessages.setActive())
            active = true
        case .ping(let value):
            try await channel.send(RemoteMessages.pingResponse(value))
        case .started(let on):
            storePower(on)?(on)
        case .volume(let info):
            storeVolume(info)?(info)
        case .error:
            throw TVError.protocolError("errore segnalato dalla TV")
        case .other:
            break
        }
    }

    private func storePower(_ value: Bool) -> ((Bool) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        lastPower = value
        return _onPower
    }

    private func storeVolume(_ value: VolumeInfo) -> ((VolumeInfo) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        lastVolume = value
        return _onVolume
    }

    func send(key: RemoteKey, direction: KeyDirection = .short) async throws {
        try await channel.send(RemoteMessages.key(key, direction))
    }

    func launch(appLink: String) async throws {
        try await channel.send(RemoteMessages.launch(appLink: appLink))
    }

    func waitUntilClosed() async {
        for await _ in closedStream { break }
    }

    func close() {
        loop?.cancel()
        channel.close()
        finish()
    }

    private func finish() {
        channel.close()
        closedContinuation.yield()
        closedContinuation.finish()
    }
}
