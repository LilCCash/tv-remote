import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var connection: TVConnectionManager
    @EnvironmentObject private var commands: RemoteCommandService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Feedback") {
                    Toggle("Vibrazione sui tasti", isOn: $prefs.haptics)
                }

                if let tv = connection.current {
                    Section("TV selezionata") {
                        TextField("Nome", text: $name)
                            .onSubmit { connection.rename(tv, to: name) }
                        Button("Salva nome") { connection.rename(tv, to: name) }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == tv.name)
                        LabeledContent("Indirizzo", value: tv.host)
                        Button("Dimentica questa TV", role: .destructive) {
                            connection.forget(tv)
                            dismiss()
                        }
                    }
                }

                Section {
                    Toggle("Modalità test", isOn: $prefs.testMode)
                } header: {
                    Text("Sviluppo")
                } footer: {
                    Text("Con la modalità test attiva i comandi non vengono inviati alla TV: restano solo registrati qui sotto.")
                }

                if prefs.testMode && !commands.testLog.isEmpty {
                    Section("Comandi registrati") {
                        ForEach(Array(commands.testLog.enumerated().reversed()), id: \.offset) { _, line in
                            Text(line).font(.system(.footnote, design: .monospaced))
                        }
                    }
                }

                Section("Cosa funziona") {
                    info("Implementato", "Frecce, OK, Indietro, Home, Menu, Impostazioni della TV, volume, muto, riproduzione, scrittura di testo, avvio di app tramite link, selettore ingressi.")
                    info("Dipende da TV e app", "Ingressi HDMI diretti, tasto Recenti, comandi multimediali (solo nelle app che li gestiscono), scorciatoie delle app, stato acceso/standby.")
                    info("Non disponibile", "Accensione da TV completamente spenta (Wake-on-LAN non incluso), elenco di ingressi e app installate, titolo in riproduzione, puntatore del mouse, controllo di soundbar esterne.")
                }

                Section("Privacy") {
                    Text("Tutto avviene sulla rete locale. Sul dispositivo vengono salvati: nome e indirizzo delle TV, le preferenze, il certificato dell'app e l'impronta del certificato della TV (nel Keychain). Nessun account, nessun server esterno, nessuna pubblicità.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            .onAppear { name = connection.current?.name ?? "" }
        }
    }

    private func info(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
