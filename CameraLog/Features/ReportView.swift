import SwiftUI

struct ReportView: View {
    let report: CameraReport
    let repository: CameraLogRepository
    @State private var selectedRollID: UUID?
    @State private var addingRoll = false
    @State private var addingTake = false
    @State private var error: String?
    @State private var pendingDeletion: TakeEntry?
    @State private var feedback = 0
    private var selectedRoll: Roll? {
        report.rolls.first { $0.id == selectedRollID } ?? report.orderedRolls.last
    }
    var body: some View {
        List {
            Section {
                Text("DAY \(report.day?.number ?? 0)").foregroundStyle(.secondary)
                if !report.rolls.isEmpty {
                    Picker("Roll actif", selection: Binding(
                        get: { selectedRoll?.id }, set: { selectedRollID = $0 }
                    )) {
                        ForEach(report.orderedRolls) { roll in
                            Text(roll.name).tag(Optional(roll.id))
                        }
                    }
                }
                Button("Nouveau roll / card", systemImage: "plus.rectangle.on.folder") { addingRoll = true }
                    .frame(minHeight: 48)
            }
            if let roll = selectedRoll {
                Section("\(roll.name) · \(roll.takes.count) prises") {
                    ForEach(roll.orderedTakes.reversed()) { take in
                        TakeRow(take: take) {
                            do { try repository.toggleCircle(take); feedback += 1 }
                            catch { self.error = error.localizedDescription }
                        }
                        .swipeActions {
                            Button("Supprimer", role: .destructive) { pendingDeletion = take }
                        }
                    }
                    if roll.takes.isEmpty { Text("Prêt pour la première prise.").foregroundStyle(.secondary) }
                }
            } else {
                ContentUnavailableView("Premier roll", systemImage: "sdcard",
                    description: Text("Ajoute le roll ou la carte avant d’enregistrer une prise."))
            }
        }
        .navigationTitle("CAM \(report.camera?.name ?? "—")")
        .safeAreaInset(edge: .bottom) {
            Button { addingTake = true } label: {
                Label("TAKE", systemImage: "plus").font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 52)
            }.buttonStyle(.borderedProminent).disabled(selectedRoll == nil)
                .padding().background(.bar)
        }
        .sheet(isPresented: $addingRoll) {
            RollEditor(report: report, repository: repository) { selectedRollID = $0.id; feedback += 1 }
        }
        .sheet(isPresented: $addingTake) {
            if let roll = selectedRoll {
                TakeEditor(roll: roll, repository: repository,
                    draft: repository.nextDraft(for: report)) { feedback += 1 }
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
}

struct TakeRow: View {
    let take: TakeEntry
    let circle: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("S\(take.scene)  SH\(take.shot)  T\(String(format: "%02d", take.number))")
                .font(.title3.bold()).monospacedDigit()
            Text([take.settings.lensName, take.settings.filters.joined(separator: " + ")]
                .filter { !$0.isEmpty }.joined(separator: " · "))
            Text("\(take.settings.iso) ISO · \(take.settings.whiteBalance) K · \(take.settings.fps.formatted()) fps · \(take.settings.shutterAngle.formatted())°")
                .font(.subheadline).foregroundStyle(.secondary)
            if !take.notes.isEmpty { Text(take.notes) }
            if !take.statusValues.isEmpty {
                Text(take.statusValues.joined(separator: " · ")).font(.caption.bold())
            }
            Button(action: circle) {
                Label(take.isCircle ? "CIRCLE" : "Circle",
                    systemImage: take.isCircle ? "checkmark.circle.fill" : "circle")
                    .frame(minHeight: 44)
            }.buttonStyle(.bordered).tint(take.isCircle ? .orange : .gray)
                .accessibilityLabel("Circle, scène \(take.scene), plan \(take.shot), prise \(take.number)")
                .accessibilityValue(take.isCircle ? "Activé" : "Désactivé")
        }.padding(.vertical, 8)
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
