import SwiftUI

struct KeyStyle: ButtonStyle {
    var corner: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.key, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct KeyButton: View {
    let icon: String
    let title: String
    var tint: Color? = nil
    var height: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(tint ?? .primary)
            .frame(maxWidth: .infinity, minHeight: height)
        }
        .buttonStyle(KeyStyle())
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
            .scaleEffect(pressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: pressed)
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

/// Pad direzionale circolare: l'elemento visivo principale del telecomando.
struct DPad: View {
    let size: CGFloat
    let press: (RemoteKey) -> Void

    var body: some View {
        let hit = size * 0.30
        let reach = size * 0.335
        ZStack {
            Circle()
                .fill(Theme.key)
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            arrow("chevron.up", "Su", .up, hit, 0, -reach)
            arrow("chevron.down", "Giù", .down, hit, 0, reach)
            arrow("chevron.left", "Sinistra", .left, hit, -reach, 0)
            arrow("chevron.right", "Destra", .right, hit, reach, 0)
            Button { press(.center) } label: {
                Text("OK")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(Theme.accentGradient, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 6)
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
                .font(.system(size: 26, weight: .semibold))
                .frame(width: hit, height: hit)
        }
        .offset(x: dx, y: dy)
        .accessibilityLabel(label)
    }
}
