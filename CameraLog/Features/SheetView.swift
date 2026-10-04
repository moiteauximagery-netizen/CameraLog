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
    @State private var takeToDelete: TakeEntry?
    @State private var inserting = false
    @State private var pendingMove: PendingMove?
    @State private var error: String?
    @State private var feedback = 0
    @State private var picker: SheetField?
    @State private var apertureFraction = ""
    @State private var labelTakeID: UUID?
    @State private var labelDraft = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var saveIssue: String?
    @State private var takePendingDeletion: TakeEntry?
    @FocusState private var focus: SheetField?
    @FocusState private var labelFocused: Bool

    init(report: CameraReport, repository: CameraLogRepository, sheet: ShotSheet?) {
        self.report = report
        self.repository = repository
        _sheet = State(initialValue: sheet)
    }

    private var isDirty: Bool { draft.savedContent != saved.savedContent }
    private var lensSeries: [LensSeries] { report.day?.production?.lensSeries ?? [] }
    private var filterKit: [FilterFamily] { report.day?.production?.filterKit ?? FilterFamily.defaultKit }
    private var catalog: ProjectCatalog { report.day?.production?.catalog ?? ProjectCatalog() }
    private var vfxShown: Bool { !catalog.isHidden(ProjectCatalog.vfxBlock) }
    /// Entry screens take the camera color; the rest of the app stays orange.
    private var accent: Color { Color.cameraAccent(report.camera?.colorHue) }
    private var nextNumber: Int { sheet.map { repository.nextTakeNumber(in: $0) } ?? 1 }
    private var rollPrefix: String? { RollNaming.prefix(forCamera: report.camera?.name) }
    private var isComplete: Bool { SheetField.identification.allSatisfy { !draft.value($0).isEmpty } }
    /// Leaving would lose typed values that cannot be saved yet.
    private var leavingLosesChanges: Bool { isDirty && (!isComplete || saveIssue != nil) }
    private var rollSuffix: Binding<String> {
        Binding(get: { RollNaming.suffix(of: draft[.roll], prefix: rollPrefix) },
                set: { draft[.roll] = RollNaming.compose(prefix: rollPrefix, suffix: $0) })
    }

    var body: some View {
        let _ = repository.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                statusHeader
                row([.scene, .shot, .roll, .magazine])
                if !draft.pendingFields.isEmpty { suggestionBar }
                row([.lens, .tStop])
                row([.filters])
                row([.iso, .whiteBalance])
                row([.fps, .shutter])
                row([.lut, .aspectRatio])
                row([.format, .resolution])
                takesSection
                notesCell
                if vfxShown { vfxSection }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(sheet == nil ? "Nouvelle fiche" : "\(saved.value(.scene)) / \(saved.value(.shot))")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(leavingLosesChanges)
        .toolbar {
            if leavingLosesChanges {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sheet == nil ? "Abandonner" : "Rétablir", action: cancel)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                if labelTakeID != nil {
                    ForEach(TakeLabel.quick, id: \.self) { value in
                        Button(value) { quickLabelForEditedTake(value) }
                            .bold()
                            .accessibilityIdentifier("quick-\(value)")
                    }
                    Button("Effacer") { quickLabelForEditedTake("") }
                    Spacer()
                    Button("Détails") { openDetails() }
                    Button("OK") { commitLabel(labelDraft) }
                        .bold()
                        .accessibilityIdentifier("label-ok")
                } else {
                    Spacer()
                    Button("OK") { focus = nil }
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear {
            if labelTakeID != nil { commitLabel(labelDraft) }
            saveTask?.cancel()
            focus = nil
            autosave()
        }
        .onChange(of: draft.savedContent) { _, _ in scheduleAutosave() }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            // A take box opens with the cursor after the text: typing « PU » on « 1 » gives « 1PU ».
            guard labelTakeID != nil, focus == nil, let field = note.object as? UITextField else { return }
            DispatchQueue.main.async {
                let end = field.endOfDocument
                field.selectedTextRange = field.textRange(from: end, to: end)
            }
        }
        .onChange(of: focus) { old, new in
            // Scene, plan and roll are saved when their box is left, never mid-typing.
            if let old, SheetField.identification.contains(old), old != new { autosave() }
        }
        .sheet(item: $editingTake, onDismiss: deletePendingTake) { take in
            TakeDetailView(take: take, repository: repository,
                           onSave: { feedback += 1 }, onDelete: { takeToDelete = take })
                .environment(\.sheetAccent, accent)
                .tint(accent)
        }
        .sheet(isPresented: $inserting) {
            if let sheet {
                InsertTakeView(sheet: sheet, repository: repository) { feedback += 1 }
                    .tint(accent)
            }
        }
        .confirmationDialog("Changer de roll ?", isPresented: Binding(
            get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }
        ), titleVisibility: .visible, presenting: pendingMove) { _ in
            Button("Déplacer et renuméroter") {
                pendingMove = nil
                save(confirmedMove: true)
            }
            Button("Annuler", role: .cancel) {
                pendingMove = nil
                draft[.roll] = saved[.roll]
            }
        } message: { move in
            Text("Les prises de cette fiche changent de carte :\n" + ClipSequence.summary(move.changes))
        }
        .confirmationDialog("Supprimer cette prise ?", isPresented: Binding(
            get: { takePendingDeletion != nil }, set: { if !$0 { takePendingDeletion = nil } }
        ), titleVisibility: .visible, presenting: takePendingDeletion) { take in
            Button("Supprimer la prise", role: .destructive) {
                takePendingDeletion = nil
                do { try repository.deleteTake(take); feedback += 1 }
                catch { self.error = error.localizedDescription }
            }
        } message: { take in
            Text(deletionMessage(take))
        }
        .sensoryFeedback(.success, trigger: feedback)
        .environment(\.sheetAccent, accent)
        .tint(accent)
        .logError($error)
    }

    // MARK: Identification and settings

    private var statusHeader: some View {
        HStack(spacing: 6) {
            CameraBadge(name: report.camera?.name ?? "—", hue: report.camera?.colorHue, size: 22)
            Text("DAY \(report.day?.number ?? 0)")
            Spacer()
            Label(stateText, systemImage: saveIssue != nil ? "exclamationmark.circle.fill"
                  : (isDirty ? "pencil.circle.fill" : "checkmark.circle"))
                .foregroundStyle(saveIssue != nil || isDirty ? accent : Color.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("sheet-state")
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }

    private var stateText: String {
        if let saveIssue { return "Non enregistré : \(saveIssue)" }
        switch (sheet == nil, isDirty) {
        case (true, false): return "Rien d’enregistré"
        case (true, true): return isComplete ? "Enregistrement…" : "Scène, plan et roll requis"
        case (false, true): return "Enregistrement…"
        case (false, false): return "Fiche enregistrée"
        }
    }

    /// Boxes of a row, without those hidden in the production settings.
    @ViewBuilder private func row(_ fields: [SheetField]) -> some View {
        let shown = fields.filter { !draft.hiddenFields.contains($0) }
        if !shown.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                ForEach(shown) { field in cell(field) }
            }
        }
    }

    private var vfxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $draft.vfx) {
                Label("VFX", systemImage: "cube.transparent")
                    .font(.headline)
            }
            .tint(accent)
            .frame(minHeight: 44)
            .accessibilityHint("Affiche hauteur caméra, point et tilt. Les nouvelles prises sont marquées VFX.")
            .accessibilityIdentifier("vfx-toggle")
            if draft.vfx {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(SheetField.vfx) { field in cell(field) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(draft.vfx ? accent.opacity(0.12) : Color.gray.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func cell(_ field: SheetField) -> some View {
        let suggestion = draft.suggestion(field) ?? ""
        let pending = draft.isPending(field)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(field.title)
                    .font(.caption2.bold()).foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if hasPicker(field) { pickerButton(field) }
            }
            HStack(spacing: 1) {
                if field == .roll, let rollPrefix {
                    Text(rollPrefix).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                TextField(field.spokenName, text: field == .roll && rollPrefix != nil ? rollSuffix : $draft[field],
                          prompt: Text(pending ? displayed(suggestion, for: field) : "—").italic())
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .keyboardType(field.keyboard)
                    .textInputAutocapitalization(field.capitalization)
                    .autocorrectionDisabled()
                    .focused($focus, equals: field)
                    .accessibilityIdentifier("field-\(field.rawValue)")
                    .accessibilityHint(pending ? "Suggestion non enregistrée : \(suggestion)." : "")
            }
            if pending {
                Button { draft.accept(field) } label: {
                    Label("Reprendre", systemImage: "arrow.down.left")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
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
                .buttonStyle(.bordered).tint(accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("accept-all")
        }
        .padding(10)
        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var notesCell: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("COMMENTAIRE").font(.caption2.bold()).foregroundStyle(accent)
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
                Text("TAKES").font(.headline).foregroundStyle(accent)
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
                    .background(accent, in: RoundedRectangle(cornerRadius: 10))
            }
            if takes.isEmpty {
                Text(sheet == nil
                     ? "Renseignez scène, plan et roll puis touchez + : la fiche est enregistrée et la prise 1 créée."
                     : "Aucune prise. Touchez + pour créer la prise \(nextNumber).")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                takeGrid(takes)
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
        .background(circleMode ? accent.opacity(0.15) : Color.gray.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(circleMode ? accent : Color.gray.opacity(0.3), lineWidth: circleMode ? 3 : 1)
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
                        if take.id == labelTakeID {
                            labelBox(take, clip: numbers[take.id])
                        } else {
                            TakeChip(take: take, clip: numbers[take.id], circleMode: circleMode) { tap(take) }
                                .contextMenu {
                                    ForEach(TakeLabel.quick, id: \.self) { value in
                                        Button(value) { quickLabel(take, value) }
                                    }
                                    Button("Effacer le libellé", systemImage: "eraser") { quickLabel(take, "") }
                                    Button("Détails…", systemImage: "info.circle") { editingTake = take }
                                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                                        takePendingDeletion = take
                                    }
                                }
                        }
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
            button.buttonStyle(.borderedProminent).tint(accent)
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
        saveTask?.cancel()
        saveIssue = nil
        if sheet == nil { dismiss(); return }
        draft.values = saved.values
        draft.notes = saved.notes
    }

    private func displayed(_ suggestion: String, for field: SheetField) -> String {
        field == .roll ? RollNaming.suffix(of: suggestion, prefix: rollPrefix) : suggestion
    }

    // MARK: Automatic saving

    private func scheduleAutosave() {
        guard loaded else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            autosave()
        }
    }

    /// Saves typed and accepted values without a button. Never while scene, plan or roll is being typed.
    private func autosave() {
        guard loaded, isDirty, pendingMove == nil else {
            if !isDirty { saveIssue = nil }
            return
        }
        if let focus, SheetField.identification.contains(focus) { return }
        guard isComplete else {
            saveIssue = sheet == nil ? nil : "scène, plan et roll sont obligatoires"
            return
        }
        save(interactive: false)
    }

    @discardableResult private func save(confirmedMove: Bool = false, interactive: Bool = true) -> Bool {
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
            saveIssue = nil
            return true
        } catch {
            if interactive { self.error = error.localizedDescription }
            else { saveIssue = error.localizedDescription }
            return false
        }
    }

    private func addTake() {
        if labelTakeID != nil { commitLabel(labelDraft) }
        focus = nil
        saveTask?.cancel()
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

    private func deletePendingTake() {
        guard let take = takeToDelete else { return }
        takeToDelete = nil
        do { try repository.deleteTake(take); feedback += 1 }
        catch { self.error = error.localizedDescription }
    }

    private func toggleCircleMode() {
        if labelTakeID != nil { commitLabel(labelDraft) }
        circleMode.toggle()
        announce(circleMode
            ? "Mode cerclage activé. Toucher une prise la cercle ou la décercle."
            : "Mode cerclage désactivé. Toucher une prise ouvre son édition.")
    }

    // MARK: Inline take label

    private func startLabelEdit(_ take: TakeEntry) {
        if labelTakeID != nil { commitLabel(labelDraft) }
        focus = nil
        labelTakeID = take.id
        labelDraft = TakeLabel.title(number: take.number, label: take.labelText)
            .replacingOccurrences(of: "—", with: "")
        DispatchQueue.main.async { labelFocused = true }
    }

    /// Saves the box content as typed: « 4PU », « FC » (no take number), « 12 ».
    private func commitLabel(_ text: String) {
        guard let id = labelTakeID else { return }
        labelTakeID = nil
        labelFocused = false
        guard let take = sheet?.takes.first(where: { $0.id == id }) else { return }
        do {
            try repository.renameTake(take, typed: text)
            feedback += 1
        } catch { self.error = error.localizedDescription }
    }

    /// Keyboard and long-press shortcuts: PU keeps the number, FC removes it, empty clears the label.
    private func quickLabel(_ take: TakeEntry, _ value: String) {
        if labelTakeID == take.id { labelTakeID = nil; labelFocused = false }
        do { try repository.applyQuickLabel(take, value); feedback += 1 }
        catch { self.error = error.localizedDescription }
    }

    private func quickLabelForEditedTake(_ value: String) {
        guard let id = labelTakeID, let take = sheet?.takes.first(where: { $0.id == id }) else { return }
        quickLabel(take, value)
    }

    private func deletionMessage(_ take: TakeEntry) -> String {
        let changes = repository.previewDeletion(of: take)
        let impact = changes.isEmpty ? "Aucun autre numéro de clip ne change."
            : "Clips renumérotés :\n" + ClipSequence.summary(changes)
        return impact + "\n\nSi ce clip existe sur la caméra, préférez le libellé FC."
    }

    private func openDetails() {
        guard let id = labelTakeID, let take = sheet?.takes.first(where: { $0.id == id }) else { return }
        commitLabel(labelDraft)
        editingTake = take
    }

    private func labelBox(_ take: TakeEntry, clip: Int?) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 1) {
                TextField("", text: $labelDraft)
                    .font(.headline)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($labelFocused)
                    .submitLabel(.done)
                    .onSubmit { commitLabel(labelDraft) }
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Texte de la case, numéro de prise et libellé")
                    .accessibilityIdentifier("take-label-field")
            }
            .padding(.horizontal, 8)
            Text(clip.map(ClipCode.code) ?? "—").font(.caption2.monospaced())
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(accent.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(accent, lineWidth: 2) }
    }

    // MARK: Quick pickers on the lens, T-stop and filter boxes

    private func hasPicker(_ field: SheetField) -> Bool {
        switch field {
        case .lens: return !lensSeries.isEmpty
        case .tStop: return true
        case .filters: return !filterKit.isEmpty
        case .lut, .aspectRatio, .format, .resolution: return !catalog.list(field).isEmpty
        default: return false
        }
    }

    private func pickerButton(_ field: SheetField) -> some View {
        Button {
            focus = nil
            if field == .tStop { apertureFraction = Aperture.parse(draft.value(.tStop))?.fraction ?? "" }
            picker = field
        } label: {
            Image(systemName: "chevron.down.circle.fill")
                .font(.title3)
                .frame(minWidth: 36, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .accessibilityLabel("Choisir \(field.spokenName) dans la liste")
        .accessibilityIdentifier("picker-\(field.rawValue)")
        .popover(isPresented: Binding(get: { picker == field }, set: { if !$0 { picker = nil } })) {
            pickerContent(field)
                .environment(\.sheetAccent, accent)
                .tint(accent)
                .padding(12)
                .frame(width: 330)
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder private func pickerContent(_ field: SheetField) -> some View {
        switch field {
        case .lens:
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lensSeries) { series in
                        VStack(alignment: .leading, spacing: 4) {
                            if !series.name.isEmpty {
                                Text(series.name).font(.caption.bold()).foregroundStyle(accent)
                            }
                            ValueGrid(values: series.focals, columns: 4, idPrefix: series.name.isEmpty ? "lens" : series.name,
                                      selected: { draft.value(.lens) == LensSeries.value(series: series.name, focal: $0) }) { focal in
                                draft[.lens] = LensSeries.value(series: series.name, focal: focal)
                                picker = nil
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
        case .tStop:
            let current = Aperture.parse(draft.value(.tStop))
            VStack(alignment: .leading, spacing: 10) {
                Text("1. Fraction").font(.caption.bold()).foregroundStyle(accent)
                ValueGrid(values: Aperture.fractions.map(Aperture.label), columns: 4, idPrefix: "fraction",
                          selected: { $0 == Aperture.label(apertureFraction) }) { label in
                    apertureFraction = Aperture.fraction(forLabel: label)
                }
                Text("2. Diaph").font(.caption.bold()).foregroundStyle(accent)
                ValueGrid(values: Aperture.fullStops, columns: 5, idPrefix: "stop",
                          selected: { $0 == current?.stop }) { stop in
                    draft[.tStop] = Aperture.value(stop: stop, fraction: apertureFraction)
                    apertureFraction = ""
                    picker = nil
                }
            }
        case .filters:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(draft.value(.filters).isEmpty ? "Aucun filtre" : draft.value(.filters))
                        .font(.subheadline.bold())
                        .lineLimit(2)
                    Spacer()
                    Button("Aucun") { draft[.filters] = "" }
                        .buttonStyle(.bordered)
                    Button("OK") { picker = nil }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("filters-done")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(filterKit) { family in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(family.name).font(.caption.bold()).foregroundStyle(accent)
                                ValueGrid(values: family.grades.isEmpty ? [family.name] : family.grades, columns: 4,
                                          idPrefix: family.name,
                                          selected: { FilterSelection.isSelected(family: family.name,
                                                      grade: family.grades.isEmpty ? "" : $0, in: draft.value(.filters)) }) { grade in
                                    draft[.filters] = FilterSelection.apply(family: family.name,
                                        grade: family.grades.isEmpty ? "" : grade, to: draft.value(.filters))
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        case .lut, .aspectRatio, .format, .resolution:
            ScrollView {
                ValueGrid(values: catalog.list(field), columns: field == .aspectRatio ? 3 : 2,
                          selected: { $0 == draft.value(field) }) { value in
                    draft[field] = value
                    picker = nil
                }
            }
            .frame(maxHeight: 360)
        default:
            EmptyView()
        }
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    private func tap(_ take: TakeEntry) {
        do {
            switch try repository.tap(take, mode: circleMode ? .circle : .edit) {
            case .edit: startLabelEdit(take)
            case .toggleCircle: feedback += 1
            }
        } catch { self.error = error.localizedDescription }
    }
}

private struct TakeChip: View {
    @Environment(\.sheetAccent) private var accent
    let take: TakeEntry
    let clip: Int?
    let circleMode: Bool
    let action: () -> Void

    private var spokenLabel: String {
        let code = clip.map(ClipCode.code) ?? "inconnu"
        let label = take.labelText
        let name = take.number > 0 ? "Prise \(take.number)" : "Sans numéro de prise"
        return label.isEmpty ? "\(name), clip \(code)" : "\(name), clip \(code), libellé \(label)"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(TakeLabel.title(number: take.number, label: take.labelText))
                    .font(.headline).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(clip.map(ClipCode.code) ?? "—").font(.caption2.monospaced())
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(take.isCircle ? Color.black : Color.primary)
            .background(take.isCircle ? accent : Color.gray.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if take.isCircle {
                    Image(systemName: "checkmark.circle.fill").font(.caption).padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(circleMode ? accent : Color.clear,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(take.isCircle ? "cerclée" : "non cerclée")
        .accessibilityHint(circleMode ? "Mode cerclage : touchez pour cercler ou décercler."
                           : "Touchez pour réécrire la case. Appui long : PU, FC, détails, suppression.")
        .accessibilityIdentifier("take-\(clip.map(ClipCode.code) ?? take.id.uuidString)")
    }
}

private extension SheetField {
    var keyboard: UIKeyboardType {
        switch self {
        case .iso, .whiteBalance: return .numberPad
        case .fps, .shutter: return .decimalPad
        case .roll, .lensHeight, .focus, .tilt: return .numbersAndPunctuation
        default: return .default
        }
    }

    var capitalization: TextInputAutocapitalization {
        switch self {
        case .scene, .shot, .roll, .magazine: return .characters
        default: return .never
        }
    }
}

/// Buttons laid out in rows, one tap per value. Used by the lens, T-stop and filter pickers.
private struct ValueGrid: View {
    @Environment(\.sheetAccent) private var accent
    let values: [String]
    let columns: Int
    var idPrefix = "value"
    let selected: (String) -> Bool
    let choose: (String) -> Void

    var body: some View {
        let rows = stride(from: 0, to: values.count, by: columns).map {
            Array(values[$0..<min($0 + columns, values.count)])
        }
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    ForEach(rows[index], id: \.self) { value in
                        let isOn = selected(value)
                        Button { choose(value) } label: {
                            Text(value)
                                .font(.body.weight(.semibold)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(isOn ? Color.black : Color.primary)
                                .background(isOn ? accent : Color.gray.opacity(0.2),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                        .accessibilityIdentifier("\(idPrefix)-\(value)")
                    }
                    ForEach(0..<(columns - rows[index].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                    }
                }
            }
        }
    }
}
