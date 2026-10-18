import SwiftUI
import Network

/// Schermata di prima configurazione (e di aggiunta di una nuova TV).
struct PairingView: View {
    let isOnboarding: Bool
    var onFinish: () -> Void = {}

    @EnvironmentObject private var connection: TVConnectionManager
    @StateObject private var discovery = TVDiscoveryService()
    @StateObject private var flow = PairingFlow()
    @State private var manualHost = ""
    @State private var code = ""
    @State private var verifyFailure: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                    }
                    .padding(20)
                    .frame(maxWidth: 460, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(isOnboarding ? "Collega la TV" : "Aggiungi una TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") { flow.reset(); onFinish() }
                    }
                }
            }
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
        .onChange(of: connection.state) { state in
            guard !isOnboarding, flow.step == .verifying else { return }
            switch state {
            case .connected: onFinish()
            case .offline(let m), .failed(let m): verifyFailure = m
            default: break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.step {
        case .idle:
            discoveryContent
        case .connecting:
            progress("Contatto la TV…", "Sulla TV comparirà un codice di associazione.")
        case .enterCode:
            codeContent
        case .verifying:
            VStack(alignment: .leading, spacing: 16) {
                progress("Verifico la connessione…", "Sto stabilendo il collegamento di controllo con la TV.")
                if let failure = verifyFailure {
                    Text(failure).foregroundStyle(.red)
                    Button("Riprova") { verifyFailure = nil; connection.retryNow() }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 16) {
                Label("Associazione non riuscita", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                Button("Torna alla ricerca") { flow.reset() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
    }

    // MARK: Ricerca

    @ViewBuilder
    private var discoveryContent: some View {
        Text("Accendi la TV e collega l'iPhone alla stessa rete Wi-Fi. Al primo avvio iOS chiede il permesso di accedere alla rete locale: serve per trovare la TV.")
            .foregroundStyle(.secondary)

        switch discovery.state {
        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                Label("Rete locale non consentita", systemImage: "wifi.exclamationmark").font(.headline)
                Text("Abilita «Rete locale» per Xiaomi Remote in Impostazioni, poi torna qui.")
                Button("Apri Impostazioni") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        case .failed(let message):
            Text("Ricerca non riuscita: \(message)").foregroundStyle(.red)
        case .searching where discovery.devices.isEmpty:
            HStack(spacing: 10) { ProgressView(); Text("Cerco le TV sulla rete…") }
        default:
            EmptyView()
        }

        ForEach(discovery.devices) { tv in
            Button {
                begin(name: tv.name, host: tv.host)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tv.name).font(.headline).foregroundStyle(.primary)
                        Text(tv.host ?? "Risoluzione dell'indirizzo…").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(KeyStyle(corner: 16))
            .disabled(tv.host == nil)
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("La TV non compare?").font(.headline)
            Text("Inserisci l'indirizzo IP (Impostazioni TV › Rete).").font(.footnote).foregroundStyle(.secondary)
            HStack {
                TextField("192.168.1.20", text: $manualHost)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .glassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("Collega") { begin(name: "Xiaomi TV", host: manualHost.trimmingCharacters(in: .whitespaces)) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(IPv4Address(manualHost.trimmingCharacters(in: .whitespaces)) == nil)
            }
        }
    }

    // MARK: Codice

    private var codeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inserisci il codice")
                .font(.title3.weight(.semibold))
            Text("Sulla TV è apparso un codice di 6 caratteri (cifre e lettere A–F).")
                .foregroundStyle(.secondary)
            TextField("A1B2C3", text: $code)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .padding(14)
                .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onChange(of: code) { value in
                    let cleaned = String(value.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(6))
                    if cleaned != value { code = cleaned }
                }
                .onAppear { codeFocused = true }
            if let error = flow.codeError {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
            Button {
                Task { await flow.submit(code: code, connection: connection) }
            } label: {
                Text("Associa").frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(code.count != 6)
            Button("Annulla", role: .cancel) { code = ""; flow.reset() }
        }
    }

    // MARK: Helper

    private func progress(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) { ProgressView(); Text(title).font(.headline) }
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func begin(name: String, host: String?) {
        guard let host else { return }
        code = ""
        verifyFailure = nil
        Task { await flow.start(name: name, host: host) }
    }
}
