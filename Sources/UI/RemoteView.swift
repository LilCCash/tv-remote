import SwiftUI

struct RemoteView: View {
    @EnvironmentObject private var connection: TVConnectionManager
    @EnvironmentObject private var commands: RemoteCommandService
    @EnvironmentObject private var prefs: Preferences
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case tvs, pairing, settings, source, menuKey, keyboard, touchpad, apps
        var id: String { rawValue }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackground()
            GeometryReader { geo in
                let pad = min(geo.size.width * 0.74, max(176, geo.size.height - 410), 300)
                VStack(spacing: 14) {
                    header
                    DPad(size: pad, press: { send($0) })
                    navRow
                    mediaRow
                    bottomBlock
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            if let error = commands.lastError { toast(error) }
        }
        .animation(.easeInOut(duration: 0.2), value: commands.lastError)
        .onChange(of: connection.state) { state in
            if state == .connected { Haptics.success(prefs.haptics) }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .tvs: TVListSheet(onAdd: { sheet = .pairing })
            case .pairing: PairingView(isOnboarding: false, onFinish: { sheet = nil })
            case .settings: SettingsView()
            case .source: SourceSheet()
            case .menuKey: MenuKeySheet()
            case .keyboard: KeyboardSheet()
            case .touchpad: TouchpadSheet()
            case .apps: AppsSheet()
            }
        }
    }

    // MARK: Sezioni

    private var header: some View {
        HStack(spacing: 10) {
            Button { sheet = .tvs } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: statusColor.opacity(0.8), radius: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(connection.current?.name ?? "TV")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(KeyStyle(corner: 22))
            .accessibilityLabel("\(connection.current?.name ?? "TV"), \(statusText). Tocca per cambiare TV.")

            if showRetry {
                Button { connection.retryNow() } label: {
                    Text("Riprova")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                }
                .buttonStyle(KeyStyle(corner: 22, tint: Theme.accent))
            }
            roundButton("power", "Accensione e spegnimento", tint: powerTint) { send(.power, strong: true) }
            roundButton("gearshape", "Impostazioni dell'app") { sheet = .settings }
        }
        .padding(.top, 4)
    }

    private var navRow: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 10) {
                KeyButton(icon: "arrow.uturn.backward", title: "Indietro") { send(.back) }
                KeyButton(icon: "house", title: "Home") { send(.home) }
                KeyButton(icon: "line.3.horizontal", title: "Menu") {
                    Haptics.tap(prefs.haptics)
                    commands.perform(prefs.menuAction)
                }
                .contextMenu { menuContext }
                KeyButton(icon: "square.on.square", title: "Recenti") { send(.appSwitch) }
            }
        }
    }

    /// Tenendo premuto «Menu» compaiono le alternative: utile perché ogni app e ogni TV reagisce in modo diverso.
    @ViewBuilder
    private var menuContext: some View {
        ForEach(ActionCatalog.menuCandidates) { action in
            Button(action.title) {
                Haptics.tap(prefs.haptics)
                commands.perform(action)
            }
        }
        Button { sheet = .menuKey } label: {
            Label("Scegli il tasto Menu…", systemImage: "slider.horizontal.3")
        }
    }

    private var mediaRow: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 10) {
                mediaButton("backward.end.fill", "Traccia precedente", .previous)
                mediaButton("backward.fill", "Riavvolgi", .rewind)
                Button { send(.playPause, strong: true) } label: {
                    Image(systemName: "playpause.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(KeyStyle(corner: 22, tint: Theme.accent))
                .accessibilityLabel("Riproduci o pausa")
                mediaButton("forward.fill", "Avanzamento veloce", .fastForward)
                mediaButton("forward.end.fill", "Traccia successiva", .next)
            }
        }
    }

    private var bottomBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            volumePill
            GlassGroup(spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    KeyButton(icon: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", title: "Muto",
                              tint: muted ? .orange : nil, height: 62) { send(.mute) }
                    KeyButton(icon: "rectangle.on.rectangle", title: "Ingressi", height: 62) { sheet = .source }
                    KeyButton(icon: "keyboard", title: "Tastiera", height: 62) { sheet = .keyboard }
                    KeyButton(icon: "hand.point.up.left", title: "Touchpad", height: 62) { sheet = .touchpad }
                    KeyButton(icon: "square.grid.2x2", title: "App", height: 62) { sheet = .apps }
                    KeyButton(icon: "slider.horizontal.3", title: "Impost. TV", height: 62) { send(.settings) }
                }
            }
        }
    }

    private var volumePill: some View {
        VStack(spacing: 0) {
            RepeatButton(action: { send(.volumeUp) }) {
                Image(systemName: "plus").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
            }
            .accessibilityLabel("Volume più")
            Text(connection.volume.map { String($0.level) } ?? "Vol")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
            RepeatButton(action: { send(.volumeDown) }) {
                Image(systemName: "minus").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
            }
            .accessibilityLabel("Volume meno")
        }
        .frame(width: 64, height: 134)
        .glassSurface(Capsule())
    }

    // MARK: Helper

    private func toast(_ error: TVError) -> some View {
        Text(error.localizedDescription)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func mediaButton(_ icon: String, _ label: String, _ key: RemoteKey) -> some View {
        Button { send(key) } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(KeyStyle(corner: 22))
        .accessibilityLabel(label)
    }

    private func roundButton(_ icon: String, _ label: String, tint: Color? = nil,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(KeyStyle(corner: 22))
        .accessibilityLabel(label)
    }

    private func send(_ key: RemoteKey, strong: Bool = false) {
        if strong || key == .center { Haptics.confirm(prefs.haptics) } else { Haptics.tap(prefs.haptics) }
        commands.press(key)
    }

    private var muted: Bool { connection.volume?.muted ?? false }

    private var powerTint: Color? {
        switch connection.isPoweredOn {
        case .some(true): return Theme.accent
        case .some(false): return .orange
        case .none: return nil
        }
    }

    private var showRetry: Bool {
        switch connection.state {
        case .offline, .failed: return true
        default: return false
        }
    }

    private var statusColor: Color {
        switch connection.state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        default: return .red
        }
    }

    private var statusText: String {
        switch connection.state {
        case .idle: return "Non connessa"
        case .connecting: return "Connessione in corso…"
        case .connected: return connection.isPoweredOn == false ? "Connessa · TV in standby" : "Connessa"
        case .reconnecting(let n): return "Riconnessione (tentativo \(n))…"
        case .offline(let message), .failed(let message): return message
        }
    }
}
