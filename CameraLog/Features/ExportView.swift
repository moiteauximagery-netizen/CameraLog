import SwiftUI

/// Builds the report files of a day (all cameras or one) and hands them to the iOS share sheet.
struct ExportView: View {
    let day: ShootDay
    let repository: CameraLogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var cameraID: UUID?
    @State private var pdf = true
    @State private var csv = true
    @State private var json = false
    @State private var files: [URL] = []
    @State private var takeCount = 0
    @State private var error: String?

    init(day: ShootDay, repository: CameraLogRepository, camera: Camera? = nil) {
        self.day = day
        self.repository = repository
        _cameraID = State(initialValue: camera?.id)
    }

    private var cameras: [Camera] { ReportExport.reports(of: day).compactMap(\.camera) }
    private var camera: Camera? { cameras.first { $0.id == cameraID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Caméra") {
                    Picker("Caméra", selection: $cameraID) {
                        Text("Toutes").tag(UUID?.none)
                        ForEach(cameras) { camera in Text("CAM \(camera.name)").tag(Optional(camera.id)) }
                    }
                }
                Section {
                    Toggle("PDF — rapport à lire ou imprimer", isOn: $pdf)
                    Toggle("CSV — Silverstack, tableur", isOn: $csv)
                    Toggle("JSON — format ZoeLog", isOn: $json)
                } header: {
                    Text("Formats")
                } footer: {
                    Text("Le CSV et le JSON reprennent les colonnes de ZoeLog lues par Silverstack. Dans Silverstack, apparier par Camera et Clip : le numéro de clip est celui calculé par carte.")
                }
                Section {
                    Text("DAY \(day.number) · \(takeCount) prise(s)")
                        .font(.subheadline).monospacedDigit()
                    if files.isEmpty {
                        Text(takeCount == 0 ? "Aucune prise à exporter." : "Choisir au moins un format.")
                            .foregroundStyle(.secondary)
                    } else {
                        ShareLink(items: files) {
                            Label("Partager \(files.count) fichier(s)", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("share-export")
                        ForEach(files, id: \.self) { url in
                            Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Exporter le rapport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
            }
            .onAppear(perform: prepare)
            .onChange(of: cameraID) { _, _ in prepare() }
            .onChange(of: pdf) { _, _ in prepare() }
            .onChange(of: csv) { _, _ in prepare() }
            .onChange(of: json) { _, _ in prepare() }
            .logError($error)
        }
    }

    /// Writes the chosen files in a fresh temporary folder; nothing is kept once shared.
    private func prepare() {
        let production = day.production
        let reports = ReportExport.reports(of: day, camera: camera)
        takeCount = ReportExport.rows(day: day, reports: reports).count
        guard takeCount > 0 else { files = []; return }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = ReportExport.baseName(production: production, day: day, camera: camera)
            var urls: [URL] = []
            if pdf {
                let url = folder.appendingPathComponent(name + ".pdf")
                try ReportPDF.make(production: production, day: day, reports: reports).write(to: url)
                urls.append(url)
            }
            if csv {
                let url = folder.appendingPathComponent(name + ".csv")
                try Data(ReportExport.csv(day: day, reports: reports).utf8).write(to: url)
                urls.append(url)
            }
            if json {
                let url = folder.appendingPathComponent(name + ".json")
                try ReportExport.json(production: production, day: day, reports: reports).write(to: url)
                urls.append(url)
            }
            files = urls
        } catch {
            files = []
            self.error = error.localizedDescription
        }
    }
}
