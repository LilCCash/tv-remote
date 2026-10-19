import XCTest
@testable import XiaomiRemote

@MainActor
final class ConnectionTests: XCTestCase {
    private func makeManager(attempts: Counter,
                             factory: @escaping @Sendable (Int) async throws -> RemoteSessionProtocol) -> TVConnectionManager {
        let storage = makeStorage()
        storage.saveTVs([SavedTV(id: UUID(), name: "Xiaomi", host: "10.0.0.2", port: 6466)])
        return TVConnectionManager(storage: storage,
                                   factory: { _ in try await factory(attempts.increment()) },
                                   policy: ReconnectPolicy(base: 0.01, cap: 0.02))
    }

    func testRetriesUntilTVAvailableWithSingleSession() async throws {
        let attempts = Counter()
        let session = MockSession()
        let manager = makeManager(attempts: attempts) { n in
            if n < 3 { throw TVError.timeout }
            return session
        }
        manager.startLoop()
        try await waitFor { manager.state == .connected }
        XCTAssertEqual(attempts.value, 3)
        XCTAssertEqual(manager.sessionsCreated, 1)
        manager.disconnect()
    }

    func testTVUnavailableStaysOfflineAndKeepsRetrying() async throws {
        let attempts = Counter()
        let manager = makeManager(attempts: attempts) { _ in throw TVError.connectionFailed("TV spenta") }
        manager.startLoop()
        try await waitFor { attempts.value >= 3 }
        if case .offline = manager.state {} else if case .reconnecting = manager.state {} else {
            XCTFail("Stato inatteso: \(manager.state)")
        }
        XCTAssertEqual(manager.sessionsCreated, 0)
        manager.disconnect()
    }

    func testLocalNetworkDeniedStopsRetrying() async throws {
        let attempts = Counter()
        let manager = makeManager(attempts: attempts) { _ in throw TVError.localNetworkDenied }
        manager.startLoop()
        try await waitFor { if case .failed = manager.state { return true } else { return false } }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(attempts.value, 1, "Con il permesso negato non ha senso riprovare in automatico")
    }

    func testConnectionLossReconnectsWithoutDuplicates() async throws {
        let attempts = Counter()
        let manager = makeManager(attempts: attempts) { _ in
            let s = MockSession()
            attempts.add(s)
            return s
        }
        manager.startLoop()
        try await waitFor { manager.state == .connected }
        attempts.sessions[0].close()                       // la TV cade
        try await waitFor { manager.sessionsCreated == 2 && manager.state == .connected }
        XCTAssertEqual(attempts.sessions.count, 2)
        manager.disconnect()
    }
}

@MainActor
final class CommandServiceTests: XCTestCase {
    private func makeService(session: RemoteSessionProtocol?, testMode: Bool = false,
                             onNotConnected: @escaping () -> Void = {}) -> RemoteCommandService {
        let prefs = Preferences(storage: makeStorage())
        prefs.testMode = testMode
        return RemoteCommandService(prefs: prefs, sessionProvider: { session }, onNotConnected: onNotConnected)
    }

    func testCommandsAreDeliveredInOrder() async {
        let session = MockSession()
        let service = makeService(session: session)
        service.press(.up)
        service.press(.down)
        service.press(.center)
        service.launch(appLink: "https://www.youtube.com")
        await service.waitUntilIdle()
        XCTAssertEqual(session.sentKeys, [19, 20, 23])
        XCTAssertEqual(session.launched, ["https://www.youtube.com"])
    }

    func testOfflineCommandIsDroppedNotQueued() {
        var kicks = 0
        let service = makeService(session: nil, onNotConnected: { kicks += 1 })
        service.press(.home)
        XCTAssertEqual(service.lastError, .notConnected)
        XCTAssertEqual(kicks, 1)
    }

    func testPackageNameIsSentAsMarketLink() async {
        let session = MockSession()
        let service = makeService(session: session)
        service.launch(appLink: "com.android.tv.settings")
        await service.waitUntilIdle()
        XCTAssertEqual(session.launched, ["market://launch?id=com.android.tv.settings"])
    }

    func testTestModeSendsNothing() async {
        let session = MockSession()
        let service = makeService(session: session, testMode: true)
        service.press(.volumeUp)
        await service.waitUntilIdle()
        XCTAssertTrue(session.sentKeys.isEmpty)
        XCTAssertEqual(service.testLog.count, 1)
    }

    func testKeyboardSyncSendsKeysAndDeletes() async {
        let session = MockSession()
        let commands = makeService(session: session)
        let keyboard = KeyboardInputService(commands: commands)
        keyboard.sync(old: "", new: "ab")
        keyboard.sync(old: "ab", new: "a")
        keyboard.sync(old: "a", new: "a😀")
        await commands.waitUntilIdle()
        XCTAssertEqual(session.sentKeys, [29, 30, 67])
        XCTAssertNotNil(keyboard.notice)
    }
}
