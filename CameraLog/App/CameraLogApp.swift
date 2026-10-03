import SwiftUI
import SwiftData

@main struct CameraLogApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    init() {
        do { container = try CameraLogStore.makeContainer(); startupError = nil }
        catch { container = nil; startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                ProductionListView(repository: CameraLogRepository(context: container.mainContext))
                    .modelContainer(container)
                    .preferredColorScheme(.dark)
                    .tint(.orange)
            } else {
                ContentUnavailableView {
                    Label("Stockage indisponible", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Impossible d’ouvrir les rapports. Aucune donnée n’a été effacée. Ferme puis relance l’app.\n\n\(startupError ?? "")")
                }
            }
        }
    }
}
