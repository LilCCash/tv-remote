import Foundation
import UIKit

typealias PairingChannelFactory = @Sendable (_ host: String) async throws -> (channel: FramedChannel, clientKey: RSAKeyParams)

let livePairingChannelFactory: PairingChannelFactory = { host in
    let identity = try CertificateManager.loadOrCreateIdentity()
    let channel = TLSChannel(host: host, port: 6467, identity: identity, pin: nil)
    do {
        try await channel.open(timeout: 10)
    } catch {
        channel.close()
        throw ErrorHandler.map(error)
    }
    let key = try CertificateManager.publicKeyParams(of: identity)
    let framed: FramedChannel = channel
    return (framed, key)
}

/// Stato della procedura di associazione (codice mostrato dalla TV, inserito sull'iPhone).
@MainActor
final class PairingFlow: ObservableObject {
    enum Step: Equatable {
        case idle
        case connecting
        case enterCode
        case verifying
        case failed(String)
    }

    @Published private(set) var step: Step = .idle
    @Published private(set) var codeError: String?

    private var session: PairingSession?
    private var target: (name: String, host: String, port: UInt16)?
    private let channelFactory: PairingChannelFactory

    init(channelFactory: @escaping PairingChannelFactory = livePairingChannelFactory) {
        self.channelFactory = channelFactory
    }

    func start(name: String, host: String, port: UInt16 = 6466) async {
        reset()
        target = (name, host, port)
        step = .connecting
        do {
            let (channel, clientKey) = try await channelFactory(host)
            let s = PairingSession(channel: channel, clientKey: clientKey, clientName: UIDevice.current.name)
            session = s
            try await s.begin()
            step = .enterCode
        } catch {
            session?.cancel()
            session = nil
            step = .failed(ErrorHandler.map(error).localizedDescription)
        }
    }

    func submit(code: String, connection: TVConnectionManager) async {
        guard let session, let target else { return }
        codeError = nil
        step = .verifying
        do {
            try await session.complete(code: code)
            session.cancel()
            self.session = nil
            // Da qui la verifica reale avviene con l'handshake della connessione di controllo.
            connection.addAndSelect(name: target.name, host: target.host, port: target.port)
        } catch {
            let e = ErrorHandler.map(error)
            if e == .wrongCode || e == .invalidCode {
                codeError = e.localizedDescription
                step = .enterCode
            } else {
                session.cancel()
                self.session = nil
                step = .failed(e.localizedDescription)
            }
        }
    }

    func reset() {
        session?.cancel()
        session = nil
        codeError = nil
        step = .idle
    }
}
