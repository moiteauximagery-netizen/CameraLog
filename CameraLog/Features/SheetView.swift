import SwiftUI
import UIKit

private struct PendingMove: Identifiable {
    let id = UUID()
    let changes: [ClipChange]
}

/// The single working screen of a shot: identification, settings, takes and circle mode.
struct SheetView: View {
    let report: CameraReport
    let repository: CameraLogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: ShotSheet?
    @State private var draft = SheetDraft()
    @State private var saved = SheetDraft()
    @State private var loaded = false
    @State private var circleMode = false
    @State private var editingTake: TakeEntry?
    @State private var inserting = false
    @State private var pendingMove: PendingMove?
    @State private var error: String?
    @State private var feedback = 0
    @FocusState private var focus: SheetField?

    init(report: CameraReport, repository: CameraLogRepository, sheet: ShotSheet?) {
        self.report = report
        self.repository = repository
        _sheet = State(initialValue: sheet)
    }

    private var isDirty: Bool { draft.savedContent != saved.savedContent }
    private var nextNumber: Int { sheet.map { repository.nextTakeNumber(in: $0) } ?? 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                statusHeader
                row([.scene, .shot, .roll])
                if !draft.pendingFields.isEmpty { suggestionBar }
                row([.lens, .tStop])
                cell(.filters)
                row([.iso, .whiteBalance])
                row([.fps, .shutter])
                takesSection
                notesCell
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(sheet == nil ? "Nouvelle fiche" : "\(saved.value(.scene)) / \(saved.value(.shot))")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDirty)
        .toolbar {
            if isDirty {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: cancel) }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focus = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isDirty {
                Button { save() } label: {
                    Label(sheet == nil ? "ENREGISTRER LA FICHE" : "ENREGISTRER LES MODIFICATIONS",
                          systemImage: "checkmark")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("save-sheet")
                .padding(.horizontal).padding(.vertical, 8)
                .background(.bar)
            }
        }
        .onAppear(perform: load)
        .sheet(item: $editingTake) { take in
            TakeDetailView(take: take, repository: repository) { feedback += 1 }
        }
        .sheet(isPresented: $inserting) {
            if let sheet {
                InsertTakeView(sheet: sheet, repository: repository) { feedback += 1 }
            }
        }
        .confirmationDialog("Changer de roll ?", isPresented: Binding(
            get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }
        ), titleVisibility: .visible, presenting: pendingMove) { _ in
            Button("Déplacer et renuméroter") {
                pendingMove = nil
                save(confirmedMove: true)
            }
            Button("Annuler", role: .cancel) { pendingMove = nil }
        } message: { move in
            Text("Les prises de cette fiche changent de carte :\n" + ClipSequence.summary(move.changes))
        }
        .sensoryFeedback(.success, trigger: feedback)
        .logError($error)
    }

    // MARK: Identification and settings

    private var statusHeader: some View {
        HStack(spacing: 6) {
            Text("DAY \(report.day?.number ?? 0) · CAM \(report.camera?.name ?? "—")")
            Spacer()
            Label(stateText, systemImage: isDirty ? "pencil.circle.fill" : "checkmark.circle")
                .foregroundStyle(isDirty ? Color.orange : Color.secondary)
                .accessibilityIdentifier("sheet-state")
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }

    private var stateText: String {
        switch (sheet == nil, isDirty) {
        case (true, false): return "Rien d’enregistré"
        case (true, true): return "Non enregistrée"
        case (false, true): return "Modifications non enregistrées"
        case (false, false): return "Fiche enregistrée"
        }
    }

    private func row(_ fields: [SheetField]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(fields) { field in cell(field) }
        }
    }

    private func cell(_ field: SheetField) -> some View {
        let suggestion = draft.suggestion(field) ?? ""
        let pending = draft.isPending(field)
        return VStack(alignment: .leading, spacing: 4) {
            Text(field.title)
                .font(.caption2.bold()).foregroundStyle(.orange)
                .lineLimit(1).minimumScaleFactor(0.7)
            TextField(field.spokenName, text: $draft[field],
                      prompt: Text(pending ? suggestion : "—").italic())
                .font(.title3.weight(.semibold)).monospacedDigit()
                .keyboardType(field.keyboard)
                .textInputAutocapitalization(field.capitalization)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .accessibilityIdentifier("field-\(field.rawValue)")
                .accessibilityHint(pending ? "Suggestion non enregistrée : \(suggestion)." : "")
            if pending {
                Button { draft.accept(field) } label: {
                    Label("Reprendre", systemImage: "arrow.down.left")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .accessibilityLabel("Reprendre \(suggestion) pour \(field.spokenName)")
                .accessibilityIdentifier("accept-\(field.rawValue)")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(pending ? Color.gray : Color.clear, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    private var suggestionBar: some View {
        let count = draft.pendingFields.count
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 valeur proposée, non enregistrée" : "\(count) valeurs proposées, non enregistrées")
                    .font(.subheadline.bold())
                Text("En gris : reprises de \(draft.suggestionSource). Reprenez-les ou tapez une autre valeur.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Tout reprendre") { draft.acceptAll() }
                .buttonStyle(.bordered).tint(.orange)
                .frame(minHeight: 44)
                .accessibilityIdentifier("accept-all")
        }
        .padding(10)
        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var notesCell: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("COMMENTAIRE").font(.caption2.bold()).foregroundStyle(.orange)
            TextField("Note de plateau", text: $draft.notes, axis: .vertical)
                .lineLimit(2...5)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Takes

    private var takesSection: some View {
        let takes = sheet?.orderedTakes ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("TAKES").font(.headline).foregroundStyle(.orange)
                Spacer()
                circleButton
                addButton
            }
            cardCounter
            if circleMode {
                Label("CERCLAGE ACTIF — toucher une prise la cercle ou la décercle", systemImage: "hand.tap.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.black)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
            }
            if takes.isEmpty {
                Text(sheet == nil
                     ? "Renseignez scène, plan et roll puis touchez + : la fiche est enregistrée et T01 créée."
                     : "Aucune prise. Touchez + pour créer \(TakeLabel.code(nextNumber)).")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                takeGrid(takes)
            }
            if isDirty && sheet != nil {
                Text("+ enregistre aussi les modifications de la fiche ; les prises existantes gardent leurs réglages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if sheet != nil && !circleMode {
                Button { inserting = true } label: {
                    Label("Insérer une prise oubliée…", systemImage: "text.insert")
                        .font(.subheadline).frame(minHeight: 36)
                }
                .accessibilityIdentifier("insert-take")
            }
        }
        .padding(12)
        .background(circleMode ? Color.orange.opacity(0.15) : Color.gray.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(circleMode ? Color.orange : Color.gray.opacity(0.3), lineWidth: circleMode ? 3 : 1)
        }
    }

    @ViewBuilder private var cardCounter: some View {
        if let roll = sheet?.roll {
            let count = roll.clipCount
            HStack(spacing: 6) {
                Image(systemName: "sdcard")
                Text("Carte \(roll.name)")
                Spacer()
                Text(count == 0 ? "aucun clip" : "\(count) clip\(count > 1 ? "s" : "") · dernier \(ClipCode.code(count))")
                    .monospacedDigit()
            }
            .font(.subheadline.bold())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("card-counter")
        }
    }

    private func takeGrid(_ takes: [TakeEntry]) -> some View {
        let numbers = sheet?.roll?.clipNumbers ?? [:]
        let rows = stride(from: 0, to: takes.count, by: 4).map { Array(takes[$0..<min($0 + 4, takes.count)]) }
        return VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    ForEach(rows[index]) { take in
                        TakeChip(take: take, clip: numbers[take.id], circleMode: circleMode) { tap(take) }
                    }
                    ForEach(0..<(4 - rows[index].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                    }
                }
            }
        }
    }

    @ViewBuilder private var circleButton: some View {
        let button = Button(action: toggleCircleMode) {
            Label("Cerclage", systemImage: circleMode ? "checkmark.circle.fill" : "circle.dashed")
                .font(.subheadline.bold())
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Mode cerclage")
        .accessibilityValue(circleMode ? "activé" : "désactivé")
        .accessibilityHint(circleMode ? "Touchez pour revenir au mode édition."
                           : "Touchez pour que chaque prise touchée soit cerclée ou décerclée.")
        .accessibilityIdentifier("circle-mode")
        if circleMode {
            button.buttonStyle(.borderedProminent).tint(.orange)
        } else {
            button.buttonStyle(.bordered).tint(.gray)
        }
    }

    private var addButton: some View {
        Button(action: addTake) {
            Label(TakeLabel.code(nextNumber), systemImage: "plus")
                .font(.headline).monospacedDigit()
                .frame(minWidth: 64, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Ajouter la prise \(nextNumber)")
        .accessibilityIdentifier("add-take")
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        let initial = sheet.map { repository.draft(for: $0, in: report) } ?? repository.newSheetDraft(for: report)
        draft = initial
        saved = initial
    }

    private func cancel() {
        focus = nil
        if sheet == nil { dismiss(); return }
        draft.values = saved.values
        draft.notes = saved.notes
    }

    @discardableResult private func save(confirmedMove: Bool = false) -> Bool {
        if let sheet, !confirmedMove {
            let changes = repository.previewRollChange(for: sheet, to: draft.value(.roll), in: report)
            if !changes.isEmpty { pendingMove = PendingMove(changes: changes); return false }
        }
        do {
            let result = try repository.saveSheet(draft, sheet: sheet, in: report)
            let suggestions = draft.suggestions
            let source = draft.suggestionSource
            var reloaded = repository.draft(for: result, in: report)
            reloaded.suggestions = suggestions
            reloaded.suggestionSource = source
            sheet = result
            draft = reloaded
            saved = reloaded
            feedback += 1
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func addTake() {
        focus = nil
        if sheet == nil || isDirty {
            guard save() else { return }
        }
        guard let sheet else { return }
        do {
            let take = try repository.addNextTake(to: sheet)
            feedback += 1
            let clip = take.roll?.clipNumbers[take.id].map(ClipCode.code) ?? ""
            announce("Prise \(take.number) ajoutée, clip \(clip)")
        } catch { self.error = error.localizedDescription }
    }

    private func toggleCircleMode() {
        circleMode.toggle()
        announce(circleMode
            ? "Mode cerclage activé. Toucher une prise la cercle ou la décercle."
            : "Mode cerclage désactivé. Toucher une prise ouvre son édition.")
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    private func tap(_ take: TakeEntry) {
        do {
            switch try repository.tap(take, mode: circleMode ? .circle : .edit) {
            case .edit: editingTake = take
            case .toggleCircle: feedback += 1
            }
        } catch { self.error = error.localizedDescription }
    }
}

private struct TakeChip: View {
    let take: TakeEntry
    let clip: Int?
    let circleMode: Bool
    let action: () -> Void

    private var spokenLabel: String {
        let code = clip.map(ClipCode.code) ?? "inconnu"
        let label = take.labelText
        return label.isEmpty ? "Prise \(take.number), clip \(code)" : "Prise \(take.number), clip \(code), libellé \(label)"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(TakeLabel.code(take.number)).font(.headline).monospacedDigit()
                Text(clip.map(ClipCode.code) ?? "—").font(.caption2.monospaced())
                Text(take.labelText.isEmpty ? " " : take.labelText)
                    .font(.caption2.bold()).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(take.isCircle ? Color.black : Color.primary)
            .background(take.isCircle ? Color.orange : Color.gray.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if take.isCircle {
                    Image(systemName: "checkmark.circle.fill").font(.caption).padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(circleMode ? Color.orange : Color.clear,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(take.isCircle ? "cerclée" : "non cerclée")
        .accessibilityHint(circleMode ? "Mode cerclage : touchez pour cercler ou décercler."
                           : "Touchez pour modifier le libellé et les informations.")
        .accessibilityIdentifier("take-\(take.number)")
    }
}

private extension SheetField {
    var keyboard: UIKeyboardType {
        switch self {
        case .iso, .whiteBalance: return .numberPad
        case .fps, .shutter: return .decimalPad
        default: return .default
        }
    }

    var capitalization: TextInputAutocapitalization {
        switch self {
        case .scene, .shot, .roll: return .characters
        default: return .never
        }
    }
}
