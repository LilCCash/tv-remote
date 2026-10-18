import Foundation

@MainActor
final class Preferences: ObservableObject {
    @Published var haptics: Bool { didSet { storage.hapticsEnabled = haptics } }
    @Published var testMode: Bool { didSet { storage.testMode = testMode } }
    private let storage: DeviceStorage

    init(storage: DeviceStorage) {
        self.storage = storage
        haptics = storage.hapticsEnabled
        testMode = storage.testMode
    }
}

@MainActor
final class AppModel: ObservableObject {
    let storage: DeviceStorage
    let prefs: Preferences
    let connection: TVConnectionManager
    let commands: RemoteCommandService
    let keyboard: KeyboardInputService

    init() {
        let storage = DeviceStorage()
        let prefs = Preferences(storage: storage)
        let connection = TVConnectionManager(storage: storage)
        let commands = RemoteCommandService(prefs: prefs,
                                            sessionProvider: { [weak connection] in connection?.session },
                                            onNotConnected: { [weak connection] in connection?.retryNow() })
        self.storage = storage
        self.prefs = prefs
        self.connection = connection
        self.commands = commands
        self.keyboard = KeyboardInputService(commands: commands)
    }
}
