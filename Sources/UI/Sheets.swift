import SwiftUI

// MARK: - Elenco TV

struct TVListSheet: View {
    @EnvironmentObject private var connection: TVConnectionManager
    @Environment(\.dismiss) private var dismiss
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(connection.savedTVs) { tv in
                        Button {
                            connection.select(tv)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.name).foregroundStyle(.primary)
                                    Text(tv.host).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if tv.id == connection.current?.id {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button { onAdd() } label: { Label("Aggiungi una TV", systemImage: "plus") }
                }
            }
            .navigationTitle("Le tue TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Ingressi

struct SourceSheet: View {
    @EnvironmentObject private var commands: RemoteCommandService
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Selettore ingressi", "Apre l'elenco delle sorgenti sulla TV", "list.bullet.rectangle", .tvInput)
                    row("TV in diretta", "Torna al canale in onda", "tv", .liveTV)
                } footer: {
                    Text("Dopo aver aperto il selettore, scegli la sorgente con le frecce e OK.")
                }
                Section {
                    row("HDMI 1", "Passa direttamente a HDMI 1", "cable.connector", .hdmi1)
                    row("HDMI 2", "Passa direttamente a HDMI 2", "cable.connector", .hdmi2)
                    row("HDMI 3", "Passa direttamente a HDMI 3", "cable.connector", .hdmi3)
                } header: {
                    Text("Ingressi diretti")
                } footer: {
                    Text("Funzionano solo se la TV riconosce questi tasti. L'app non può leggere l'elenco degli ingressi: se non succede nulla, usa il selettore.")
                }
            }
            .navigationTitle("Ingressi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, _ subtitle: String, _ icon: String, _ key: RemoteKey) -> some View {
        Button {
            Haptics.tap(prefs.haptics)
            commands.press(key)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
            }
        }
    }
}

// MARK: - Tastiera

struct KeyboardSheet: View {
    @EnvironmentObject private var keyboard: KeyboardInputService
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var previous = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Apri prima un campo di ricerca sulla TV, poi scrivi qui: ogni carattere viene inviato subito.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Scrivi qui", text: $text)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { keyboard.submit() }
                    .padding(14)
                    .background(Theme.key, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: text) { new in
                        keyboard.sync(old: previous, new: new)
                        previous = new
                    }
                HStack(spacing: 10) {
                    Button {
                        if text.isEmpty { keyboard.backspace() } else { text.removeLast() }
                    } label: {
                        Label("Cancella", systemImage: "delete.left").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(KeyStyle(corner: 14))
                    Button { keyboard.submit() } label: {
                        Label("Invio", systemImage: "return").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(KeyStyle(corner: 14))
                }
                if let notice = keyboard.notice {
                    Text(notice).font(.footnote).foregroundStyle(.orange)
                }
                Text("Maiuscole e accenti vengono semplificati; emoji e simboli speciali non sono supportati.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Tastiera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Touchpad

struct TouchpadSheet: View {
    @EnvironmentObject private var commands: RemoteCommandService
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @State private var last: CGPoint?
    @State private var accumulated = CGSize.zero
    @State private var moved = false
    private let step: CGFloat = 36

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Scorri per muoverti, tocca per confermare. Android TV non ha un puntatore: i gesti diventano frecce e OK.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Theme.key)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    .overlay(Text("Touchpad").foregroundStyle(.secondary))
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag($0) }
                        .onEnded { end($0) })
                    .accessibilityElement()
                    .accessibilityLabel("Touchpad")
                    .accessibilityAction(.default) { fire(.center) }
                    .accessibilityAction(named: "Su") { fire(.up) }
                    .accessibilityAction(named: "Giù") { fire(.down) }
                    .accessibilityAction(named: "Sinistra") { fire(.left) }
                    .accessibilityAction(named: "Destra") { fire(.right) }
                HStack(spacing: 10) {
                    KeyButton(icon: "arrow.uturn.backward", title: "Indietro") { fire(.back) }
                    KeyButton(icon: "house", title: "Home") { fire(.home) }
                }
            }
            .padding()
            .navigationTitle("Touchpad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func drag(_ value: DragGesture.Value) {
        let point = value.location
        guard let previous = last else { last = point; return }
        accumulated.width += point.x - previous.x
        accumulated.height += point.y - previous.y
        last = point
        guard abs(accumulated.width) >= step || abs(accumulated.height) >= step else { return }
        moved = true
        if abs(accumulated.width) > abs(accumulated.height) {
            fire(accumulated.width > 0 ? .right : .left)
        } else {
            fire(accumulated.height > 0 ? .down : .up)
        }
        accumulated = .zero
    }

    private func end(_ value: DragGesture.Value) {
        if !moved && hypot(value.translation.width, value.translation.height) < 10 { fire(.center) }
        last = nil
        accumulated = .zero
        moved = false
    }

    private func fire(_ key: RemoteKey) {
        Haptics.tap(prefs.haptics)
        commands.press(key)
    }
}

// MARK: - Scorciatoie app

struct AppsSheet: View {
    @EnvironmentObject private var commands: RemoteCommandService
    @EnvironmentObject private var connection: TVConnectionManager
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @State private var custom: [Shortcut] = []
    @State private var newName = ""
    @State private var newLink = ""

    private let builtIn: [(name: String, link: String)] = [
        ("YouTube", "https://www.youtube.com"),
        ("Netflix", "https://www.netflix.com"),
        ("Prime Video", "https://app.primevideo.com"),
        ("Disney+", "https://www.disneyplus.com")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(builtIn, id: \.name) { item in launchRow(item.name, item.link) }
                } header: {
                    Text("Scorciatoie")
                } footer: {
                    Text("L'app invia alla TV un link: si apre solo se l'app corrispondente è installata e registrata per quel link. L'elenco delle app installate non è leggibile da qui.")
                }
                Section("Le tue scorciatoie") {
                    ForEach(custom) { item in launchRow(item.name, item.link) }
                        .onDelete { offsets in
                            custom.remove(atOffsets: offsets)
                            connection.storage.saveShortcuts(custom)
                        }
                    TextField("Nome", text: $newName)
                    TextField("Link (es. https://…)", text: $newLink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Aggiungi scorciatoia") {
                        custom.append(Shortcut(id: UUID(),
                                               name: newName.trimmingCharacters(in: .whitespaces),
                                               link: newLink.trimmingCharacters(in: .whitespaces)))
                        connection.storage.saveShortcuts(custom)
                        newName = ""
                        newLink = ""
                    }
                    .disabled(!canAdd)
                }
            }
            .navigationTitle("App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            .onAppear { custom = connection.storage.loadShortcuts() }
        }
        .presentationDetents([.medium, .large])
    }

    private var canAdd: Bool {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let link = newLink.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && URL(string: link)?.scheme != nil
    }

    private func launchRow(_ name: String, _ link: String) -> some View {
        Button {
            Haptics.tap(prefs.haptics)
            commands.launch(appLink: link)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary)
                Text(link).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
