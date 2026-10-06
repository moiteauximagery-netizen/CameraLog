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
    @State private var series: [EditableLensSeries]
    @State private var filters: [EditableFilterFamily]
    @State private var catalog: ProjectCatalog
    @State private var listEntries: [SheetField: String] = [:]
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
        _series = State(initialValue: (production?.lensSeries ?? []).map(EditableLensSeries.init))
        _filters = State(initialValue: (production?.filterKit ?? FilterFamily.defaultKit).map(EditableFilterFamily.init))
        _catalog = State(initialValue: production?.catalog ?? ProjectCatalog())
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
                ForEach(SheetField.catalogLists) { field in listSection(field) }
                visibleFieldsSection
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
            ForEach($series) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Série, par exemple S4", text: $item.name)
                        .font(.headline)
                        .autocorrectionDisabled()
                    TextField("Focales : 18, 25, 32, 50, 75", text: $item.focals)
                        .font(.subheadline)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("lens-entry")
                }
                .padding(.vertical, 2)
            }
            .onDelete { series.remove(atOffsets: $0) }
            Button("Ajouter une série d’objectifs", systemImage: "plus") {
                series.append(EditableLensSeries(LensSeries(name: "", focals: [])))
            }
        } header: {
            Text("Séries d’objectifs")
        } footer: {
            Text("La flèche de la case OBJECTIF affiche chaque série et ses focales ; la case reçoit « S4 50mm ». Sans série, la case reste en saisie libre. Balayer pour supprimer.")
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

    private func listSection(_ field: SheetField) -> some View {
        Section {
            ForEach(catalog.list(field), id: \.self) { value in Text(value) }
                .onDelete { offsets in
                    var values = catalog.list(field)
                    values.remove(atOffsets: offsets)
                    catalog.setList(values, for: field)
                }
            HStack {
                TextField(listPlaceholder(field), text: Binding(get: { listEntries[field] ?? "" },
                                                                set: { listEntries[field] = $0 }))
                    .autocorrectionDisabled()
                    .onSubmit { addListValues(field) }
                    .accessibilityIdentifier("list-entry-\(field.rawValue)")
                Button("Ajouter") { addListValues(field) }
                    .disabled((listEntries[field] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Liste \(field.spokenName)")
        } footer: {
            Text("Proposée par la flèche de la case \(field.title). Valeurs séparées par des virgules.")
        }
    }

    private func listPlaceholder(_ field: SheetField) -> String {
        switch field {
        case .lut: return "Show LUT v2, Rec709…"
        case .aspectRatio: return "1.85, 2.39…"
        case .format: return "ARRIRAW, ProRes 4444…"
        case .resolution: return "4.6K 3:2 OG, UHD…"
        default: return ""
        }
    }

    private func addListValues(_ field: SheetField) {
        var values = catalog.list(field)
        for value in FilterFamily.parseGrades(listEntries[field] ?? "")
        where !values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            values.append(value)
        }
        catalog.setList(values, for: field)
        listEntries[field] = ""
    }

    private var visibleFieldsSection: some View {
        Section {
            ForEach(SheetField.hideable) { field in
                Toggle(field.spokenName, isOn: shownBinding(field.rawValue))
                    .accessibilityIdentifier("show-\(field.rawValue)")
            }
            Toggle("VFX : hauteur, point, tilt", isOn: shownBinding(ProjectCatalog.vfxBlock))
                .accessibilityIdentifier("show-vfx")
        } header: {
            Text("Cases affichées sur les fiches")
        } footer: {
            Text("Scène, plan et roll restent toujours affichés. Une case masquée n’est plus proposée ; les valeurs déjà enregistrées restent dans les exports.")
        }
    }

    private func shownBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { !catalog.isHidden(key) }, set: { catalog.setHidden(key, !$0) })
    }

    private func save() {
        for field in SheetField.catalogLists where !(listEntries[field] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            addListValues(field)
        }
        let kit = filters.map { FilterFamily(name: $0.name, grades: FilterFamily.parseGrades($0.grades)) }
        if hasEnd && end < start { error = "La fin doit suivre le début."; return }
        do {
            let target: Production
            if let production { target = production } else {
                target = try repository.addProduction(name: name)
            }
            try repository.updateProduction(target, name: name, client: client, director: director,
                cinematographer: cinematographer, start: start, end: hasEnd ? end : nil,
                projectNumber: number, notes: notes, lensKit: [], filterKit: kit, catalog: catalog,
                lensSeries: series.map { LensSeries(name: $0.name, focals: LensKit.merged([], adding: LensKit.parse($0.focals))) })
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Lens series edited as text: focal lengths are typed comma-separated.
struct EditableLensSeries: Identifiable {
    let id = UUID()
    var name: String
    var focals: String
    init(_ series: LensSeries) {
        name = series.name
        focals = series.focals.joined(separator: ", ")
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
    @State private var filters = SearchFilters()
    @State private var facetPicker: SearchFacet?
    @State private var showTakes = false
    @State private var dayToDelete: ShootDay?
    @State private var confirmingDayDeletion = false
    @State private var error: String?
    var body: some View {
        let _ = repository.revision
        let result = ProjectSearch.run(production, filters: filters)
        List {
            Section {
                FilterChipsRow(filters: $filters) { facetPicker = $0 }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                if filters.isActive {
                    Picker("Afficher", selection: $showTakes) {
                        Text("Fiches").tag(false)
                        Text("Prises").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("results-mode")
                    Text("\(result.hits.count) fiche(s) · \(result.takeCount) prise(s) · \(result.circleCount) cerclée(s)")
                        .font(.subheadline.bold()).monospacedDigit()
                        .accessibilityIdentifier("results-count")
                }
            }
            if filters.isActive {
                SearchResultsSections(result: result, showTakes: showTakes, repository: repository)
            } else {
                projectSections
            }
        }
        .searchable(text: $filters.text, prompt: "Plan, roll, objectif, PU, note…")
        .navigationTitle(production.name)
        .toolbar {
            Button("Réglages", systemImage: "slider.horizontal.3") { editing = true }
                .accessibilityIdentifier("edit-production")
        }
        .sheet(item: $facetPicker) { facet in
            FacetPicker(facet: facet, options: result.options[facet] ?? [], filters: $filters)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $addingDay) { DayEditor(production: production, day: nil, repository: repository) }
        // First confirmation: what will be removed.
        .confirmationDialog("Supprimer DAY \(dayToDelete?.number ?? 0) ?", isPresented: Binding(
            get: { dayToDelete != nil && !confirmingDayDeletion }, set: { if !$0 && !confirmingDayDeletion { dayToDelete = nil } }
        ), titleVisibility: .visible, presenting: dayToDelete) { _ in
            Button("Continuer", role: .destructive) { confirmingDayDeletion = true }
                .accessibilityIdentifier("delete-day-continue")
            Button("Annuler", role: .cancel) { dayToDelete = nil }
        } message: { day in
            let summary = repository.deletionSummary(of: day)
            Text("\(summary.cameras) caméra(s), \(summary.sheets) fiche(s) et \(summary.takes) prise(s) de cette journée seront effacées. Les caméras restent dans la production.")
        }
        // Second confirmation: final.
        .alert("Suppression définitive de DAY \(dayToDelete?.number ?? 0)", isPresented: $confirmingDayDeletion,
               presenting: dayToDelete) { day in
            Button("Supprimer définitivement", role: .destructive) {
                do { try repository.deleteDay(day) }
                catch { self.error = error.localizedDescription }
                dayToDelete = nil
            }
            .accessibilityIdentifier("delete-day-confirm")
            Button("Annuler", role: .cancel) { dayToDelete = nil }
        } message: { _ in
            Text("Cette action ne peut pas être annulée.")
        }
        .logError($error)
        .sheet(isPresented: $editing) { ProductionEditor(repository: repository, production: production) }
    }

    @ViewBuilder private var projectSections: some View {
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
                    .swipeActions {
                        Button("Supprimer", role: .destructive) { dayToDelete = day }
                            .accessibilityIdentifier("delete-day-\(day.number)")
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
            Section("Matériel") {
                LabeledContent("Objectifs", value: production.lensSeries.isEmpty ? "Aucune série"
                               : production.lensSeries.map { $0.name.isEmpty ? "\($0.focals.count) focales" : $0.name }
                                    .joined(separator: ", "))
                LabeledContent("Filtres", value: production.filterKit.map(\.name).joined(separator: ", "))
            }
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
