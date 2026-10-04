import SwiftUI

struct TakeEditor: View {
    let roll: Roll
    let repository: CameraLogRepository
    let existingTake: TakeEntry?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TakeDraft
    @State private var filterText: String
    @State private var showTechnical = false
    @State private var error: String?

    init(roll: Roll, repository: CameraLogRepository, draft: TakeDraft,
         existingTake: TakeEntry? = nil, onSave: @escaping () -> Void) {
        self.roll = roll; self.repository = repository
        self.existingTake = existingTake; self.onSave = onSave
        _draft = State(initialValue: draft)
        _filterText = State(initialValue: draft.settings.filters.joined(separator: " + "))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(roll.name, systemImage: "sdcard")
                        Spacer()
                        Text("DAY \(roll.report?.day?.number ?? 0) · CAM \(roll.report?.camera?.name ?? "—")")
                    }
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    HStack(spacing: 8) {
                        cell("SCÈNE") {
                            TextField("24A", text: $draft.scene)
                                .textInputAutocapitalization(.characters)
                        }
                        cell("PLAN") {
                            TextField("03", text: $draft.shot)
                                .textInputAutocapitalization(.characters)
                        }
                        cell("PRISE") {
                            TextField("1", value: $draft.number, format: .number)
                                .keyboardType(.numberPad)
                        }
                    }

                    HStack(spacing: 8) {
                        cell("OBJECTIF") {
                            TextField("50 mm", text: $draft.settings.lensName)
                        }
                        cell("DIAPH") {
                            TextField("T-stop", value: $draft.settings.tStop, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    }

                    cell("FILTRES") {
                        TextField("ND 0.6 + 1/8 BPM", text: $filterText)
                    }

                    HStack(spacing: 8) {
                        cell("ISO / EI") {
                            TextField("800", value: $draft.settings.iso, format: .number)
                                .keyboardType(.numberPad)
                        }
                        cell("TEMPÉRATURE · K") {
                            TextField("5600", value: $draft.settings.whiteBalance, format: .number)
                                .keyboardType(.numberPad)
                        }
                    }

                    HStack(spacing: 8) {
                        cell("FPS") {
                            TextField("24", value: $draft.settings.fps, format: .number)
                                .keyboardType(.decimalPad)
                        }
                        cell("SHUTTER · °") {
                            TextField("180", value: $draft.settings.shutterAngle, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    }

                    Button {
                        let enabled = !draft.statuses.contains(.circle)
                        draft.statuses.removeAll { $0 == .circle }
                        if enabled { draft.statuses.append(.circle) }
                    } label: {
                        Label(draft.statuses.contains(.circle) ? "PRISE CERCLÉE" : "CIRCLE",
                            systemImage: draft.statuses.contains(.circle) ? "checkmark.circle.fill" : "circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .tint(draft.statuses.contains(.circle) ? .orange : .secondary)

                    cell("COMMENTAIRE") {
                        TextField("Note de plateau", text: $draft.notes, axis: .vertical)
                            .lineLimit(2...5)
                    }

                    DisclosureGroup("Autres détails", isExpanded: $showTechnical) {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                cell("TC IN") { TextField("00:00:00:00", text: $draft.tcIn) }
                                cell("TC OUT") { TextField("00:00:00:00", text: $draft.tcOut) }
                            }
                            cell("CLIP") { TextField("Nom du clip", text: $draft.clipName) }
                            cell("CODEC") { TextField("Codec", text: $draft.settings.codec) }
                            HStack(spacing: 8) {
                                cell("RÉSOLUTION") { TextField("Résolution", text: $draft.settings.resolution) }
                                cell("FORMAT") { TextField("Format", text: $draft.settings.recordingFormat) }
                            }
                            HStack(spacing: 8) {
                                cell("RATIO") { TextField("Ratio", text: $draft.settings.aspectRatio) }
                                cell("LUT") { TextField("LUT", text: $draft.settings.lut) }
                            }
                            ForEach(TakeStatus.allCases.filter { $0 != .circle }) { status in
                                Toggle(status.rawValue, isOn: statusBinding(status))
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: draft.scene) { _, _ in if existingTake == nil { draft.number = 1 } }
            .onChange(of: draft.shot) { _, _ in if existingTake == nil { draft.number = 1 } }
            .navigationTitle(existingTake == nil ? "Nouvelle prise" : "Modifier la prise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Label(existingTake == nil ? "ENREGISTRER T\(draft.number)" : "ENREGISTRER LES MODIFICATIONS",
                          systemImage: "checkmark")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal).padding(.vertical, 8)
                .background(.bar)
            }
            .logError($error)
        }
    }

    private func cell<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.bold()).foregroundStyle(.orange)
            content()
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
        do {
            if let existingTake { try repository.updateTake(existingTake, draft: draft) }
            else { try repository.addTake(to: roll, draft: draft) }
            onSave(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
