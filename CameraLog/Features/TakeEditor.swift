import SwiftUI

struct TakeEditor: View {
    let roll: Roll
    let repository: CameraLogRepository
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TakeDraft
    @State private var filterText: String
    @State private var showTechnical = false
    @State private var error: String?
    init(roll: Roll, repository: CameraLogRepository, draft: TakeDraft, onSave: @escaping () -> Void) {
        self.roll = roll; self.repository = repository; self.onSave = onSave
        _draft = State(initialValue: draft)
        _filterText = State(initialValue: draft.settings.filters.joined(separator: " + "))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("\(roll.name) · Identification") {
                    TextField("Scène", text: $draft.scene).textInputAutocapitalization(.characters)
                    TextField("Plan", text: $draft.shot).textInputAutocapitalization(.characters)
                        .onChange(of: draft.shot) { _, _ in draft.number = 1 }
                    Stepper("PRISE \(String(format: "%02d", draft.number))", value: $draft.number, in: 1...99999)
                        .font(.title2.bold()).frame(minHeight: 48)
                }
                Section("Optique · réglages mémorisés") {
                    TextField("Objectif, par exemple 50 mm", text: $draft.settings.lensName)
                    TextField("Filtres séparés par +", text: $filterText)
                    TextField("T-stop", value: $draft.settings.tStop, format: .number).keyboardType(.decimalPad)
                }
                Section {
                    Toggle("CIRCLE", isOn: statusBinding(.circle)).font(.headline).frame(minHeight: 48)
                    TextField("Commentaire", text: $draft.notes, axis: .vertical)
                    DisclosureGroup("Autres statuts") {
                        ForEach(TakeStatus.allCases.filter { $0 != .circle }) { status in
                            Toggle(status.rawValue, isOn: statusBinding(status))
                        }
                    }
                }
                Section {
                    DisclosureGroup("Paramètres caméra", isExpanded: $showTechnical) {
                        LabeledContent("ISO") {
                            TextField("ISO", value: $draft.settings.iso, format: .number).keyboardType(.numberPad)
                        }
                        LabeledContent("WB · K") {
                            TextField("Kelvin", value: $draft.settings.whiteBalance, format: .number).keyboardType(.numberPad)
                        }
                        LabeledContent("FPS") {
                            TextField("FPS", value: $draft.settings.fps, format: .number).keyboardType(.decimalPad)
                        }
                        LabeledContent("Shutter · °") {
                            TextField("Angle", value: $draft.settings.shutterAngle, format: .number).keyboardType(.decimalPad)
                        }
                        TextField("Codec", text: $draft.settings.codec)
                        TextField("Résolution", text: $draft.settings.resolution)
                        TextField("Format", text: $draft.settings.recordingFormat)
                        TextField("Ratio", text: $draft.settings.aspectRatio)
                        TextField("LUT", text: $draft.settings.lut)
                    }
                }
            }
            .onChange(of: draft.scene) { _, _ in draft.number = 1 }
            .navigationTitle("Nouvelle prise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Label("ENREGISTRER T\(String(format: "%02d", draft.number))", systemImage: "checkmark")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }.buttonStyle(.borderedProminent).padding().background(.bar)
            }
            .logError($error)
        }
    }
    private func statusBinding(_ status: TakeStatus) -> Binding<Bool> {
        Binding(get: { draft.statuses.contains(status) }, set: { enabled in
            draft.statuses.removeAll { $0 == status }
            if enabled { draft.statuses.append(status) }
        })
    }
    private func save() {
        draft.settings.filters = filterText.split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do { try repository.addTake(to: roll, draft: draft); onSave(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
