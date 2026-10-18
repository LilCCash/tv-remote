import Foundation
import Network

enum TVError: Error, Equatable, LocalizedError {
    case localNetworkDenied
    case timeout
    case notConnected
    case connectionFailed(String)
    case connectionLost(String)
    case tlsRejected
    case certificateChanged
    case pairingRejected
    case wrongCode
    case invalidCode
    case protocolError(String)
    case identity(String)

    var errorDescription: String? {
        switch self {
        case .localNetworkDenied:
            return "Accesso alla rete locale negato. Abilitalo in Impostazioni › Xiaomi Remote › Rete locale."
        case .timeout:
            return "La TV non risponde. Controlla che sia accesa e sulla stessa rete Wi-Fi."
        case .notConnected:
            return "TV non connessa: sto riprovando a collegarmi."
        case .connectionFailed(let m):
            return m
        case .connectionLost(let m):
            return "Connessione persa (\(m))."
        case .tlsRejected:
            return "La TV ha rifiutato la connessione sicura. Se l'hai ripristinata, ripeti l'associazione."
        case .certificateChanged:
            return "Il certificato della TV è cambiato dall'associazione. Se l'hai ripristinata, ripeti l'associazione."
        case .pairingRejected:
            return "La TV ha rifiutato l'associazione. Riprova: apparirà un nuovo codice."
        case .wrongCode:
            return "Codice errato. Controlla il codice mostrato sulla TV."
        case .invalidCode:
            return "Il codice deve avere 6 caratteri (0-9, A-F)."
        case .protocolError(let m):
            return "Risposta inattesa dalla TV (\(m))."
        case .identity(let m):
            return "Errore nel certificato dell'app (\(m))."
        }
    }

    /// Errori per cui è inutile riprovare in automatico.
    var isFatal: Bool {
        switch self {
        case .localNetworkDenied, .tlsRejected, .certificateChanged, .identity: return true
        default: return false
        }
    }
}

enum ErrorHandler {
    static func map(_ error: Error) -> TVError {
        if let e = error as? TVError { return e }
        if let n = error as? NWError {
            switch n {
            case .dns(let code) where code == -65570: // kDNSServiceErr_PolicyDenied
                return .localNetworkDenied
            case .tls:
                return .tlsRejected
            case .posix(let code):
                switch code {
                case .ECONNREFUSED:
                    return .connectionFailed("La TV rifiuta la connessione: è spenta o il servizio remoto non è attivo.")
                case .ETIMEDOUT:
                    return .timeout
                case .EHOSTUNREACH, .ENETUNREACH, .ENETDOWN:
                    return .connectionFailed("TV non raggiungibile: verifica di essere sulla stessa rete Wi-Fi.")
                default:
                    return .connectionFailed(n.localizedDescription)
                }
            default:
                return .connectionFailed(n.localizedDescription)
            }
        }
        return .connectionFailed(error.localizedDescription)
    }
}
