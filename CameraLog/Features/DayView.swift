import SwiftUI

struct DayView: View {
    let day: ShootDay
    let repository: CameraLogRepository
    @State private var addingCamera = false
    var body: some View {
        List {
            Section {
                Text(day.date, style: .date).font(.headline)
                Text([day.location, day.unit].filter { !$0.isEmpty }.joined(separator: " · "))
            }
            Section("Caméras") {
                ForEach(day.reports.sorted { ($0.camera?.name ?? "") < ($1.camera?.name ?? "") }) { report in
                    NavigationLink {
                        ReportView(report: report, repository: repository)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CAM \(report.camera?.name ?? "—")").font(.title2.bold())
                            Text("\(report.rolls.flatMap(\.currentSheets).count) fiches · \(report.rolls.flatMap(\.takes).count) prises")
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
                Button("Ajouter une caméra", systemImage: "plus") { addingCamera = true }
                    .frame(minHeight: 48)
            }
        }.navigationTitle("DAY \(day.number)")
        .sheet(isPresented: $addingCamera) { CameraEditor(day: day, repository: repository) }
    }
}

struct CameraEditor: View {
    let day: ShootDay
    let repository: CameraLogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var manufacturer = ""
    @State private var model = ""
    @State private var serial = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let production = day.production {
                    Section("Caméras de la production") {
                        ForEach(production.cameras.filter { camera in
                            !day.reports.contains { $0.camera?.id == camera.id }
                        }) { camera in
                            Button("Utiliser \(camera.name) · \(camera.model)") {
                                do { try repository.addReport(to: day, camera: camera); dismiss() }
                                catch { self.error = error.localizedDescription }
                            }.frame(minHeight: 48)
                        }
                    }
                }
                Section("Nouvelle caméra") {
                    TextField("Nom : A, B, Drone…", text: $name)
                    TextField("Fabricant", text: $manufacturer)
                    TextField("Modèle", text: $model)
                    TextField("Numéro de série", text: $serial)
                }
            }.navigationTitle("Caméra")
            .toolbar { SaveToolbar(save: {
                guard let production = day.production else { return }
                do {
                    let camera = try repository.addCamera(to: production, name: name,
                        manufacturer: manufacturer, model: model, serialNumber: serial)
                    try repository.addReport(to: day, camera: camera)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }, cancel: { dismiss() }) }
            .logError($error)
        }
    }
}
