import SwiftUI

@main
struct XiaomiRemoteApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model.connection)
                .environmentObject(model.commands)
                .environmentObject(model.keyboard)
                .environmentObject(model.prefs)
                .task { model.connection.bootstrap() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var connection: TVConnectionManager
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if connection.current == nil {
                PairingView(isOnboarding: true)
            } else {
                RemoteView()
            }
        }
        .onChange(of: phase) { newPhase in
            switch newPhase {
            case .active: connection.appDidBecomeActive()
            case .background: connection.appDidEnterBackground()
            default: break
            }
        }
    }
}
