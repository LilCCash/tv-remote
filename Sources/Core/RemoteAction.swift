import Foundation

/// Un'azione inviabile alla TV: un tasto (breve o tenuto premuto) oppure un link da aprire.
struct RemoteAction: Codable, Equatable, Identifiable, Hashable {
    enum Kind: String, Codable { case key, keyHold, link }

    let id: String
    let title: String
    let detail: String
    let kind: Kind
    let code: Int
    let holdMs: Int
    let link: String

    static func keyPress(_ id: String, _ title: String, _ detail: String, code: Int) -> RemoteAction {
        RemoteAction(id: id, title: title, detail: detail, kind: .key, code: code, holdMs: 0, link: "")
    }

    /// Tasto premuto, tenuto per `ms` millisecondi e rilasciato (START_LONG … END_LONG),
    /// come farebbe un dito su un telecomando fisico.
    static func keyHold(_ id: String, _ title: String, _ detail: String, code: Int, ms: Int) -> RemoteAction {
        RemoteAction(id: id, title: title, detail: detail, kind: .keyHold, code: code, holdMs: ms, link: "")
    }

    static func openLink(_ id: String, _ title: String, _ detail: String, url: String) -> RemoteAction {
        RemoteAction(id: id, title: title, detail: detail, kind: .link, code: 0, holdMs: 0, link: url)
    }
}

/// Un modo di cambiare ingresso: una serie di link (o tasti) per HDMI 1, 2 e 3.
struct InputMethod: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let hdmi: [RemoteAction]
}

enum ActionCatalog {
    // MARK: Tasto Menu / SET

    /// Candidati per il tasto Menu. Codici: KEYCODE_MENU 82, KEYCODE_SETTINGS 176, KEYCODE_DPAD_CENTER 23,
    /// KEYCODE_INFO 165, KEYCODE_TV_CONTENTS_MENU 256, KEYCODE_TV_MEDIA_CONTEXT_MENU 257.
    static let menuCandidates: [RemoteAction] = [
        .keyPress("menu.key", "Menu", "Il tasto Menu standard di Android.", code: 82),
        .keyPress("set.key", "Impostazioni (tasto SET)", "Il tasto Impostazioni di Android: su molti Xiaomi è il tasto «SET».", code: 176),
        .keyHold("menu.hold", "Menu, pressione manuale", "Premuto e rilasciato come un tasto fisico (più lungo di un tocco).", code: 82, ms: 150),
        .keyHold("set.hold", "Impostazioni, pressione manuale", "Come sopra, ma con il tasto Impostazioni.", code: 176, ms: 150),
        .keyHold("menu.long", "Menu tenuto premuto", "Pressione prolungata (circa 1 secondo) del tasto Menu.", code: 82, ms: 900),
        .keyHold("ok.long", "OK tenuto premuto", "Apre il menu contestuale in molte app.", code: 23, ms: 900),
        .keyPress("info.key", "Info", "Mostra le informazioni o le opzioni del contenuto.", code: 165),
        .keyPress("ctx.media", "Menu contestuale contenuti", "Tasto «menu contestuale» dei contenuti multimediali.", code: 257),
        .keyPress("contents.menu", "Menu contenuti", "Tasto «elenco titoli» (alcune app).", code: 256)
    ]

    static var menuDefault: RemoteAction { menuCandidates[0] }

    // MARK: Ingressi

    static let selectorActions: [RemoteAction] = [
        .keyPress("input.key", "Selettore ingressi (tasto INPUT)", "Equivale al tasto INPUT del telecomando.", code: 178),
        .keyHold("input.hold", "Selettore, pressione manuale", "Come sopra, premuto e rilasciato come un tasto fisico.", code: 178, ms: 150)
    ]

    static let liveTV = RemoteAction.keyPress("input.live", "TV in diretta", "Torna al canale in onda.", code: 170)

    static let defaultInputMethodID = "amlogic"

    /// I link `content://android.media.tv/passthrough/…` sono gli indirizzi degli ingressi nel framework TV di Android.
    /// L'ID dipende dal chip della TV: le Mi TV 4A (Android 9) usano Amlogic.
    static let inputMethods: [InputMethod] = [
        InputMethod(
            id: "amlogic",
            title: "Amlogic (Mi TV 4A e simili)",
            detail: "Consigliato per la tua TV.",
            hdmi: (1...3).map { n in
                .openLink("amlogic.hdmi\(n)", "HDMI \(n)", "Link di ingresso Amlogic.",
                          url: passthrough("com.droidlogic.tvinput%2F.services.Hdmi\(n)InputService", hw: n + 4))
            }),
        InputMethod(
            id: "mediatek-a",
            title: "MediaTek (variante A)",
            detail: "Per TV con chip MediaTek: HDMI su HW4-HW6.",
            hdmi: (1...3).map { n in
                .openLink("mtka.hdmi\(n)", "HDMI \(n)", "Link di ingresso MediaTek.",
                          url: passthrough("com.mediatek.tvinput%2F.hdmi.HDMIInputService", hw: n + 3))
            }),
        InputMethod(
            id: "mediatek-b",
            title: "MediaTek (variante B)",
            detail: "Per TV con chip MediaTek: HDMI su HW5-HW7.",
            hdmi: (1...3).map { n in
                .openLink("mtkb.hdmi\(n)", "HDMI \(n)", "Link di ingresso MediaTek.",
                          url: passthrough("com.mediatek.tvinput%2F.hdmi.HDMIInputService", hw: n + 4))
            }),
        InputMethod(
            id: "keys",
            title: "Tasti HDMI diretti",
            detail: "Spesso ignorati dalle TV quando arrivano dalla rete.",
            hdmi: [
                .keyPress("keys.hdmi1", "HDMI 1", "Tasto KEYCODE_TV_INPUT_HDMI_1.", code: 243),
                .keyPress("keys.hdmi2", "HDMI 2", "Tasto KEYCODE_TV_INPUT_HDMI_2.", code: 244),
                .keyPress("keys.hdmi3", "HDMI 3", "Tasto KEYCODE_TV_INPUT_HDMI_3.", code: 245)
            ])
    ]

    static func inputMethod(id: String) -> InputMethod {
        inputMethods.first { $0.id == id } ?? inputMethods[0]
    }

    private static func passthrough(_ component: String, hw: Int) -> String {
        "content://android.media.tv/passthrough/\(component)%2FHW\(hw)"
    }
}
