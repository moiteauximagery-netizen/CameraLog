import SwiftUI
import SwiftData

struct ProductionListView: View {
    let repository: CameraLogRepository
    @Query(sort: \Production.createdAt, order: .reverse) private var productions: [Production]
    @State private var creating = false
    @State private var error: String?
    @State private var pendingDeletion: Production?
    private var recentReport: CameraReport? {
        productions.flatMap(\.days).flatMap(\.reports).max {
            activityDate(for: $0) < activityDate(for: $1)
        }
    }
    private func activityDate(for report: CameraReport) -> Date {
        report.rolls.flatMap(\.takes).map(\.updatedAt).max() ?? report.createdAt
    }
    var body: some View {
        NavigationStack {
            List {
                if let report = recentReport {
                    Section {
                        NavigationLink {
                            ReportView(report: report, repository: repository)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Reprendre le rapport", systemImage: "arrow.uturn.forward.circle.fill")
                                    .font(.headline)
                                Text("\(report.day?.production?.name ?? "Production") · DAY \(report.day?.number ?? 0) · CAM \(report.camera?.name ?? "—")")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                Section {
                    ForEach(productions) { production in
                        NavigationLink {
                            ProductionDetailView(production: production, repository: repository)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(production.name).font(.headline)
                                Text("\(production.days.count) journées · \(production.client)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 8)
                        }
                        .swipeActions {
                            Button("Supprimer", role: .destructive) { pendingDeletion = production }
                        }
                    }
                } header: { Text("Productions · stockage local") }
                if productions.isEmpty {
                    ContentUnavailableView("Premier tournage", systemImage: "film.stack",
                        description: Text("Crée une production pour commencer ton rapport caméra."))
                    Button("Charger LES OMBRES — exemple") {
                        do { try SampleData.load(into: repository) }
                        catch { self.error = error.localizedDescription }
                    }.frame(minHeight: 48)
                }
            }
            .navigationTitle("CAMERALOG")
            .safeAreaInset(edge: .bottom) {
                Button { creating = true } label: {
                    Label("Nouvelle production", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.borderedProminent).padding().background(.bar)
            }
            .sheet(isPresented: $creating) { ProductionEditor(repository: repository) }
            .confirmationDialog("Supprimer cette production et tous ses rapports ?", isPresented: Binding(
                get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("Supprimer définitivement", role: .destructive) {
                    guard let item = pendingDeletion else { return }
                    do { try repository.deleteProduction(item) }
                    catch { self.error = error.localizedDescription }
                    pendingDeletion = nil
                }
            }
            .logError($error)
        }
    }
}

struct ProductionEditor: View {
    let repository: CameraLogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var client = ""
    @State private var director = ""
    @State private var cinematographer = ""
    @State private var number = ""
    @State private var notes = ""
    @State private var start = Date()
    @State private var hasEnd = false
    @State private var end = Date()
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Production") {
                    TextField("Nom", text: $name)
                    TextField("Client / producteur", text: $client)
                    TextField("Numéro de projet", text: $number)
                }
                Section("Équipe") {
                    TextField("Réalisateur", text: $director)
                    TextField("Directeur photo", text: $cinematographer)
                }
                Section("Calendrier") {
                    DatePicker("Début", selection: $start, displayedComponents: .date)
                    Toggle("Date de fin connue", isOn: $hasEnd)
                    if hasEnd { DatePicker("Fin", selection: $end, displayedComponents: .date) }
                }
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("Nouvelle production")
            .toolbar { SaveToolbar(save: save, cancel: { dismiss() }) }
            .logError($error)
        }
    }
    private func save() {
        do {
            try repository.addProduction(name: name, client: client, director: director,
                cinematographer: cinematographer, start: start, end: hasEnd ? end : nil,
                projectNumber: number, notes: notes)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ProductionDetailView: View {
    let production: Production
    let repository: CameraLogRepository
    @State private var addingDay = false
    var body: some View {
        List {
            Section("Journées") {
                ForEach(production.days.sorted { $0.number < $1.number }) { day in
                    NavigationLink {
                        DayView(day: day, repository: repository)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DAY \(day.number)").font(.headline)
                            Text(day.date, style: .date)
                            Text(day.location).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
                Button("Ajouter une journée", systemImage: "plus") { addingDay = true }
                    .frame(minHeight: 48)
            }
            Section("Équipe") {
                LabeledContent("Production", value: production.client)
                LabeledContent("Réalisation", value: production.director)
                LabeledContent("Image", value: production.cinematographer)
            }
        }
        .navigationTitle(production.name)
        .sheet(isPresented: $addingDay) { DayEditor(production: production, repository: repository) }
    }
}

struct DayEditor: View {
    let production: Production
    let repository: CameraLogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var number: Int
    @State private var date = Date()
    @State private var location = ""
    @State private var unit = ""
    @State private var notes = ""
    @State private var error: String?
    init(production: Production, repository: CameraLogRepository) {
        self.production = production; self.repository = repository
        _number = State(initialValue: (production.days.map(\.number).max() ?? 0) + 1)
    }
    var body: some View {
        NavigationStack {
            Form {
                Stepper("DAY \(number)", value: $number, in: 1...9999)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Lieu", text: $location)
                TextField("Unité", text: $unit)
                TextField("Notes", text: $notes, axis: .vertical)
            }.navigationTitle("Nouvelle journée")
            .toolbar { SaveToolbar(save: {
                do {
                    try repository.addDay(to: production, number: number, date: date,
                        location: location, unit: unit, notes: notes)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }, cancel: { dismiss() }) }
            .logError($error)
        }
    }
}
