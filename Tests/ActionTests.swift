import XCTest
@testable import XiaomiRemote

@MainActor
final class ActionTests: XCTestCase {
    private func makeService(session: RemoteSessionProtocol?, testMode: Bool = false) -> RemoteCommandService {
        let prefs = Preferences(storage: makeStorage())
        prefs.testMode = testMode
        return RemoteCommandService(prefs: prefs, sessionProvider: { session }, onNotConnected: {})
    }

    func testHoldSendsPressThenRelease() async {
        let session = MockSession()
        let service = makeService(session: session)
        service.hold(RemoteKey.menu, milliseconds: 5)
        await service.waitUntilIdle()
        XCTAssertEqual(session.sentKeys, [82, 82])
        XCTAssertEqual(session.directions, [KeyDirection.startLong.rawValue, KeyDirection.endLong.rawValue])
    }

    func testPerformDispatchesByKind() async {
        let session = MockSession()
        let service = makeService(session: session)
        service.perform(.keyPress("a", "A", "", code: 19))
        service.perform(.keyHold("b", "B", "", code: 23, ms: 1))
        service.perform(.openLink("c", "C", "", url: "content://x/y"))
        await service.waitUntilIdle()
        XCTAssertEqual(session.sentKeys, [19, 23, 23])
        XCTAssertEqual(session.directions, [3, 1, 2])
        XCTAssertEqual(session.launched, ["content://x/y"])
    }

    func testHoldIsOnlyLoggedInTestMode() async {
        let session = MockSession()
        let service = makeService(session: session, testMode: true)
        service.hold(RemoteKey.settings, milliseconds: 100)
        await service.waitUntilIdle()
        XCTAssertTrue(session.sentKeys.isEmpty)
        XCTAssertTrue(service.testLog.first?.contains("TENUTO") ?? false)
    }

    func testCatalogIsConsistent() {
        let methodActions = ActionCatalog.inputMethods.flatMap { $0.hdmi }
        let all = ActionCatalog.menuCandidates + ActionCatalog.selectorActions + methodActions + [ActionCatalog.liveTV]
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "ID duplicati nel catalogo")

        for action in all where action.kind == .link {
            XCTAssertTrue(action.link.hasPrefix("content://android.media.tv/passthrough/"), action.link)
            XCTAssertTrue(action.link.contains("%2FHW"), "Serve %2F tra servizio e HW: \(action.link)")
        }
        for action in all where action.kind != .link {
            XCTAssertGreaterThan(action.code, 0)
        }
        for action in all where action.kind == .keyHold {
            XCTAssertGreaterThan(action.holdMs, 0)
        }
    }

    func testKnownInputLinks() {
        let amlogic = ActionCatalog.inputMethod(id: "amlogic").hdmi
        XCTAssertEqual(amlogic.map(\.link), [
            "content://android.media.tv/passthrough/com.droidlogic.tvinput%2F.services.Hdmi1InputService%2FHW5",
            "content://android.media.tv/passthrough/com.droidlogic.tvinput%2F.services.Hdmi2InputService%2FHW6",
            "content://android.media.tv/passthrough/com.droidlogic.tvinput%2F.services.Hdmi3InputService%2FHW7"
        ])
        let mtkA = ActionCatalog.inputMethod(id: "mediatek-a").hdmi
        XCTAssertTrue(mtkA[1].link.hasSuffix("HDMIInputService%2FHW5"))
        XCTAssertEqual(ActionCatalog.inputMethod(id: "inesistente").id, ActionCatalog.inputMethods[0].id)
        XCTAssertEqual(ActionCatalog.defaultInputMethodID, "amlogic")
    }

    func testChoicesArePersisted() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let first = DeviceStorage(defaults: defaults)
        XCTAssertEqual(first.menuAction, ActionCatalog.menuDefault)
        XCTAssertEqual(first.inputMethodID, "amlogic")

        let chosen = ActionCatalog.menuCandidates.first { $0.id == "ok.long" }!
        first.menuAction = chosen
        first.inputMethodID = "mediatek-b"

        let second = DeviceStorage(defaults: defaults)
        XCTAssertEqual(second.menuAction, chosen)
        XCTAssertEqual(second.inputMethodID, "mediatek-b")
    }
}
