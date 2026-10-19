import SwiftUI

/// Cambio ingresso. I pulsanti usano i «link di ingresso» (funzionano sulla TV dell'utente);
/// il tasto INPUT e il selettore, che la TV ignora quando arrivano dalla rete, restano tra le opzioni avanzate.
struct SourceSheet: View {
    @EnvironmentObject private var commands: RemoteCommandService
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @State private var lastSent: String?
    @State private var showAdvanced = false

    private var method: InputMethod { ActionCatalog.inputMethod(id: prefs.inputMethodID) }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Tocca la sorgente: la TV passa direttamente a quell'ingresso.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        GlassGroup(spacing: 8) {
                            HStack(spacing: 12) {
                                ForEach(method.hdmi) { action in bigKey(action) }
                            }
                        }

                        DisclosureGroup(isExpanded: $showAdvanced) {
                            VStack(alignment: .leading, spacing: 16) {
                                card {
                                    Text("Metodo di cambio ingresso").font(.subheadline.weight(.semibold))
                                    Text("Se «HDMI 1» non cambia ingresso, prova un altro metodo.")
                                        .font(.caption).foregroundStyle(.secondary)
                                    ForEach(ActionCatalog.inputMethods) { item in methodRow(item) }
                                }
                                card {
                                    Text("Selettore e tasti dedicati").font(.subheadline.weight(.semibold))
                                    Text("Su questa TV il tasto INPUT inviato via rete viene ignorato: è la TV a scartarlo, non l'app. Restano qui per altri modelli.")
                                        .font(.caption).foregroundStyle(.secondary)
                                    ForEach(ActionCatalog.selectorActions + [ActionCatalog.liveTV]) { action in
                                        actionRow(action)
                                    }
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Text("Opzioni avanzate").font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Ingressi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func bigKey(_ action: RemoteAction) -> some View {
        let selected = lastSent == action.id
        return Button {
            Haptics.confirm(prefs.haptics)
            lastSent = action.id
            commands.perform(action)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "cable.connector").font(.system(size: 26, weight: .semibold))
                Text(action.title).font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 112)
        }
        .buttonStyle(KeyStyle(corner: 26, tint: selected ? Theme.accent : nil))
        .accessibilityLabel(action.title)
    }

    private func methodRow(_ item: InputMethod) -> some View {
        Button {
            Haptics.tap(prefs.haptics)
            prefs.inputMethodID = item.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).foregroundStyle(.primary)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if item.id == prefs.inputMethodID {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(_ action: RemoteAction) -> some View {
        Button {
            Haptics.confirm(prefs.haptics)
            commands.perform(action)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).foregroundStyle(.primary)
                    Text(action.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "paperplane").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
