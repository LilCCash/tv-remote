import Foundation
import Network

typealias SessionFactory = @Sendable (SavedTV) async throws -> RemoteSessionProtocol

/// Attesa crescente tra i tentativi di riconnessione: 1, 2, 4, 8, poi 15 secondi.
struct ReconnectPolicy {
    var base: TimeInterval = 1
    var cap: TimeInterval = 15

    func delay(attempt: Int) -> TimeInterval {
        min(cap, base * pow(2, Double(max(0, attempt - 1))))
    }
}

/// Gestisce la TV selezionata: connessione, riconnessione automatica e stato.
/// Esiste una sola sessione alla volta e i comandi non vengono mai accodati
/// quando la TV è offline, quindi dopo una riconnessione nulla viene "rieseguito".
@MainActor
final class TVConnectionManager: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case offline(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isPoweredOn: Bool?
    @Published private(set) var volume: VolumeInfo?
    @Published private(set) var savedTVs: [SavedTV] = []
    @Published private(set) var current: SavedTV?

    let storage: DeviceStorage
    private(set) var session: RemoteSessionProtocol?
    private(set) var sessionsCreated = 0

    private let factory: SessionFactory
    private let policy: ReconnectPolicy
    private var loop: Task<Void, Never>?
    private var monitor: NWPathMonitor?
    private var lastRestart = Date.distantPast

    init(storage: DeviceStorage, factory: SessionFactory? = nil, policy: ReconnectPolicy = ReconnectPolicy()) {
        self.storage = storage
        self.policy = policy
        self.factory = factory ?? TVConnectionManager.liveFactory(storage: storage)
        savedTVs = storage.loadTVs()
        current = savedTVs.first { $0.id == storage.selectedID } ?? savedTVs.first
    }

    nonisolated static func liveFactory(storage: DeviceStorage) -> SessionFactory {
        return { tv in
            let identity = try CertificateManager.loadOrCreateIdentity()
            let pin = storage.pin(for: tv.id)
            let channel = TLSChannel(host: tv.host, port: tv.port, identity: identity, pin: pin)
            do {
                try await channel.open(timeout: 8)
                let session = RemoteSession(channel: channel)
                try await session.handshake()
                // Prima connessione dopo il pairing: memorizza l'impronta del certificato della TV.
                if pin == nil, let fingerprint = channel.serverFingerprint {
                    storage.savePin(fingerprint, for: tv.id)
                }
                session.startLoop()
                return session
            } catch {
                channel.close()
                throw ErrorHandler.map(error)
            }
        }
    }

    // MARK: Ciclo di vita

    func bootstrap() {
        startMonitoring()
        startLoop()
    }

    func startLoop() {
        stop()
        guard let tv = current else { state = .idle; return }
        lastRestart = Date()
        loop = Task { [weak self] in await self?.run(tv) }
    }

    /// Riprova subito (pulsante «Riprova» o comando premuto con la TV offline).
    /// Ignorato se si sta già connettendo o se l'ultimo tentativo è recentissimo.
    func retryNow() {
        guard state != .connecting, Date().timeIntervalSince(lastRestart) > 1.5 else { return }
        startLoop()
    }

    func disconnect() {
        stop()
        state = .idle
    }

    func appDidEnterBackground() {
        guard current != nil else { return }
        stop()
        state = .idle
    }

    func appDidBecomeActive() {
        guard current != nil, state != .connected, state != .connecting else { return }
        startLoop()
    }

    private func stop() {
        loop?.cancel()
        loop = nil
        session?.close()
        session = nil
        isPoweredOn = nil
        volume = nil
    }

    private func run(_ tv: SavedTV) async {
        var attempt = 0
        while !Task.isCancelled {
            state = attempt == 0 ? .connecting : .reconnecting(attempt: attempt)
            do {
                let s = try await factory(tv)
                if Task.isCancelled { s.close(); return }
                sessionsCreated += 1
                s.onPower = { [weak self] on in Task { @MainActor in self?.isPoweredOn = on } }
                s.onVolume = { [weak self] info in Task { @MainActor in self?.volume = info } }
                session = s
                state = .connected
                attempt = 0
                await s.waitUntilClosed()
                if Task.isCancelled { return }
                session = nil
                isPoweredOn = nil
                volume = nil
                state = .offline("Connessione persa. Riprovo…")
            } catch {
                if Task.isCancelled { return }
                let e = ErrorHandler.map(error)
                if e.isFatal {
                    state = .failed(e.localizedDescription)
                    return
                }
                state = .offline(e.localizedDescription)
            }
            attempt += 1
            try? await Task.sleep(nanoseconds: UInt64(policy.delay(attempt: attempt) * 1_000_000_000))
        }
    }

    // MARK: Rete

    func startMonitoring() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.networkAvailable() }
        }
        m.start(queue: DispatchQueue(label: "it.example.xiaomiremote.path"))
        monitor = m
    }

    /// Cambio di rete Wi-Fi o rete tornata disponibile: riprova subito.
    private func networkAvailable() {
        guard Date().timeIntervalSince(lastRestart) > 2 else { return }
        switch state {
        case .offline, .reconnecting: startLoop()
        default: break
        }
    }

    // MARK: TV salvate

    func addAndSelect(name: String, host: String, port: UInt16) {
        if let i = savedTVs.firstIndex(where: { $0.host == host }) {
            savedTVs[i].port = port
            storage.deletePin(for: savedTVs[i].id)   // nuovo pairing = nuovo certificato da memorizzare
            current = savedTVs[i]
        } else {
            let tv = SavedTV(id: UUID(), name: name, host: host, port: port)
            savedTVs.append(tv)
            current = tv
        }
        storage.saveTVs(savedTVs)
        storage.selectedID = current?.id
        startLoop()
    }

    func select(_ tv: SavedTV) {
        current = tv
        storage.selectedID = tv.id
        startLoop()
    }

    func rename(_ tv: SavedTV, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = savedTVs.firstIndex(where: { $0.id == tv.id }) else { return }
        savedTVs[i].name = trimmed
        if current?.id == tv.id { current = savedTVs[i] }
        storage.saveTVs(savedTVs)
    }

    func forget(_ tv: SavedTV) {
        storage.deletePin(for: tv.id)
        savedTVs.removeAll { $0.id == tv.id }
        storage.saveTVs(savedTVs)
        if current?.id == tv.id {
            stop()
            current = savedTVs.first
            storage.selectedID = current?.id
            state = .idle
            if current != nil { startLoop() }
        }
    }
}
