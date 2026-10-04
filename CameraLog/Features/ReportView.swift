import SwiftUI

private enum ReportSearch: String, CaseIterable, Identifiable {
    case all = "Tout", scene = "Scène", roll = "Roll", lens = "Optique"
    var id: String { rawValue }
}

/// Sheets of one camera and day, grouped automatically by the roll typed in each sheet.
struct ReportView: View {
    let report: CameraReport
    let repository: CameraLogRepository
    /// The rolls page of a camera takes the camera color, like its sheets.
    private var accent: Color { Color.cameraAccent(report.camera?.colorHue) }
    @State private var query = ""
    @State private var searchScope: ReportSearch = .all
    @State private var error: String?
    @State private var pendingDeletion: ShotSheet?
    @State private var editingRoll: Roll?
    @State private var exporting = false

    private var rolls: [Roll] {
        report.orderedRolls.reversed().filter { !$0.currentSheets.isEmpty }
    }

    private func sheets(for roll: Roll) -> [ShotSheet] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return roll.currentSheets.filter { sheet in
            guard !term.isEmpty else { return true }
            let lens = SheetField.lens.rawValue
            let fields: [String]
            switch searchScope {
            case .all: fields = [sheet.scene, sheet.shot, sheet.scene + sheet.shot, roll.name, sheet.settings[lens] ?? ""]
            case .scene: fields = [sheet.scene, sheet.shot, sheet.scene + sheet.shot]
            case .roll: fields = [roll.name]
            case .lens: fields = [sheet.settings[lens] ?? ""] + sheet.takes.map { $0.snapshot[lens] ?? "" }
            }
            return fields.contains { $0.localizedStandardContains(term) }
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    var body: some View {
        let _ = repository.revision
        List {
            Picker("Rechercher par", selection: $searchScope) {
                ForEach(ReportSearch.allCases) { scope in Text(scope.rawValue).tag(scope) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            ForEach(rolls) { roll in rollSection(roll) }

            if rolls.isEmpty {
                ContentUnavailableView("Première fiche", systemImage: "square.and.pencil",
                    description: Text("Touchez « Nouvelle fiche ». Le roll saisi dans la fiche est créé automatiquement."))
            } else if !query.isEmpty && rolls.allSatisfy({ sheets(for: $0).isEmpty }) {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Scène, roll ou objectif")
        .navigationTitle("CAM \(report.camera?.name ?? "—") · DAY \(report.day?.number ?? 0)")
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                SheetView(report: report, repository: repository, sheet: nil)
            } label: {
                Label("Nouvelle fiche", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("new-sheet")
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
        }
        .confirmationDialog("Supprimer cette fiche et ses prises ?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible, presenting: pendingDeletion) { sheet in
            Button("Supprimer définitivement", role: .destructive) {
                do { try repository.deleteSheet(sheet) }
                catch { self.error = error.localizedDescription }
                pendingDeletion = nil
            }
        } message: { sheet in
            Text(deletionMessage(sheet))
        }
        .sheet(item: $editingRoll) { roll in RollEditor(roll: roll, repository: repository).tint(accent) }
        .toolbar {
            Button("Exporter", systemImage: "square.and.arrow.up") { exporting = true }
                .accessibilityIdentifier("export-report")
        }
        .sheet(isPresented: $exporting) {
            if let day = report.day {
                ExportView(day: day, repository: repository, camera: report.camera)
                    .tint(accent)
            }
        }
        .environment(\.sheetAccent, accent)
        .tint(accent)
        .logError($error)
    }

    @ViewBuilder private func rollSection(_ roll: Roll) -> some View {
        let rows = sheets(for: roll)
        if !rows.isEmpty {
            let numbers = roll.clipNumbers
            Section {
                ForEach(rows) { sheet in
                    NavigationLink {
                        SheetView(report: report, repository: repository, sheet: sheet)
                    } label: {
                        SheetRow(sheet: sheet, clipNumbers: numbers)
                    }
                    .accessibilityIdentifier("sheet-\(sheet.scene)-\(sheet.shot)")
                    .swipeActions {
                        Button("Supprimer", role: .destructive) { pendingDeletion = sheet }
                    }
                }
            } header: {
                HStack {
                    Button { editingRoll = roll } label: {
                        Label("ROLL \(roll.name)", systemImage: "pencil")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Modifier le roll \(roll.name)")
                    .accessibilityIdentifier("edit-roll-\(roll.name)")
                    Spacer()
                    Text(clipSummary(roll.clipCount)).monospacedDigit()
                }
            }
        }
    }

    private func deletionMessage(_ sheet: ShotSheet) -> String {
        let summary = ClipSequence.summary(repository.previewDeletion(of: sheet))
        return "\(sheet.takes.count) prise(s) supprimée(s). Numéros de clips recalculés :\n\(summary)"
    }

    private func clipSummary(_ count: Int) -> String {
        count == 0 ? "aucun clip" : "\(count) clip\(count > 1 ? "s" : "") · dernier \(ClipCode.code(count))"
    }
}

private struct SheetRow: View {
    @Environment(\.sheetAccent) private var accent
    let sheet: ShotSheet
    let clipNumbers: [UUID: Int]

    var body: some View {
        let takes = sheet.orderedTakes
        let clips = takes.compactMap { clipNumbers[$0.id] }
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sheet.scene).font(.title2.bold()).monospacedDigit()
                Text("PLAN \(sheet.shot)").font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    ForEach(takes.prefix(7)) { take in
                        Text("\(take.number)")
                            .font(.caption.bold()).monospacedDigit()
                            .frame(width: 26, height: 26)
                            .foregroundStyle(take.isCircle ? Color.black : Color.primary)
                            .background(take.isCircle ? accent : Color.clear, in: Circle())
                            .overlay(Circle().strokeBorder(accent, lineWidth: 1))
                    }
                    if takes.count > 7 { Text("+\(takes.count - 7)").font(.caption) }
                }
                Text(rangeText(clips))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)
            Text(sheet.settings[SheetField.lens.rawValue] ?? "—")
                .font(.caption.bold()).lineLimit(1)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(takes: takes, clips: clips))
    }

    private func rangeText(_ clips: [Int]) -> String {
        guard let low = clips.min(), let high = clips.max() else { return "Aucune prise" }
        return "\(ClipCode.code(low)) → \(ClipCode.code(high))"
    }

    private func spokenLabel(takes: [TakeEntry], clips: [Int]) -> String {
        let circled = takes.filter(\.isCircle).count
        var text = "Scène \(sheet.scene), plan \(sheet.shot), \(takes.count) prises, \(circled) cerclées"
        if let low = clips.min(), let high = clips.max() {
            text += ", clips \(ClipCode.code(low)) à \(ClipCode.code(high))"
        }
        return text
    }
}

/// Roll name, card and reel. Renaming moves every sheet of the roll with it.
struct RollEditor: View {
    let roll: Roll
    let repository: CameraLogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var card: String
    @State private var reel: String
    @State private var error: String?
    init(roll: Roll, repository: CameraLogRepository) {
        self.roll = roll; self.repository = repository
        _name = State(initialValue: roll.name)
        _card = State(initialValue: roll.card)
        _reel = State(initialValue: roll.reel)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Roll, par exemple A010", text: $name)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Magasin # (carte)", text: $card)
                    TextField("Reel", text: $reel)
                } footer: {
                    Text("Renommer le roll renomme la carte de toutes ses fiches ; les numéros de clips ne changent pas.")
                }
            }
            .navigationTitle("ROLL \(roll.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(save: {
                do { try repository.updateRoll(roll, name: name, card: card, reel: reel); dismiss() }
                catch { self.error = error.localizedDescription }
            }, cancel: { dismiss() }) }
            .logError($error)
        }
    }
}
