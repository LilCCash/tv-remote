import SwiftUI

/// Tasto in vetro: reagisce al tocco con una leggera molla.
struct KeyStyle: ButtonStyle {
    var corner: CGFloat = 22
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassSurface(RoundedRectangle(cornerRadius: corner, style: .continuous), tint: tint, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

struct KeyButton: View {
    let icon: String
    let title: String
    var tint: Color? = nil
    var height: CGFloat = 58
    var scale: CGFloat = 1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5 * scale) {
                Image(systemName: icon).font(.system(size: 19 * scale, weight: .semibold))
                Text(title)
                    .font(.system(size: 11 * scale, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tint ?? .primary)
            .frame(maxWidth: .infinity, minHeight: height)
        }
        .buttonStyle(KeyStyle(corner: 22 * min(scale, 1.2)))
        .accessibilityLabel(title)
    }
}

/// Esegue l'azione subito, poi la ripete finché il dito resta premuto.
/// Un limite massimo di ripetizioni evita comandi "bloccati" se il sistema interrompe il gesto.
struct RepeatButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var task: Task<Void, Never>?
    @State private var pressed = false

    var body: some View {
        label()
            .opacity(pressed ? 0.55 : 1)
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in begin() }
                .onEnded { _ in end() })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .onDisappear { end() }
    }

    private func begin() {
        guard task == nil else { return }
        pressed = true
        action()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
            var repeats = 0
            while !Task.isCancelled, repeats < 80 {
                action()
                repeats += 1
                try? await Task.sleep(nanoseconds: 110_000_000)
            }
        }
    }

    private func end() {
        task?.cancel()
        task = nil
        pressed = false
    }
}

/// Pad direzionale: grande disco di vetro con il tasto OK in vetro colorato al centro.
struct DPad: View {
    let size: CGFloat
    let press: (RemoteKey) -> Void

    var body: some View {
        let hit = size * 0.30
        let reach = size * 0.335
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: size, height: size)
                .glassSurface(Circle())
            Circle()
                .strokeBorder(Theme.stroke, lineWidth: 1)
                .frame(width: size * 0.50, height: size * 0.50)
            arrow("chevron.up", "Su", .up, hit, 0, -reach)
            arrow("chevron.down", "Giù", .down, hit, 0, reach)
            arrow("chevron.left", "Sinistra", .left, hit, -reach, 0)
            arrow("chevron.right", "Destra", .right, hit, reach, 0)
            Button { press(.center) } label: {
                Text("OK")
                    .font(.system(size: size * 0.105, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .glassSurface(Circle(), tint: Theme.accent, interactive: true)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("OK, conferma")
        }
        .frame(width: size, height: size)
    }

    private func arrow(_ icon: String, _ label: String, _ key: RemoteKey,
                       _ hit: CGFloat, _ dx: CGFloat, _ dy: CGFloat) -> some View {
        RepeatButton(action: { press(key) }) {
            Image(systemName: icon)
                .font(.system(size: size * 0.10, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.88))
                .frame(width: hit, height: hit)
        }
        .offset(x: dx, y: dy)
        .accessibilityLabel(label)
    }
}
