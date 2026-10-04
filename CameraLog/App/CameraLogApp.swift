import SwiftUI
import SwiftData

@main struct CameraLogApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    private let uiTesting: Bool
    init() {
        #if DEBUG
        // UI tests run on a throwaway in-memory store seeded with LES OMBRES.
        uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        uiTesting = false
        #endif
        do { container = try CameraLogStore.makeContainer(inMemory: uiTesting); startupError = nil }
        catch { container = nil; startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView(container: container, seedSample: uiTesting)
                        .modelContainer(container)
                } else {
                    StorageFailure(message: startupError ?? "")
                }
            }
            .preferredColorScheme(.dark)
            .tint(.orange)
        }
    }
}

/// Attaches takes from the previous version to sheets before showing any report.
private struct RootView: View {
    let container: ModelContainer
    let seedSample: Bool
    @State private var repository: CameraLogRepository?
    @State private var failure: String?

    var body: some View {
        Group {
            if let repository {
                ProductionListView(repository: repository)
            } else if let failure {
                StorageFailure(message: failure)
            } else {
                ProgressView("Ouverture des rapports…")
            }
        }
        .onAppear {
            guard repository == nil, failure == nil else { return }
            let candidate = CameraLogRepository(context: container.mainContext)
            do {
                try candidate.migrateLegacyTakes()
                if seedSample { try SampleData.load(into: candidate) }
                repository = candidate
            } catch {
                failure = "La mise à jour des prises existantes a échoué ; rien n’a été modifié.\n\n\(error.localizedDescription)"
            }
        }
    }
}

private struct StorageFailure: View {
    let message: String
    var body: some View {
        ContentUnavailableView {
            Label("Stockage indisponible", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Impossible d’ouvrir les rapports. Aucune donnée n’a été effacée. Ferme puis relance l’app.\n\n\(message)")
        }
    }
}
