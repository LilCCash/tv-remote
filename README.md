# Xiaomi Remote (iOS)

Telecomando per **Xiaomi Android TV / Google TV** sulla stessa rete Wi-Fi. SwiftUI, nessuna dipendenza esterna,
nessun account, nessun server, nessuna pubblicità. iOS 16 o successivo, solo iPhone.

> **Stato onesto:** il codice è stato scritto e rivisto ma l'ambiente di sviluppo non aveva Swift/Xcode: **i sorgenti
> non sono stati compilati qui e i test unitari non sono stati eseguiti**. Le correzioni su Menu e Ingressi (v1.1) si basano
> su documentazione e segnalazioni di altri utenti, **non su una prova sulla tua TV**: per questo l'app ora ti lascia
> *provare e scegliere* (vedi «Menu/SET» e «Ingressi»). Vedi anche «Cosa è verificato».

## Protocollo scelto

**Android TV Remote Protocol v2** (lo stesso dell'app Google TV): non richiede ADB né modalità sviluppatore.
La TV deve avere il servizio *Android TV Remote Service*, preinstallato sulla maggior parte delle Android TV.

| Fase | Dettaglio |
|---|---|
| Scoperta | mDNS/Bonjour `_androidtvremote2._tcp` (+ inserimento manuale dell'IP) |
| Associazione | TLS sulla porta **6467**, messaggi protobuf "polo"; la TV mostra un codice a 6 caratteri; segreto = SHA-256(modulo/esponente client, modulo/esponente TV, ultimi 2 byte del codice) |
| Controllo | TLS sulla porta **6466** con certificato client; `RemoteKeyInject` (codici tasto Android), `RemoteAppLinkLaunchRequest` (link di app), ping/handshake |

Fonti consultate: `remotemessage.proto` e documentazione del pairing della libreria `androidtvremote2`
(tronikos), schemi `pairingmessage.proto` dei client di riferimento (louis49/androidtv-remote).

**Non inclusi, e perché:** ADB (richiede debug di rete attivato dall'utente, non standard), HDMI-CEC (nessun percorso
dall'iPhone senza hardware esterno), Wake-on-LAN (serve il MAC e la TV deve supportarlo).

## Installazione sul tuo iPhone

Serve un **Mac con Xcode 15+** (non si può compilare un'app iOS senza). Un ID Apple gratuito basta, ma l'app
installata così scade dopo 7 giorni (si reinstalla da Xcode); con l'Apple Developer Program (99 €/anno) dura un anno.

**Opzione A – XcodeGen**
1. `brew install xcodegen`, poi nella cartella del progetto `xcodegen generate` e apri `XiaomiRemote.xcodeproj`.
2. In `project.yml` cambia `bundleIdPrefix` / `PRODUCT_BUNDLE_IDENTIFIER` con un identificatore tuo.

**Opzione B – a mano**
1. Xcode › File › New › Project › iOS App (SwiftUI, Swift), nome `XiaomiRemote`, deployment target **iOS 16.0**.
2. Elimina `ContentView.swift` e il file `@main` generato; trascina dentro la cartella `Sources` (gruppi + target).
3. Target › Info: aggiungi `NSLocalNetworkUsageDescription` (testo a piacere) e `NSBonjourServices` = array con `_androidtvremote2._tcp`.
4. (Facoltativo) aggiungi un target *Unit Testing Bundle* e trascina `Tests`.

**Firma e installazione**
1. Target › Signing & Capabilities › scegli il tuo *Team* (accedi con l'ID Apple in Xcode › Settings › Accounts).
2. Sull'iPhone: Impostazioni › Privacy e sicurezza › **Modalità sviluppatore** (poi riavvio).
3. Collega l'iPhone con il cavo, selezionalo come destinazione e premi ▶︎. Alla prima installazione:
   Impostazioni › Generali › VPN e gestione dispositivo › **Autorizza** il tuo profilo.
4. Dopo la prima volta puoi usare «Connect via network» (Window › Devices and Simulators) per non usare il cavo.

## Primo utilizzo
1. Accendi la TV, iPhone sullo stesso Wi-Fi. Consenti l'accesso alla **Rete locale** quando iOS lo chiede.
2. Scegli la TV (o inserisci l'IP: Impostazioni TV › Rete). Sulla TV compare un codice a 6 caratteri: scrivilo nell'app.
3. L'app si collega e salva la TV. Se la TV è spenta o la rete cade, riprova da sola con attesa crescente.

## Novità v1.2

**Tasti Menu/SET e INPUT.** Dalle prove sulla tua TV (Mi TV MSSP3, Android 9) risulta che i tasti HDMI diretti
funzionano ma **MENU, SET e INPUT inviati via rete vengono scartati dalla TV**: non dipende dall'app e non si può
correggere con un altro codice. Li ho sostituiti con azioni che passano:
- **Menu** ora apre per impostazione predefinita l'app *Impostazioni* della TV (`market://launch?id=com.android.tv.settings`,
  lo stesso meccanismo con cui l'integrazione Android TV Remote di Home Assistant avvia le app). Se la TV avvia l'app,
  da lì si raggiungono immagine, audio, rete e ingressi. Tenendo premuto «Menu» trovi le alternative (e il vecchio tasto SET).
- **Ingressi** mostra tre grandi pulsanti HDMI (i link di ingresso che già funzionano); il selettore INPUT e gli altri
  metodi sono nelle «Opzioni avanzate».
- In **App** puoi aggiungere anche il *nome di un pacchetto* (es. `com.netflix.ninja`) oltre ai link.

**Schermo intero.** Il layout ora si adatta all'altezza: il D-pad occupa lo spazio disponibile e tasti, righe e
volume crescono in proporzione (su iPhone Pro Max riempie lo schermo, su schermi piccoli si compatta). Se l'app
risultasse ancora in «mezzo schermo», controlla che nel target ci sia la *Launch Screen* (con XcodeGen c'è già:
`UILaunchScreen` in `project.yml`).

**Icona.** Telecomando in vetro con D-pad e onde di segnale, in versione chiara, scura e monocromatica
(`Sources/Resources/Assets.xcassets`, rigenerabile con `python3 Tools/make_icon.py`). Con la configurazione manuale
(opzione B) trascina `Assets.xcassets` nel progetto e imposta *App Icon Source* = `AppIcon`.

**Video.** Nuovo pannello **Video**: stop/play/pausa, riavvolgi e avanti (tenendo premuto si ripete), salto, fotogrammi,
sottotitoli, traccia audio, info, formato, canali e guida; funzionano solo se la TV o l'app li gestiscono.
**Riconoscimento:** la TV comunica l'**app in uso** (es. «YouTube», mostrata anche sotto il nome della TV); il
**titolo del video non è disponibile** con questo protocollo (servirebbe ADB), quindi non viene mostrato.

## Novità v1.1

**Liquid Glass.** Con **Xcode 26 e iOS 26** i tasti, il D-pad, il volume e i pannelli usano il vero Liquid Glass
(`glassEffect`, `GlassEffectContainer`) su uno sfondo a macchie di colore. Con SDK o iOS precedenti l'app si compila
e usa un materiale sfumato equivalente (nessuna modifica necessaria).

**Menu / SET.** Il tasto «SET» del tuo telecomando può inviare codici diversi a seconda di TV e app, e l'app non può sapere
quale. Tocca **Impostazioni › Tasto Menu (SET)** (oppure tieni premuto «Menu» nella schermata principale): apri un'app
sulla TV, tocca **Prova** su ogni voce (Menu, Impostazioni/SET, pressione manuale, tenuto premuto, OK lungo, Info…) e,
quando compare il menu giusto, tocca **Usa**. La scelta viene ricordata.

**Ingressi.** Il tasto INPUT inviato via rete è ignorato da molte TV (limite noto del protocollo). Per questo i pulsanti
HDMI usano un *link di ingresso* `content://android.media.tv/passthrough/…` che le segnalazioni di altri utenti indicano
funzionante su Xiaomi/Amlogic. Le Mi TV 4A con Android 9 usano il chip **Amlogic**: è il metodo preselezionato. Se
«HDMI 1» non cambia ingresso, scegli un altro metodo nella stessa schermata (MediaTek A/B o tasti diretti).
Il selettore INPUT resta disponibile in due varianti (tocco normale e pressione manuale).
Puoi anche aggiungere un tuo link in **App › Le tue scorciatoie**.

## Come sono mappati i controlli
Frecce/OK/Indietro/Home/Menu/Recenti/Impostazioni TV/Volume ±/Muto/Play-Pausa/Avanti/Indietro veloce = codici tasto Android
(`KEYCODE_*`) inviati con `RemoteKeyInject`. **Menu** è configurabile (vedi sopra; di base `KEYCODE_MENU`). **Ingressi**: link di ingresso per HDMI 1-3, selettore
(`KEYCODE_TV_INPUT`) + frecce/OK, e in alternativa i tasti `KEYCODE_TV_INPUT_HDMI_*` (spesso ignorati). **Tastiera**: invia i tasti lettera/cifra/punteggiatura (maiuscole e accenti semplificati, emoji no).
**Touchpad**: gesti → frecce e OK (non esiste un puntatore). **App**: invia un link alla TV (`RemoteAppLinkLaunchRequest`).

## Cosa è verificato e cosa no
- ✅ Porte, schemi dei messaggi, codici tasto e formula del segreto: confrontati con la documentazione/le librerie di riferimento.
- ✅ Byte dei messaggi principali calcolati a mano e usati nei test (`ProtocolTests`).
- ❌ Compilazione, esecuzione dei test e prova su una Xiaomi reale: **non fatte**.
- ⚠️ Punti più a rischio al primo test: creazione dell'identità TLS nel Keychain (`CertificateManager`), valore `featureFlags = 622`
  nell'handshake, permesso Rete locale.
- ⚠️ I link di ingresso passano dal comando «apri link»: funzionano su altre Xiaomi/Amlogic secondo le segnalazioni, ma non sono provati sulla tua TV.
- ⚠️ Dipendono da modello/app: Menu, ingressi, Recenti, comandi multimediali, link delle app (YouTube/Netflix/Prime/Disney+ da verificare),
  stato acceso/standby e volume (arrivano solo se la TV li invia).
- ❌ Non disponibili: tasti MENU/SET/INPUT via rete su questa TV, accensione da TV spenta, elenco ingressi/app installate, titolo del video in riproduzione, controllo di soundbar.
- La digitazione usa i tasti Android perché lo schema `RemoteImeBatchEdit` delle fonti consultate era incoerente tra versioni.

## Sicurezza e privacy
Solo rete locale. Salvati sul dispositivo: elenco TV e preferenze (UserDefaults), identità TLS dell'app e impronta SHA-256 del certificato
della TV (Keychain, solo questo dispositivo, nessun backup). Il certificato della TV è «bloccato» alla prima connessione: se cambia
(TV ripristinata) l'app lo segnala e chiede di ripetere l'associazione. Nessun PIN viene salvato.

## Architettura (`Sources/`)
`Core/` protocollo (`Protobuf`, `Messages`, `TLSChannel`, `PairingSession`, `RemoteSession`, `Certificates`, `Errors` = ErrorHandler) ·
`Services/` (`TVDiscoveryService`, `TVConnectionManager`, `RemoteCommandService`, `KeyboardInputService`, `DeviceStorage`, `PairingFlow`) ·
`UI/` (SwiftUI, Liquid Glass) · `App/` · `Resources/` (icona) · `Tools/make_icon.py`. Una sola sessione alla volta; i comandi con la TV offline vengono scartati (mai accodati) per non rieseguirli in ritardo.
**Modalità test** (Impostazioni): i comandi non vengono inviati, solo registrati.

## Test (`Tests/`, ⌘U)
Codifica/decodifica protocollo, segreto di pairing, flusso di pairing con TV simulata (ordine messaggi, rifiuto, codice errato,
timeout), riconnessione, TV non disponibile, permesso di rete negato, ordine dei comandi, TV offline, modalità test, tastiera.
