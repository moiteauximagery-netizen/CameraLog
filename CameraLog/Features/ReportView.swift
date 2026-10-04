import SwiftUI

private enum ReportSearch: String, CaseIterable, Identifiable {
    case all = "Tout", scene = "Scène", roll = "Roll", lens = "Optique"
    var id: String { rawValue }
}

private struct TakeGroup: Identifiable {
    let scene: String
    let shot: String
    let takes: [TakeEntry]
    var id: String { "\(scene.lowercased())|\(shot.lowercased())" }
    var latest: TakeEntry { takes.max { $0.createdAt < $1.createdAt }! }
}

struct ReportView: View {
    let report: CameraReport
    let repository: CameraLogRepository
    @State private var selectedRollID: UUID?
    @State private var addingRoll = false
    @State private var addingTake = false
    @State private var editingTake: TakeEntry?
    @State private var query = ""
    @State private var searchScope: ReportSearch = .all
    @State private var error: String?
    @State private var pendingDeletion: TakeEntry?
    @State private var feedback = 0

    private var selectedRoll: Roll? {
        report.rolls.first { $0.id == selectedRollID } ?? report.orderedRolls.last
    }

    private func groups(for roll: Roll) -> [TakeGroup] {
        let matching = roll.takes.filter { take in
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return true }
            let fields: [String]
            switch searchScope {
            case .all: fields = [take.scene, take.shot, roll.name, take.settings.lensName]
            case .scene: fields = [take.scene, take.shot]
            case .roll: fields = [roll.name]
            case .lens: fields = [take.settings.lensName]
            }
            return fields.contains { $0.localizedStandardContains(term) }
        }
        let keys = Dictionary(grouping: matching) { "\($0.scene.lowercased())|\($0.shot.lowercased())" }
        return keys.values.map { takes in
            let first = takes[0]
            return TakeGroup(scene: first.scene, shot: first.shot,
                takes: takes.sorted { $0.number < $1.number })
        }.sorted { $0.latest.createdAt > $1.latest.createdAt }
    }

    var body: some View {
        reportList
        .searchable(text: $query, prompt: "Scène, roll ou objectif")
        .navigationTitle("CAM \(report.camera?.name ?? "—")")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nouveau roll", systemImage: "plus.rectangle.on.folder") { addingRoll = true }
            }
        }
        .safeAreaInset(edge: .bottom) { activeRollBar }
        .sheet(isPresented: $addingRoll) {
            RollEditor(report: report, repository: repository) {
                selectedRollID = $0.id; feedback += 1
            }
        }
        .sheet(isPresented: $addingTake) {
            if let roll = selectedRoll {
                TakeEditor(roll: roll, repository: repository,
                    draft: repository.nextDraft(for: report)) { feedback += 1 }
            }
        }
        .sheet(item: $editingTake) { take in
            if let roll = take.roll {
                TakeEditor(roll: roll, repository: repository,
                    draft: take.draft, existingTake: take) { feedback += 1 }
            }
        }
        .confirmationDialog("Supprimer cette prise définitivement ?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                guard let take = pendingDeletion else { return }
                do { try repository.deleteTake(take) }
                catch { self.error = error.localizedDescription }
                pendingDeletion = nil
            }
        }
        .sensoryFeedback(.success, trigger: feedback)
        .logError($error)
    }

    private var reportList: some View {
        List {
            Picker("Rechercher par", selection: $searchScope) {
                ForEach(ReportSearch.allCases) { scope in Text(scope.rawValue).tag(scope) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            ForEach(report.orderedRolls.reversed()) { roll in
                rollSection(roll)
            }

            if report.rolls.isEmpty {
                ContentUnavailableView("Premier roll", systemImage: "sdcard",
                    description: Text("Ajoute un roll ou une carte pour commencer."))
            } else if !query.isEmpty && !report.rolls.contains(where: { !groups(for: $0).isEmpty }) {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    @ViewBuilder private func rollSection(_ roll: Roll) -> some View {
        let rows = groups(for: roll)
        if !rows.isEmpty || query.isEmpty {
            Section {
                if rows.isEmpty {
                    Text("Aucune prise sur ce roll").foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { group in
                        TakeGroupRow(group: group,
                            edit: { editingTake = $0 },
                            circle: circle,
                            delete: { pendingDeletion = $0 })
                    }
                }
            } header: {
                HStack {
                    Text("ROLL \(roll.name)")
                    Spacer()
                    Text("\(roll.takes.count) prises")
                }
            }
        }
    }

    private var activeRollBar: some View {
            HStack(spacing: 12) {
                if let roll = selectedRoll {
                    Menu {
                        ForEach(report.orderedRolls.reversed()) { item in
                            Button(item.name) { selectedRollID = item.id }
                        }
                    } label: {
                        Label(roll.name, systemImage: "sdcard")
                            .lineLimit(1).frame(minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Roll actif : \(roll.name)")
                }
                Button { addingTake = true } label: {
                    Label("Nouvelle prise", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRoll == nil)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
    }

    private func circle(_ take: TakeEntry) {
        do { try repository.toggleCircle(take); feedback += 1 }
        catch { error = error.localizedDescription }
    }
}

private struct TakeGroupRow: View {
    let group: TakeGroup
    let edit: (TakeEntry) -> Void
    let circle: (TakeEntry) -> Void
    let delete: (TakeEntry) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { edit(group.latest) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.scene).font(.title2.bold()).monospacedDigit()
                    Text("PLAN \(group.shot)").font(.caption).foregroundStyle(.secondary)
                }
                .frame(minWidth: 58, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Modifier scène \(group.scene), plan \(group.shot)")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(group.takes) { take in
                        Button { circle(take) } label: {
                            Text("\(take.number)")
                                .font(.subheadline.bold()).monospacedDigit()
                                .frame(width: 34, height: 34)
                                .foregroundStyle(take.isCircle ? Color.white : Color.primary)
                                .background(take.isCircle ? Color.orange : Color.clear,
                                    in: Circle())
                                .overlay(Circle().strokeBorder(.orange, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Prise \(take.number), \(take.isCircle ? "cerclée" : "non cerclée")")
                        .accessibilityHint("Touchez pour changer Circle. Appui long pour modifier ou supprimer.")
                        .contextMenu {
                            Button("Modifier", systemImage: "pencil") { edit(take) }
                            Button("Supprimer", systemImage: "trash", role: .destructive) { delete(take) }
                        }
                    }
                }
                .frame(minHeight: 44)
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text(group.latest.settings.lensName.isEmpty ? "—" : group.latest.settings.lensName)
                    .font(.caption.bold()).lineLimit(1)
                Text(group.latest.settings.filters.joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }
}

struct RollEditor: View {
    let report: CameraReport
    let repository: CameraLogRepository
    let onSave: (Roll) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var card = ""
    @State private var reel = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Roll, par exemple A004", text: $name)
                TextField("Card", text: $card)
                TextField("Reel", text: $reel)
            }.navigationTitle("Nouveau roll")
            .toolbar { SaveToolbar(save: {
                do {
                    let roll = try repository.addRoll(to: report, name: name, card: card, reel: reel)
                    onSave(roll); dismiss()
                } catch { self.error = error.localizedDescription }
            }, cancel: { dismiss() }) }
            .logError($error)
        }
    }
}
