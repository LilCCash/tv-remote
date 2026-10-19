import SwiftUI
import UIKit

/// Grafite con accenti blu e viola; si adatta a modalità chiara e scura.
enum Theme {
    private static func adaptive(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let bgTop = adaptive(dark: UIColor(red: 0.070, green: 0.074, blue: 0.098, alpha: 1),
                                light: UIColor(red: 0.950, green: 0.953, blue: 0.972, alpha: 1))
    static let bgBottom = adaptive(dark: UIColor(red: 0.030, green: 0.031, blue: 0.044, alpha: 1),
                                   light: UIColor(red: 0.880, green: 0.886, blue: 0.925, alpha: 1))
    static let key = adaptive(dark: UIColor(white: 1, alpha: 0.08), light: UIColor(white: 0, alpha: 0.055))
    static let stroke = adaptive(dark: UIColor(white: 1, alpha: 0.12), light: UIColor(white: 0, alpha: 0.09))
    static let accent = Color(red: 0.36, green: 0.43, blue: 1.0)
    static let accent2 = Color(red: 0.62, green: 0.39, blue: 1.0)
    static let accent3 = Color(red: 0.10, green: 0.74, blue: 0.86)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Sfondo a macchie di colore sfocate: dà al vetro qualcosa da rifrangere.
/// È statico (nessuna animazione continua) per non pesare sulla batteria.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Circle().fill(Theme.accent)
                    .frame(width: w * 0.95)
                    .blur(radius: 70)
                    .opacity(dark ? 0.50 : 0.30)
                    .offset(x: -w * 0.38, y: -h * 0.16)
                Circle().fill(Theme.accent2)
                    .frame(width: w * 0.85)
                    .blur(radius: 75)
                    .opacity(dark ? 0.42 : 0.26)
                    .offset(x: w * 0.42, y: h * 0.34)
                Circle().fill(Theme.accent3)
                    .frame(width: w * 0.65)
                    .blur(radius: 80)
                    .opacity(dark ? 0.26 : 0.16)
                    .offset(x: -w * 0.12, y: h * 0.80)
            }
            .clipped()
        }
        .ignoresSafeArea()
    }
}

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)

    static func tap(_ enabled: Bool) {
        guard enabled else { return }
        light.impactOccurred()
    }

    static func confirm(_ enabled: Bool) {
        guard enabled else { return }
        medium.impactOccurred()
    }

    static func success(_ enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
