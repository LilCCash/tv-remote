import Foundation
import Network

struct DiscoveredTV: Identifiable, Equatable {
    let id: String
    let name: String
    var host: String?
    var port: UInt16
    let endpoint: NWEndpoint
}

/// Risolve un servizio Bonjour in indirizzo IPv4 e porta aprendo (e chiudendo subito) una connessione TCP.
enum EndpointResolver {
    static func resolve(_ endpoint: NWEndpoint, timeout: TimeInterval = 5) async -> (host: String, port: UInt16)? {
        await withCheckedContinuation { (cont: CheckedContinuation<(host: String, port: UInt16)?, Never>) in
            let params = NWParameters.tcp
            if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let connection = NWConnection(to: endpoint, using: params)
            let queue = DispatchQueue(label: "it.example.xiaomiremote.resolve")
            let gate = Gate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.fire() {
                        var result: (host: String, port: UInt16)?
                        if case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint {
                            let text = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
                            result = (host: text, port: port.rawValue)
                        }
                        connection.cancel()
                        cont.resume(returning: result)
                    }
                case .failed, .waiting, .cancelled:
                    if gate.fire() {
                        connection.cancel()
                        cont.resume(returning: nil)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if gate.fire() {
                    connection.cancel()
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

/// Cerca le Android TV sulla rete locale tramite mDNS (servizio `_androidtvremote2._tcp`).
/// Il primo avvio fa comparire la richiesta di permesso "Rete locale" di iOS.
@MainActor
final class TVDiscoveryService: ObservableObject {
    enum State: Equatable { case idle, searching, denied, failed(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [DiscoveredTV] = []

    static let serviceType = "_androidtvremote2._tcp"
    private var browser: NWBrowser?
    private var resolving = Set<String>()

    func start() {
        stop()
        state = .searching
        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        b.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in self?.handle(state: st) }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.handle(results: results) }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolving.removeAll()
        if state == .searching { state = .idle }
    }

    private func handle(state st: NWBrowser.State) {
        switch st {
        case .failed(let error), .waiting(let error):
            if case .dns(let code) = error, code == -65570 {
                state = .denied
            } else {
                state = .failed(error.localizedDescription)
            }
        case .ready:
            state = .searching
        default:
            break
        }
    }

    private func handle(results: Set<NWBrowser.Result>) {
        var found: [DiscoveredTV] = []
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            let previous = devices.first { $0.id == name }
            found.append(DiscoveredTV(id: name, name: name, host: previous?.host,
                                      port: previous?.port ?? 6466, endpoint: result.endpoint))
        }
        devices = found.sorted { $0.name < $1.name }
        for tv in devices where tv.host == nil && !resolving.contains(tv.id) {
            resolving.insert(tv.id)
            Task { await self.resolve(tv) }
        }
    }

    private func resolve(_ tv: DiscoveredTV) async {
        let result = await EndpointResolver.resolve(tv.endpoint)
        resolving.remove(tv.id)
        guard let i = devices.firstIndex(where: { $0.id == tv.id }), let result else { return }
        devices[i].host = result.host
        devices[i].port = result.port
    }
}
