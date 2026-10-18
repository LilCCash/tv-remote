import Foundation

/// Invia i comandi alla TV in ordine. Se la TV non è connessa il comando viene scartato
/// (e si avvia la riconnessione): non si accodano comandi che potrebbero scattare in ritardo.
@MainActor
final class RemoteCommandService: ObservableObject {
    @Published private(set) var testLog: [String] = []
    @Published private(set) var lastError: TVError?

    private let prefs: Preferences
    private let sessionProvider: () -> RemoteSessionProtocol?
    private let onNotConnected: () -> Void
    private var tail: Task<Void, Never>?
    private var pending = 0

    init(prefs: Preferences,
         sessionProvider: @escaping () -> RemoteSessionProtocol?,
         onNotConnected: @escaping () -> Void) {
        self.prefs = prefs
        self.sessionProvider = sessionProvider
        self.onNotConnected = onNotConnected
    }

    func press(_ key: RemoteKey, direction: KeyDirection = .short) {
        enqueue(label: "TASTO \(key.code)") { try await $0.send(key: key, direction: direction) }
    }

    /// Tasto premuto, tenuto e rilasciato (come un dito su un telecomando fisico).
    func hold(_ key: RemoteKey, milliseconds: Int) {
        enqueue(label: "TASTO \(key.code) TENUTO \(milliseconds) ms") { session in
            try await session.send(key: key, direction: .startLong)
            try? await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
            try await session.send(key: key, direction: .endLong)
        }
    }

    func perform(_ action: RemoteAction) {
        switch action.kind {
        case .key: press(RemoteKey(action.code))
        case .keyHold: hold(RemoteKey(action.code), milliseconds: action.holdMs)
        case .link: launch(appLink: action.link)
        }
    }

    func launch(appLink: String) {
        enqueue(label: "APP \(appLink)") { try await $0.launch(appLink: appLink) }
    }

    /// Per i test: attende l'invio dei comandi in coda.
    func waitUntilIdle() async { await tail?.value }

    private func enqueue(label: String, _ work: @escaping (RemoteSessionProtocol) async throws -> Void) {
        if prefs.testMode {
            testLog.append(label)
            if testLog.count > 50 { testLog.removeFirst(testLog.count - 50) }
            return
        }
        guard let session = sessionProvider() else {
            fail(.notConnected)
            onNotConnected()
            return
        }
        guard pending < 30 else { return }
        pending += 1
        let previous = tail
        tail = Task { [weak self] in
            await previous?.value
            do { try await work(session) } catch { self?.fail(ErrorHandler.map(error)) }
            self?.pending -= 1
        }
    }

    private func fail(_ error: TVError) {
        lastError = error
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self?.lastError == error { self?.lastError = nil }
        }
    }
}
