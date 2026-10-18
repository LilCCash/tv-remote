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
                    ForEach(ActionCatalog.inputMethods) { method in
                        Button {
                            Haptics.tap(prefs.haptics)
                            prefs.inputMethodID = method.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(method.title).foregroundStyle(.primary)
                                    Text(method.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if method.id == prefs.inputMethodID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Metodo")
                } footer: {
                    Text("Prova «HDMI 1» qui sotto: se la TV non cambia ingresso, scegli un altro metodo e riprova. Quello che funziona viene ricordato.")
                }

                Section("Passa a") {
                    ForEach(ActionCatalog.inputMethod(id: prefs.inputMethodID).hdmi) { action in
                        actionRow(action, icon: "cable.connector")
                    }
                    actionRow(ActionCatalog.liveTV, icon: "tv")
                }

                Section {
                    ForEach(ActionCatalog.selectorActions) { action in
                        actionRow(action, icon: "list.bullet.rectangle")
                    }
                } header: {
                    Text("Selettore ingressi (tasto INPUT)")
                } footer: {
                    Text("Su molte TV il tasto INPUT inviato via rete viene ignorato: è un limite del protocollo, non dell'app. Se non succede nulla usa i metodi sopra. Dopo aver aperto il selettore scegli con frecce e OK.")
                }
            }
            .navigationTitle("Ingressi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func actionRow(_ action: RemoteAction, icon: String) -> some View {
        Button {
            Haptics.confirm(prefs.haptics)
            commands.perform(action)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).foregroundStyle(.primary)
                    Text(action.detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
            }
        }
    }
}

// MARK: - Tasto Menu / SET

/// Ogni TV e ogni app reagiscono in modo diverso al «menu»: qui si prova ciascun comando e si sceglie quello giusto.
struct MenuKeyList: View {
    @EnvironmentObject private var commands: RemoteCommandService
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        List {
            Section {
                Text("Sul tuo telecomando il tasto si chiama «SET». Apri un'app sulla TV, tocca «Prova» sulle voci qui sotto finché compare il menu o le opzioni che ti servono, poi tocca «Usa»: il tasto Menu dell'app farà quella cosa.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(ActionCatalog.menuCandidates) { action in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(action.title).font(.subheadline.weight(.semibold))
                        Text(action.detail).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Prova") {
                                Haptics.confirm(prefs.haptics)
                                commands.perform(action)
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            if prefs.menuAction.id == action.id {
                                Label("In uso", systemImage: "checkmark.circle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            } else {
                                Button("Usa") { prefs.menuAction = action }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.accent)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("Tenendo premuto il tasto Menu nella schermata principale compare lo stesso elenco.")
            }
        }
        .navigationTitle("Tasto Menu")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MenuKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MenuKeyList()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.large])
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
                    .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: text) { new in
                        keyboard.sync(old: previous, new: new)
                        previous = new
                    }
                GlassGroup(spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            if text.isEmpty { keyboard.backspace() } else { text.removeLast() }
                        } label: {
                            Label("Cancella", systemImage: "delete.left").frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(KeyStyle(corner: 16))
                        Button { keyboard.submit() } label: {
                            Label("Invio", systemImage: "return")
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(KeyStyle(corner: 16, tint: Theme.accent))
                    }
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
    @State private var finger: CGPoint?
    @State private var accumulated = CGSize.zero
    @State private var moved = false
    private let step: CGFloat = 36

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Scorri per muoverti, tocca per confermare. Android TV non ha un puntatore: i gesti diventano frecce e OK.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.clear)
                    .glassSurface(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .overlay {
                        ZStack {
                            Text("Scorri o tocca").foregroundStyle(.secondary)
                            if let finger {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 68, height: 68)
                                    .glassSurface(Circle(), tint: Theme.accent.opacity(0.7))
                                    .position(finger)
                            }
                        }
                        .animation(.interactiveSpring(), value: finger)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { finger = $0.location; drag($0) }
                        .onEnded { finger = nil; end($0) })
                    .accessibilityElement()
                    .accessibilityLabel("Touchpad")
                    .accessibilityAction(.default) { fire(.center) }
                    .accessibilityAction(named: "Su") { fire(.up) }
                    .accessibilityAction(named: "Giù") { fire(.down) }
                    .accessibilityAction(named: "Sinistra") { fire(.left) }
                    .accessibilityAction(named: "Destra") { fire(.right) }
                GlassGroup(spacing: 8) {
                    HStack(spacing: 10) {
                        KeyButton(icon: "arrow.uturn.backward", title: "Indietro") { fire(.back) }
                        KeyButton(icon: "house", title: "Home") { fire(.home) }
                    }
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
