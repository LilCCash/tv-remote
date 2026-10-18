import SwiftUI

/// Liquid Glass su iOS 26 (con Xcode 26); su versioni precedenti un materiale sfumato con bordo sottile.
/// Così l'app resta compilabile e bella anche con SDK o iOS più vecchi.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(makeGlass(), in: shape)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(shape.fill(tint.map { $0.opacity(0.6) } ?? Color.clear))
            .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
    #endif
}

extension View {
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }
}

/// Raggruppa elementi in vetro vicini: con Liquid Glass li fa fondere e reagire insieme.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}
