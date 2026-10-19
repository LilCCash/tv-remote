import SwiftUI

/// Controlli video avanzati e app in uso. Il supporto di ogni tasto dipende dall'app e dalla TV.
struct VideoSheet: View {
    @EnvironmentObject private var connection: TVConnectionManager
    @EnvironmentObject private var commands: RemoteCommandService
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        nowPlaying

                        section("Riproduzione") {
                            grid([
                                ("stop.fill", "Stop", .stop),
                                ("play.fill", "Play", .play),
                                ("pause.fill", "Pausa", .pause)
                            ])
                        }

                        section("Cerca nel video", footer: "Tieni premuto Riavvolgi o Avanti per ripetere. In molte app ogni tocco sposta di circa 10 secondi.") {
                            GlassGroup(spacing: 8) {
                                HStack(spacing: 10) {
                                    seekKey("gobackward.10", "Riavvolgi", .rewind)
                                    seekKey("goforward.10", "Avanti", .fastForward)
                                }
                            }
                            grid([
                                ("backward.end.alt.fill", "Salta indietro", .skipBackward),
                                ("forward.end.alt.fill", "Salta avanti", .skipForward),
                                ("backward.frame.fill", "Fotogramma −", .stepBackward),
                                ("forward.frame.fill", "Fotogramma +", .stepForward)
                            ], columns: 2)
                        }

                        section("Audio e sottotitoli") {
                            grid([
                                ("captions.bubble", "Sottotitoli", .captions),
                                ("waveform", "Traccia audio", .audioTrack),
                                ("info.circle", "Info", .info),
                                ("arrow.up.left.and.arrow.down.right", "Formato", .zoomMode)
                            ], columns: 2)
                        }

                        section("TV in diretta") {
                            grid([
                                ("chevron.down.circle", "Canale −", .channelDown),
                                ("chevron.up.circle", "Canale +", .channelUp),
                                ("arrow.uturn.backward.circle", "Ultimo", .lastChannel),
                                ("list.bullet.rectangle", "Guida", .guide)
                            ], columns: 2)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    // MARK: Riconoscimento

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: "play.tv")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("In uso sulla TV").font(.caption).foregroundStyle(.secondary)
                    Text(appTitle).font(.system(.title3, design: .rounded).weight(.semibold))
                    if let package = connection.currentApp?.package {
                        Text(package).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
            Text("La TV comunica solo l'app in primo piano, non il titolo del video: è un limite del protocollo di controllo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var appTitle: String {
        guard connection.state == .connected else { return "TV non connessa" }
        return connection.currentApp?.displayName ?? "Non rilevata"
    }

    // MARK: Componenti

    private func section<Content: View>(_ title: String, footer: String? = nil,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            content()
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func grid(_ items: [(String, String, RemoteKey)], columns: Int = 3) -> some View {
        GlassGroup(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    KeyButton(icon: item.0, title: item.1, height: 66) { fire(item.2) }
                }
            }
        }
    }

    private func seekKey(_ icon: String, _ title: String, _ key: RemoteKey) -> some View {
        RepeatButton(action: { fire(key) }) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 26, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .glassSurface(RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
        }
        .accessibilityLabel(title)
    }

    private func fire(_ key: RemoteKey) {
        Haptics.tap(prefs.haptics)
        commands.press(key)
    }
}
