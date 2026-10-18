import SwiftUI
import UIKit

/// Grafite con accenti blu/viola; si adatta a modalità chiara e scura.
enum Theme {
    private static func adaptive(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let bgTop = adaptive(dark: UIColor(red: 0.075, green: 0.078, blue: 0.098, alpha: 1),
                                light: UIColor(red: 0.945, green: 0.949, blue: 0.965, alpha: 1))
    static let bgBottom = adaptive(dark: UIColor(red: 0.035, green: 0.036, blue: 0.047, alpha: 1),
                                   light: UIColor(red: 0.890, green: 0.894, blue: 0.925, alpha: 1))
    static let key = adaptive(dark: UIColor(white: 1, alpha: 0.08), light: UIColor(white: 0, alpha: 0.055))
    static let stroke = adaptive(dark: UIColor(white: 1, alpha: 0.10), light: UIColor(white: 0, alpha: 0.08))
    static let accent = Color(red: 0.36, green: 0.43, blue: 1.0)
    static let accent2 = Color(red: 0.62, green: 0.39, blue: 1.0)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var background: some View {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    static func tap(_ enabled: Bool) {
        guard enabled else { return }
        light.impactOccurred()
    }
}
