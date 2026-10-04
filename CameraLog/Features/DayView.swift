import SwiftUI

struct DayView: View {
    let day: ShootDay
    let repository: CameraLogRepository
    @State private var editingDay = false
    @State private var exporting = false
    @State private var editingCamera: Camera?
    @State private var pendingDeletion: CameraReport?
    @State private var error: String?

    private var reports: [CameraReport] {
        day.reports.filter { $0.day?.id == day.id }
            .sorted { ($0.camera?.name ?? "") < ($1.camera?.name ?? "") }
    }

    var body: some View {
        let _ = repository.revision
        List {
            Section {
                Text(day.date, style: .date).font(.headline)
                let details = [day.location, day.unit].filter { !$0.isEmpty }.joined(separator: " · ")
                if !details.isEmpty { Text(details).accessibilityIdentifier("day-details") }
                if !day.notes.isEmpty { Text(day.notes).foregroundStyle(.secondary) }
            }
            Section("Caméras") {
                ForEach(reports) { report in
                    NavigationLink {
                        ReportView(report: report, repository: repository)
                    } label: {
                        HStack(spacing: 12) {
                            CameraBadge(name: report.camera?.name ?? "—", hue: report.camera?.colorHue, size: 40)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("CAM \(report.camera?.name ?? "—")").font(.title2.bold())
                                Text([report.camera?.model ?? "", (report.camera?.nativeISO).map { "ISO \($0)" } ?? ""]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(report.rolls.flatMap(\.currentSheets).count) fiches · \(report.rolls.flatMap(\.takes).count) prises")
                                    .foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("camera-\(report.camera?.name ?? "")")
                    .swipeActions {
                        Button("Supprimer", role: .destructive) { pendingDeletion = report }
                        if let camera = report.camera {
                            Button("Modifier") { editingCamera = camera }
                                .tint(.gray)
                                .accessibilityIdentifier("edit-camera-\(camera.name)")
                        }
                    }
                }
                Button {
                    do { try repository.addNextCamera(to: day) }
                    catch { self.error = error.localizedDescription }
                } label: {
                    Label("Ajouter la caméra \(CameraNaming.next(used: reports.compactMap { $0.camera?.name }))",
                          systemImage: "plus")
                }
                .frame(minHeight: 48)
                .accessibilityIdentifier("add-camera")
            }
        }
        .navigationTitle("DAY \(day.number)")
        .toolbar {
            Button("Exporter", systemImage: "square.and.arrow.up") { exporting = true }
                .accessibilityIdentifier("export-day")
            Button("Modifier", systemImage: "pencil") { editingDay = true }
                .accessibilityIdentifier("edit-day")
        }
        .sheet(isPresented: $exporting) { ExportView(day: day, repository: repository) }
        .sheet(isPresented: $editingDay) {
            if let production = day.production {
                DayEditor(production: production, day: day, repository: repository)
            }
        }
        .sheet(item: $editingCamera) { camera in CameraEditor(camera: camera, repository: repository) }
        .confirmationDialog("Supprimer cette caméra pour la journée ?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible, presenting: pendingDeletion) { report in
            Button("Supprimer ses rolls et prises du jour", role: .destructive) {
                do { try repository.deleteReport(report) }
                catch { self.error = error.localizedDescription }
                pendingDeletion = nil
            }
        } message: { report in
            Text("CAM \(report.camera?.name ?? "") : \(report.rolls.flatMap(\.takes).count) prise(s) de cette journée seront supprimées. La caméra reste dans la production.")
        }
        .logError($error)
    }
}

/// Name and body details of a production camera.
struct CameraEditor: View {
    let camera: Camera
    let repository: CameraLogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var manufacturer: String
    @State private var model: String
    @State private var serial: String
    @State private var hue: Double?
    @State private var nativeISO: String
    @State private var error: String?
    init(camera: Camera, repository: CameraLogRepository) {
        self.camera = camera; self.repository = repository
        _name = State(initialValue: camera.name)
        _manufacturer = State(initialValue: camera.manufacturer)
        _model = State(initialValue: camera.model)
        _serial = State(initialValue: camera.serialNumber)
        _hue = State(initialValue: camera.colorHue)
        _nativeISO = State(initialValue: camera.nativeISO ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CameraBadge(name: name.isEmpty ? "?" : name, hue: hue, size: 44)
                        TextField("Nom : A, B, Drone…", text: $name)
                            .textInputAutocapitalization(.characters)
                            .font(.title2.bold())
                    }
                }
                Section("Couleur") {
                    HStack(spacing: 10) {
                        ForEach(CameraColor.palette, id: \.self) { value in
                            colorButton(value, label: "Couleur \(CameraColor.palette.firstIndex(of: value).map { $0 + 1 } ?? 0)")
                        }
                        colorButton(nil, label: "Gris")
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    TextField("800, 1280…", text: $nativeISO)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("native-iso")
                } header: {
                    Text("ISO natif")
                } footer: {
                    Text("Proposé en gris dans la case ISO quand aucune fiche précédente n’en propose.")
                }
                Section("Boîtier") {
                    TextField("Fabricant", text: $manufacturer)
                    TextField("Modèle", text: $model)
                    TextField("Numéro de série", text: $serial)
                }
            }
            .navigationTitle("CAM \(camera.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(save: {
                do {
                    try repository.updateCamera(camera, name: name, manufacturer: manufacturer,
                                                model: model, serialNumber: serial, colorHue: .some(hue),
                                                nativeISO: nativeISO)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }, cancel: { dismiss() }) }
            .logError($error)
        }
    }

    private func colorButton(_ value: Double?, label: String) -> some View {
        let selected = hue == value
        return Button { hue = value } label: {
            Circle()
                .fill(Color.camera(value))
                .frame(width: 28, height: 28)
                .overlay { Circle().strokeBorder(Color.primary, lineWidth: selected ? 3 : 0) }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
