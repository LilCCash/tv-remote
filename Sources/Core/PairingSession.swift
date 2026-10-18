import Foundation
import CryptoKit

/// Calcolo del segreto di pairing (protocollo "polo" di Android TV):
/// SHA-256( modulo_client | esponente_client | modulo_TV | esponente_TV | ultimi 2 byte del codice ).
/// Il primo byte dell'hash deve coincidere con i primi due caratteri esadecimali del codice
/// mostrato dalla TV; l'hash completo viene inviato come segreto.
enum PairingSecret {
    static func compute(client: RSAKeyParams, server: RSAKeyParams, code: String) throws -> [UInt8] {
        let normalized = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard normalized.count == 6, let codeBytes = hexBytes(normalized) else {
            throw TVError.invalidCode
        }
        var hasher = SHA256()
        hasher.update(data: client.modulus)
        hasher.update(data: client.exponent)
        hasher.update(data: server.modulus)
        hasher.update(data: server.exponent)
        hasher.update(data: Array(codeBytes[1...2]))
        let digest = Array(hasher.finalize())
        guard digest[0] == codeBytes[0] else { throw TVError.wrongCode }
        return digest
    }

    static func hexBytes(_ text: String) -> [UInt8]? {
        guard text.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}

/// Procedura di associazione sulla porta 6467:
/// richiesta → opzioni → configurazione (la TV mostra il codice) → segreto.
final class PairingSession {
    private let channel: FramedChannel
    private let clientKey: RSAKeyParams
    private let clientName: String

    init(channel: FramedChannel, clientKey: RSAKeyParams, clientName: String) {
        self.channel = channel
        self.clientKey = clientKey
        self.clientName = clientName
    }

    /// Esegue lo scambio fino a quando la TV mostra il codice a 6 caratteri.
    func begin() async throws {
        try await channel.send(PairingMessages.request(clientName: clientName))
        while true {
            let message = try PairingMessages.decode(try await channel.receive(timeout: 15))
            guard message.status < 400 else { throw TVError.pairingRejected }
            switch message.kind {
            case .requestAck:
                try await channel.send(PairingMessages.option())
            case .option:
                try await channel.send(PairingMessages.configuration())
            case .configurationAck:
                return
            case .secretAck, .unknown:
                continue
            }
        }
    }

    /// Verifica il codice digitato dall'utente. `wrongCode` / `invalidCode` sono errori
    /// locali (nessun dato inviato): la sessione resta valida e si può riprovare.
    func complete(code: String) async throws {
        guard let server = channel.serverKey else {
            throw TVError.protocolError("certificato della TV mancante")
        }
        let secret = try PairingSecret.compute(client: clientKey, server: server, code: code)
        try await channel.send(PairingMessages.secret(secret))
        let reply = try PairingMessages.decode(try await channel.receive(timeout: 15))
        guard reply.kind == .secretAck, reply.status < 400 else { throw TVError.pairingRejected }
    }

    func cancel() { channel.close() }
}
