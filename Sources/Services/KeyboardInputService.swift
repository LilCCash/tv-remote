import Foundation

/// Scrive sulla TV usando i tasti Android (lettere, cifre, spazio, punteggiatura di base).
/// Funziona con qualsiasi campo di testo che abbia il focus sulla TV (es. ricerca di YouTube).
/// Limiti: niente emoji né simboli speciali; maiuscole e accenti vengono semplificati.
@MainActor
final class KeyboardInputService: ObservableObject {
    @Published private(set) var notice: String?
    private let commands: RemoteCommandService

    init(commands: RemoteCommandService) { self.commands = commands }

    nonisolated static func diff(old: String, new: String) -> (deletions: Int, inserted: String) {
        let o = Array(old), n = Array(new)
        var p = 0
        while p < o.count, p < n.count, o[p] == n[p] { p += 1 }
        return (o.count - p, String(n[p...]))
    }

    nonisolated static func key(for character: Character) -> RemoteKey? {
        let simplified = String(character).folding(options: .diacriticInsensitive, locale: nil).lowercased()
        guard simplified.unicodeScalars.count == 1, let scalar = simplified.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 97...122: return RemoteKey(29 + Int(scalar.value) - 97)   // a-z → KEYCODE_A...Z
        case 48...57: return RemoteKey(7 + Int(scalar.value) - 48)     // 0-9 → KEYCODE_0...9
        case 32: return RemoteKey(62)    // spazio
        case 44: return RemoteKey(55)    // ,
        case 46: return RemoteKey(56)    // .
        case 45: return RemoteKey(69)    // -
        case 61: return RemoteKey(70)    // =
        case 91: return RemoteKey(71)    // [
        case 93: return RemoteKey(72)    // ]
        case 92: return RemoteKey(73)    // \
        case 59: return RemoteKey(74)    // ;
        case 39: return RemoteKey(75)    // '
        case 47: return RemoteKey(76)    // /
        case 64: return RemoteKey(77)    // @
        case 43: return RemoteKey(81)    // +
        case 42: return RemoteKey(17)    // *
        case 35: return RemoteKey(18)    // #
        default: return nil
        }
    }

    func sync(old: String, new: String) {
        let change = Self.diff(old: old, new: new)
        for _ in 0..<change.deletions { commands.press(.delete) }
        var skipped = 0
        for character in change.inserted {
            if let key = Self.key(for: character) { commands.press(key) } else { skipped += 1 }
        }
        notice = skipped > 0 ? "\(skipped) caratteri non supportati ignorati." : nil
    }

    func submit() { commands.press(.enter) }
    func backspace() { commands.press(.delete) }
}
