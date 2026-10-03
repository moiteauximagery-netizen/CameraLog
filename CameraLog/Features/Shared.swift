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
