import SwiftUI

/// Normal-mode tap on a take: label, statuses and notes. The clip number is shown, never edited.
struct TakeDetailView: View {
    let take: TakeEntry
    let repository: CameraLogRepository
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var notes: String
    @State private var statuses: [String]
    @State private var confirmingDeletion = false
    @State private var error: String?

    init(take: TakeEntry, repository: CameraLogRepository, onSave: @escaping () -> Void) {
        self.take = take; self.repository = repository; self.onSave = onSave
        _label = State(initialValue: take.labelText)
        _notes = State(initialValue: take.notes)
        _statuses = State(initialValue: take.statusValues)
    }

    private var clipCode: String {
        take.roll?.clipNumbers[take.id].map(ClipCode.code) ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Prise", value: TakeLabel.code(take.number))
                    LabeledContent("Clip calculé", value: "\(take.roll?.name ?? "—") · \(clipCode)")
                    LabeledContent("Circle", value: take.isCircle ? "Cerclée" : "Non cerclée")
                } footer: {
                    Text("Le numéro de clip découle de l’ordre des prises sur la carte ; il ne se saisit pas. Circle se change avec le mode Cerclage de la fiche.")
                }

                Section {
                    TextField("Libellé, par exemple PU", text: $label)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("take-label")
                    HStack(spacing: 8) {
                        ForEach(TakeLabel.quick, id: \.self) { value in
                            Button(value) { label = value }
                                .buttonStyle(.bordered)
                                .tint(label == value ? Color.orange : Color.gray)
                                .accessibilityIdentifier("label-\(value)")
                        }
                        Button("Aucun") { label = "" }
                            .buttonStyle(.bordered).tint(.gray)
                    }
                } header: {
                    Text("Libellé")
                } footer: {
                    Text("PU : pick-up. FC : clip créé sur la caméra mais inexploitable ; il garde sa place dans la séquence des clips. Le numéro de prise ne change pas.")
                }

                Section("Statuts") {
                    ForEach(TakeStatus.allCases.filter { $0 != .circle }) { status in
                        Toggle(status.rawValue, isOn: binding(status))
                    }
                }

                Section("Commentaire") {
                    TextField("Note sur cette prise", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    let snapshot = take.snapshot
                    let fields = SheetField.settings.filter { !(snapshot[$0.rawValue] ?? "").isEmpty }
                    if fields.isEmpty {
                        Text("Aucun réglage renseigné à la création de la prise.").foregroundStyle(.secondary)
                    } else {
                        ForEach(fields) { field in
                            LabeledContent(field.spokenName, value: snapshot[field.rawValue] ?? "")
                        }
                    }
                } header: {
                    Text("Réglages au moment de la prise")
                } footer: {
                    Text("Instantané enregistré avec la prise : modifier la fiche ensuite ne le change pas.")
                }

                if !take.clipName.isEmpty {
                    Section("Saisi avant la mise à jour") {
                        LabeledContent("Nom de clip", value: take.clipName)
                    }
                }

                Section {
                    Button("Supprimer cette prise", role: .destructive) { confirmingDeletion = true }
                }
            }
            .navigationTitle(TakeLabel.title(number: take.number, label: take.labelText))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(save: save, cancel: { dismiss() }) }
            .confirmationDialog("Supprimer cette prise ?", isPresented: $confirmingDeletion,
                                titleVisibility: .visible) {
                Button("Supprimer", role: .destructive, action: delete)
            } message: {
                Text(deletionMessage)
            }
            .logError($error)
        }
    }

    private var deletionMessage: String {
        let changes = repository.previewDeletion(of: take)
        let impact = changes.isEmpty ? "Aucun autre numéro de clip ne change."
            : "Clips renumérotés :\n" + ClipSequence.summary(changes)
        return impact + "\n\nSi ce clip existe sur la caméra, préférez le libellé FC."
    }

    private func binding(_ status: TakeStatus) -> Binding<Bool> {
        Binding(get: { statuses.contains(status.rawValue) }, set: { enabled in
            statuses.removeAll { $0 == status.rawValue }
            if enabled { statuses.append(status.rawValue) }
        })
    }

    private func save() {
        do {
            try repository.updateTake(take, label: label, statuses: statuses, notes: notes)
            onSave(); dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() {
        do { try repository.deleteTake(take); onSave(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

/// Adds a forgotten take at its real place on the card, after showing every renumbered clip.
struct InsertTakeView: View {
    let sheet: ShotSheet
    let repository: CameraLogRepository
    let onInsert: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var position: Int?
    @State private var number: Int
    @State private var error: String?

    init(sheet: ShotSheet, repository: CameraLogRepository, onInsert: @escaping () -> Void) {
        self.sheet = sheet; self.repository = repository; self.onInsert = onInsert
        _number = State(initialValue: (sheet.takes.map(\.number).max() ?? 0) + 1)
    }

    var body: some View {
        let sequence = sheet.roll?.clipSequence ?? []
        NavigationStack {
            List {
                Section {
                    Stepper(value: $number, in: 1...999) {
                        Text("Prise \(TakeLabel.code(number))").monospacedDigit()
                    }
                } footer: {
                    Text("Fiche \(sheet.title). La prise oubliée prend le numéro de clip de la position choisie.")
                }

                Section("Position sur la carte \(sheet.roll?.name ?? "")") {
                    ForEach(Array(1...(sequence.count + 1)), id: \.self) { slot in
                        Button { position = slot } label: {
                            HStack(spacing: 10) {
                                Image(systemName: position == slot ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(.orange)
                                Text(slot <= sequence.count
                                     ? "Avant \(ClipCode.code(slot)) · \(sequence[slot - 1].displayTitle)"
                                     : "Après le dernier clip · \(ClipCode.code(slot))")
                                    .monospacedDigit()
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(position == slot ? .isSelected : [])
                    }
                }

                if let position, let roll = sheet.roll {
                    let shifts = repository.previewInsertion(on: roll, at: position)
                    Section("À vérifier avant de confirmer") {
                        Text("\(sheet.title) · \(TakeLabel.code(number)) devient \(ClipCode.code(position))").bold()
                        if shifts.isEmpty {
                            Text("Aucun autre clip ne change de numéro.")
                        } else {
                            ForEach(shifts) { change in Text(change.line).monospacedDigit() }
                        }
                    }
                }
            }
            .navigationTitle("Prise oubliée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insérer", action: insert).bold().disabled(position == nil)
                }
            }
            .logError($error)
        }
    }

    private func insert() {
        guard let position else { return }
        do {
            try repository.insertTake(into: sheet, at: position, number: number)
            onInsert(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
