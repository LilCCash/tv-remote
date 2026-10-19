import SwiftUI

/// Scorciatoie verso app e pagine di sistema. Si può inserire un link oppure il nome di un pacchetto Android.
struct AppsSheet: View {
    @EnvironmentObject private var commands: RemoteCommandService
    @EnvironmentObject private var connection: TVConnectionManager
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @State private var custom: [Shortcut] = []
    @State private var newName = ""
    @State private var newLink = ""

    private let system: [(name: String, link: String)] = [
        ("Impostazioni della TV", "com.android.tv.settings"),
        ("Play Store", "com.android.vending")
    ]

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
                    ForEach(system, id: \.name) { item in launchRow(item.name, item.link) }
                } header: {
                    Text("Sistema")
                } footer: {
                    Text("Aprono le app di sistema della TV tramite il nome del pacchetto: utili quando i tasti Menu e SET vengono ignorati.")
                }
                Section {
                    ForEach(builtIn, id: \.name) { item in launchRow(item.name, item.link) }
                } header: {
                    Text("Scorciatoie")
                } footer: {
                    Text("L'app invia alla TV un link: si apre solo se l'app corrispondente è installata e registrata per quel link. L'elenco delle app installate non è leggibile da qui.")
                }
                Section {
                    ForEach(custom) { item in launchRow(item.name, item.link) }
                        .onDelete { offsets in
                            custom.remove(atOffsets: offsets)
                            connection.storage.saveShortcuts(custom)
                        }
                    TextField("Nome", text: $newName)
                    TextField("Link o pacchetto (es. com.netflix.ninja)", text: $newLink)
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
                } header: {
                    Text("Le tue scorciatoie")
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
        !newName.trimmingCharacters(in: .whitespaces).isEmpty && AppLink.isValid(newLink)
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
