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
        (report.rolls.flatMap(\.takes).map(\.updatedAt) + report.rolls.flatMap(\.sheets).map(\.updatedAt)).max()
            ?? report.createdAt
    }
    var body: some View {
        let _ = repository.revision
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
                        .accessibilityIdentifier("resume-report")
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
                        .accessibilityIdentifier("production-\(production.name)")
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
            .sheet(isPresented: $creating) { ProductionEditor(repository: repository, production: nil) }
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

/// Creates a production or edits every one of its settings, including the lens and filter kits.
struct ProductionEditor: View {
    let repository: CameraLogRepository
    let production: Production?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var client: String
    @State private var director: String
    @State private var cinematographer: String
    @State private var number: String
    @State private var notes: String
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date
    @State private var lenses: [String]
    @State private var lensEntry = ""
    @State private var filters: [EditableFilterFamily]
    @State private var error: String?

    init(repository: CameraLogRepository, production: Production?) {
        self.repository = repository
        self.production = production
        _name = State(initialValue: production?.name ?? "")
        _client = State(initialValue: production?.client ?? "")
        _director = State(initialValue: production?.director ?? "")
        _cinematographer = State(initialValue: production?.cinematographer ?? "")
        _number = State(initialValue: production?.projectNumber ?? "")
        _notes = State(initialValue: production?.notes ?? "")
        _start = State(initialValue: production?.startDate ?? Date())
        _hasEnd = State(initialValue: production?.endDate != nil)
        _end = State(initialValue: production?.endDate ?? Date())
        _lenses = State(initialValue: production?.lensKit ?? [])
        _filters = State(initialValue: (production?.filterKit ?? FilterFamily.defaultKit).map(EditableFilterFamily.init))
    }

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
                lensSection
                filterSection
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(production == nil ? "Nouvelle production" : "Réglages du projet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(save: save, cancel: { dismiss() }) }
            .logError($error)
        }
    }

    private var lensSection: some View {
        Section {
            ForEach(lenses, id: \.self) { lens in Text(lens) }
                .onDelete { lenses.remove(atOffsets: $0) }
            HStack {
                TextField("18, 25, 32, 50, 75…", text: $lensEntry)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .onSubmit(addLenses)
                    .accessibilityIdentifier("lens-entry")
                Button("Ajouter", action: addLenses)
                    .disabled(lensEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Série d’objectifs")
        } footer: {
            Text("Ces focales apparaissent dans le menu de la case OBJECTIF. Plusieurs valeurs séparées par des virgules. Sans série, la case reste en saisie libre.")
        }
    }

    private var filterSection: some View {
        Section {
            ForEach($filters) { $family in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Famille, par exemple ND", text: $family.name)
                        .font(.headline)
                        .autocorrectionDisabled()
                    TextField("Valeurs : 0.3, 0.6, 0.9", text: $family.grades)
                        .font(.subheadline)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                }
                .padding(.vertical, 2)
            }
            .onDelete { filters.remove(atOffsets: $0) }
            Button("Ajouter une famille de filtres", systemImage: "plus") {
                filters.append(EditableFilterFamily(FilterFamily(name: "", grades: [])))
            }
            Button("Rétablir le kit standard") {
                filters = FilterFamily.defaultKit.map(EditableFilterFamily.init)
            }
        } header: {
            Text("Kit de filtres")
        } footer: {
            Text("Dans la case FILTRES : famille puis valeur, en un toucher. Une famille sans valeur (POLA) s’ajoute directement. Balayer pour supprimer.")
        }
    }

    private func addLenses() {
        lenses = LensKit.merged(lenses, adding: LensKit.parse(lensEntry))
        lensEntry = ""
    }

    private func save() {
        if !lensEntry.trimmingCharacters(in: .whitespaces).isEmpty { addLenses() }
        let kit = filters.map { FilterFamily(name: $0.name, grades: FilterFamily.parseGrades($0.grades)) }
        if hasEnd && end < start { error = "La fin doit suivre le début."; return }
        do {
            let target: Production
            if let production { target = production } else {
                target = try repository.addProduction(name: name)
            }
            try repository.updateProduction(target, name: name, client: client, director: director,
                cinematographer: cinematographer, start: start, end: hasEnd ? end : nil,
                projectNumber: number, notes: notes, lensKit: lenses, filterKit: kit)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Filter family edited as text: grades are typed comma-separated.
struct EditableFilterFamily: Identifiable {
    let id = UUID()
    var name: String
    var grades: String
    init(_ family: FilterFamily) {
        name = family.name
        grades = family.grades.joined(separator: ", ")
    }
}

struct ProductionDetailView: View {
    let production: Production
    let repository: CameraLogRepository
    @State private var addingDay = false
    @State private var editing = false
    var body: some View {
        let _ = repository.revision
        List {
            Section("Journées") {
                ForEach(production.days.sorted { $0.number < $1.number }) { day in
                    NavigationLink {
                        DayView(day: day, repository: repository)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DAY \(day.number)").font(.headline)
                            Text(day.date, style: .date)
                            if !day.location.isEmpty { Text(day.location).foregroundStyle(.secondary) }
                        }.padding(.vertical, 6)
                    }
                    .accessibilityIdentifier("day-\(day.number)")
                }
                Button("Ajouter une journée", systemImage: "plus") { addingDay = true }
                    .frame(minHeight: 48)
            }
            Section("Équipe") {
                LabeledContent("Production", value: production.client)
                LabeledContent("Réalisation", value: production.director)
                LabeledContent("Image", value: production.cinematographer)
            }
            Section("Matériel") {
                LabeledContent("Objectifs", value: production.lensKit.isEmpty ? "Aucune série"
                               : production.lensKit.joined(separator: ", "))
                LabeledContent("Filtres", value: production.filterKit.map(\.name).joined(separator: ", "))
            }
        }
        .navigationTitle(production.name)
        .toolbar {
            Button("Réglages", systemImage: "slider.horizontal.3") { editing = true }
                .accessibilityIdentifier("edit-production")
        }
        .sheet(isPresented: $addingDay) { DayEditor(production: production, day: nil, repository: repository) }
        .sheet(isPresented: $editing) { ProductionEditor(repository: repository, production: production) }
    }
}

/// Creates a day (with camera A) or edits its number, date, location, unit and notes.
struct DayEditor: View {
    let production: Production
    let day: ShootDay?
    let repository: CameraLogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var number: Int
    @State private var date: Date
    @State private var location: String
    @State private var unit: String
    @State private var notes: String
    @State private var error: String?
    init(production: Production, day: ShootDay?, repository: CameraLogRepository) {
        self.production = production; self.day = day; self.repository = repository
        _number = State(initialValue: day?.number ?? (production.days.map(\.number).max() ?? 0) + 1)
        _date = State(initialValue: day?.date ?? Date())
        _location = State(initialValue: day?.location ?? "")
        _unit = State(initialValue: day?.unit ?? "")
        _notes = State(initialValue: day?.notes ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Stepper("DAY \(number)", value: $number, in: 1...9999)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Lieu", text: $location)
                    .accessibilityIdentifier("day-location")
                TextField("Unité", text: $unit)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle(day == nil ? "Nouvelle journée" : "Modifier la journée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(save: save, cancel: { dismiss() }) }
            .logError($error)
        }
    }
    private func save() {
        do {
            if let day {
                try repository.updateDay(day, number: number, date: date, location: location, unit: unit, notes: notes)
            } else {
                let created = try repository.addDay(to: production, number: number, date: date,
                    location: location, unit: unit, notes: notes)
                try repository.addNextCamera(to: created)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
