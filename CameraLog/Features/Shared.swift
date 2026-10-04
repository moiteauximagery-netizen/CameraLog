import SwiftUI

struct ErrorNotice: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("Action non enregistrée", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
}

extension View {
    func logError(_ message: Binding<String?>) -> some View { modifier(ErrorNotice(message: message)) }
}

struct SaveToolbar: ToolbarContent {
    let save: () -> Void
    let cancel: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: cancel) }
        ToolbarItem(placement: .confirmationAction) { Button("Enregistrer", action: save).bold() }
    }
}

extension Color {
    /// Identification color of a camera; gray when none is set.
    static func camera(_ hue: Double?) -> Color {
        guard let hue else { return .gray }
        return Color(hue: hue, saturation: 0.72, brightness: 0.95)
    }
}

/// « A » on the camera color, used wherever a camera is named.
struct CameraBadge: View {
    let name: String
    let hue: Double?
    var size: CGFloat = 30
    var body: some View {
        Text(name)
            .font(.system(size: size * 0.5, weight: .heavy)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(Color.black)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, name.count > 1 ? 6 : 0)
            .background(Color.camera(hue), in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityLabel("Caméra \(name)")
    }
}
