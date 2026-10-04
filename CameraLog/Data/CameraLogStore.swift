import Foundation
import SwiftData

/// Schema 2 adds shot sheets, take labels, card order and settings snapshots.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Production.self, ShootDay.self, Camera.self, CameraReport.self, Roll.self, ShotSheet.self, TakeEntry.self]
    }
}

/// Version 1 → 2 only adds an entity, a relationship and optional attributes: a lightweight
/// migration keeps every row and identifier. Sheets are then attached by `migrateLegacyTakes()`.
enum CameraLogMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

enum CameraLogStore {
    static let schema = Schema(versionedSchema: SchemaV2.self)

    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema,
                isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: CameraLogMigrationPlan.self,
                                  configurations: [configuration])
    }
}

/// One main-actor context, explicit commits. Failed writes roll back; never acknowledge an unsaved take.
@MainActor final class CameraLogRepository {
    // ModelContext does not keep its container alive. The repository must own
    // both so an independently created repository can safely insert models.
    private let container: ModelContainer
    let context: ModelContext
    init(context: ModelContext) {
        container = context.container
        self.context = context
        context.autosaveEnabled = false
    }

    private func commit() throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
    private func required(_ value: String, _ label: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LogError.invalid("\(label) est obligatoire.") }
        return result
    }
    private func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    @discardableResult func addProduction(name: String, client: String = "", director: String = "",
        cinematographer: String = "", start: Date = Date(), end: Date? = nil,
        projectNumber: String = "", notes: String = "") throws -> Production {
        let name = try required(name, "Le nom")
        if let end, end < start { throw LogError.invalid("La fin doit suivre le début.") }
        let item = Production(name: name)
        item.client = client; item.director = director; item.cinematographer = cinematographer
        item.startDate = start; item.endDate = end; item.projectNumber = projectNumber; item.notes = notes
        context.insert(item); try commit(); return item
    }

    @discardableResult func addDay(to production: Production, number: Int, date: Date,
        location: String = "", unit: String = "", notes: String = "") throws -> ShootDay {
        guard number > 0, !production.days.contains(where: { $0.number == number }) else {
            throw LogError.invalid("Le numéro de journée doit être positif et unique dans la production.")
        }
        let day = ShootDay(number: number, date: date, production: production)
        day.location = location; day.unit = unit; day.notes = notes
        context.insert(day); try commit(); return day
    }

    @discardableResult func addCamera(to production: Production, name: String,
        manufacturer: String = "", model: String = "", serialNumber: String = "") throws -> Camera {
        let name = try required(name, "Le nom caméra")
        guard !production.cameras.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
            throw LogError.invalid("Cette caméra existe déjà dans la production.")
        }
        let camera = Camera(name: name, production: production)
        camera.manufacturer = manufacturer; camera.model = model; camera.serialNumber = serialNumber
        context.insert(camera); try commit(); return camera
    }

    @discardableResult func addReport(to day: ShootDay, camera: Camera) throws -> CameraReport {
        guard day.production?.id == camera.production?.id else {
            throw LogError.invalid("La caméra doit appartenir à cette production.")
        }
        guard !day.reports.contains(where: { $0.camera?.id == camera.id }) else {
            throw LogError.invalid("Cette caméra possède déjà un rapport pour la journée.")
        }
        let report = CameraReport(day: day, camera: camera)
        context.insert(report); try commit(); return report
    }

    /// Explicit roll creation, kept for card/reel details. Sheets create their roll automatically.
    @discardableResult func addRoll(to report: CameraReport, name: String,
        card: String = "", reel: String = "") throws -> Roll {
        let name = try required(name, "Le roll")
        guard roll(named: name, in: report) == nil else {
            throw LogError.invalid("Ce roll existe déjà dans ce rapport.")
        }
        let roll = Roll(name: name, report: report); roll.card = card; roll.reel = reel
        context.insert(roll); try commit(); return roll
    }

    func roll(named name: String, in report: CameraReport) -> Roll? {
        report.rolls.first { same($0.name, name) }
    }

    // MARK: Data recorded before shot sheets

    /// Attaches takes recorded with schema 1 to sheets grouped by roll, scene and shot, and gives
    /// them a card order following their creation date. Settings, statuses, identifiers and the
    /// typed clip names are left untouched. Idempotent; returns the number of updated takes.
    @discardableResult func migrateLegacyTakes() throws -> Int {
        var updated = Set<UUID>()
        for roll in try context.fetch(FetchDescriptor<Roll>()) {
            let takes = roll.takes.filter { $0.roll?.id == roll.id }
            var next = takes.compactMap(\.cardOrder).max() ?? 0
            let unordered = takes.filter { $0.cardOrder == nil }
                .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            for take in unordered { next += 1; take.cardOrder = next; updated.insert(take.id) }

            let orphans = takes.filter { $0.sheet == nil }
            let groups = Dictionary(grouping: orphans) { "\($0.scene.lowercased())|\($0.shot.lowercased())" }
            for group in groups.values {
                let ordered = group.sorted { $0.createdAt < $1.createdAt }
                guard let first = ordered.first, let last = ordered.last else { continue }
                let sheet: ShotSheet
                if let existing = roll.currentSheets.first(where: { same($0.scene, first.scene) && same($0.shot, first.shot) }) {
                    sheet = existing
                } else {
                    sheet = ShotSheet(scene: first.scene, shot: first.shot, roll: roll)
                    sheet.settings = last.settings.sheetValues
                    sheet.createdAt = first.createdAt
                    sheet.updatedAt = last.updatedAt
                    context.insert(sheet)
                }
                for take in group { take.sheet = sheet; updated.insert(take.id) }
            }
        }
        if !updated.isEmpty { try commit() }
        return updated.count
    }

    // MARK: Shot sheets

    func previousSheet(in report: CameraReport, excluding sheet: ShotSheet? = nil) -> ShotSheet? {
        report.rolls.flatMap(\.currentSheets).filter { $0.id != sheet?.id }
            .max { $0.lastActivity < $1.lastActivity }
    }

    func newSheetDraft(for report: CameraReport) -> SheetDraft {
        var draft = SheetDraft()
        suggest(into: &draft, report: report, excluding: nil)
        return draft
    }

    func draft(for sheet: ShotSheet, in report: CameraReport) -> SheetDraft {
        var draft = SheetDraft()
        draft[.scene] = sheet.scene
        draft[.shot] = sheet.shot
        draft[.roll] = sheet.roll?.name ?? ""
        let settings = sheet.settings
        for field in SheetField.settings { draft[field] = settings[field.rawValue] ?? "" }
        draft.notes = sheet.notes
        suggest(into: &draft, report: report, excluding: sheet)
        return draft
    }

    private func suggest(into draft: inout SheetDraft, report: CameraReport, excluding sheet: ShotSheet?) {
        guard let previous = previousSheet(in: report, excluding: sheet) else { return }
        let rollName = previous.roll?.name ?? ""
        draft.suggestions = SmartFill.suggestions(scene: previous.scene, roll: rollName, settings: previous.settings)
        draft.suggestionSource = "la fiche \(previous.title) · \(rollName)"
    }

    /// Clip numbers that saving `rollName` on this sheet would change. Empty when nothing moves.
    func previewRollChange(for sheet: ShotSheet, to rollName: String, in report: CameraReport) -> [ClipChange] {
        let name = rollName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = sheet.roll, !name.isEmpty, !same(source.name, name) else { return [] }
        let moving = sheet.orderedTakes
        guard !moving.isEmpty else { return [] }
        let movingIDs = Set(moving.map(\.id))
        let target = roll(named: name, in: report)
        let targetName = target?.name ?? name.uppercased()
        let targetCount = target?.clipCount ?? 0
        let numbers = source.clipNumbers
        var changes: [ClipChange] = []
        for (offset, take) in moving.enumerated() {
            changes.append(ClipChange(id: take.id, title: take.displayTitle,
                from: "\(source.name) · \(ClipCode.code(numbers[take.id] ?? 0))",
                to: "\(targetName) · \(ClipCode.code(targetCount + offset + 1))"))
        }
        changes += removalChanges(on: source, sequence: source.clipSequence, removing: movingIDs)
        return changes
    }

    /// Saves only what the user typed or accepted. The roll is found by name for this camera and
    /// day, or created. Moving a sheet moves its takes, appended in order at the end of the new card.
    @discardableResult func saveSheet(_ draft: SheetDraft, sheet existing: ShotSheet?,
                                      in report: CameraReport) throws -> ShotSheet {
        let scene = try required(draft.value(.scene), "La scène")
        let shot = try required(draft.value(.shot), "Le plan")
        let rollName = try required(draft.value(.roll), "Le roll").uppercased()
        var settings = try SheetValidation.normalizedSettings(draft.settingsToSave)
        if let existing {
            // Keep values written by a later version for fields this screen does not show.
            for (key, value) in existing.settings where SheetField(rawValue: key) == nil { settings[key] = value }
        }
        let target = roll(named: rollName, in: report)
        if let target, target.currentSheets.contains(where: {
            $0.id != existing?.id && same($0.scene, scene) && same($0.shot, shot)
        }) { throw LogError.duplicateSheet("\(scene) / \(shot)", target.name) }

        let roll: Roll
        if let target { roll = target } else {
            roll = Roll(name: rollName, report: report)
            context.insert(roll)
        }
        let sheet: ShotSheet
        if let existing {
            sheet = existing
            if sheet.roll?.id != roll.id {
                var next = roll.takes.filter { $0.roll?.id == roll.id }.compactMap(\.cardOrder).max() ?? 0
                for take in existing.orderedTakes { next += 1; take.roll = roll; take.cardOrder = next }
                sheet.roll = roll
            }
            sheet.revision += 1
        } else {
            sheet = ShotSheet(scene: scene, shot: shot, roll: roll)
            context.insert(sheet)
        }
        sheet.scene = scene
        sheet.shot = shot
        sheet.settings = settings
        sheet.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        sheet.updatedAt = Date()
        for take in sheet.takes where take.scene != scene || take.shot != shot {
            take.scene = scene; take.shot = shot
        }
        try commit()
        return sheet
    }

    func deleteSheet(_ sheet: ShotSheet) throws { context.delete(sheet); try commit() }

    func previewDeletion(of sheet: ShotSheet) -> [ClipChange] {
        guard let roll = sheet.roll else { return [] }
        return removalChanges(on: roll, sequence: roll.clipSequence, removing: Set(sheet.takes.map(\.id)))
    }

    // MARK: Takes

    func nextTakeNumber(in sheet: ShotSheet) -> Int { (sheet.takes.map(\.number).max() ?? 0) + 1 }

    /// Creates the next take of the sheet, last clip of its card, with a copy of the sheet settings.
    @discardableResult func addNextTake(to sheet: ShotSheet) throws -> TakeEntry {
        guard let roll = sheet.roll else { throw LogError.invalid("Roll introuvable.") }
        let order = (roll.takes.filter { $0.roll?.id == roll.id }.compactMap(\.cardOrder).max() ?? 0) + 1
        let take = TakeEntry(number: nextTakeNumber(in: sheet), sheet: sheet, roll: roll, cardOrder: order)
        context.insert(take); try commit(); return take
    }

    /// Clips that inserting a forgotten take at `position` (1-based) would renumber.
    func previewInsertion(on roll: Roll, at position: Int) -> [ClipChange] {
        let sequence = roll.clipSequence
        guard position >= 1, position <= sequence.count + 1 else { return [] }
        var changes: [ClipChange] = []
        for (index, take) in sequence.enumerated() where index + 1 >= position {
            changes.append(ClipChange(id: take.id, title: take.displayTitle,
                from: ClipCode.code(index + 1), to: ClipCode.code(index + 2)))
        }
        return changes
    }

    /// Inserts a forgotten take at a card position. Later clips move by one, as previewed.
    @discardableResult func insertTake(into sheet: ShotSheet, at position: Int, number: Int) throws -> TakeEntry {
        guard let roll = sheet.roll else { throw LogError.invalid("Roll introuvable.") }
        let sequence = roll.clipSequence
        guard position >= 1, position <= sequence.count + 1 else {
            throw LogError.invalid("Position de clip invalide.")
        }
        guard number > 0, number < 1000 else { throw LogError.invalid("Numéro de prise invalide.") }
        guard !sheet.takes.contains(where: { $0.number == number }) else { throw LogError.duplicateTake }
        for (index, take) in sequence.enumerated() {
            take.cardOrder = index + 1 < position ? index + 1 : index + 2
        }
        let take = TakeEntry(number: number, sheet: sheet, roll: roll, cardOrder: position)
        context.insert(take); try commit(); return take
    }

    /// Label, statuses and notes. Circle is preserved: it changes only through `toggleCircle`.
    func updateTake(_ take: TakeEntry, label: String, statuses: [String], notes: String) throws {
        var values = statuses.filter { $0 != TakeStatus.circle.rawValue }
        if take.isCircle { values.append(TakeStatus.circle.rawValue) }
        take.label = TakeLabel.normalized(label)
        take.statusValues = values
        take.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        take.updatedAt = Date(); take.revision += 1; try commit()
    }

    func toggleCircle(_ take: TakeEntry) throws {
        if take.isCircle { take.statusValues.removeAll { $0 == TakeStatus.circle.rawValue } }
        else { take.statusValues.append(TakeStatus.circle.rawValue) }
        take.updatedAt = Date(); take.revision += 1; try commit()
    }

    /// Normal mode opens the editor; circle mode toggles Circle immediately.
    func tap(_ take: TakeEntry, mode: TakeTapMode) throws -> TakeTapAction {
        switch mode {
        case .edit: return .edit(take.id)
        case .circle: try toggleCircle(take); return .toggleCircle(take.id)
        }
    }

    func previewDeletion(of take: TakeEntry) -> [ClipChange] {
        guard let roll = take.roll else { return [] }
        return removalChanges(on: roll, sequence: roll.clipSequence, removing: [take.id])
    }

    func deleteTake(_ take: TakeEntry) throws { context.delete(take); try commit() }
    func deleteProduction(_ production: Production) throws { context.delete(production); try commit() }

    private func removalChanges(on roll: Roll, sequence: [TakeEntry], removing ids: Set<UUID>) -> [ClipChange] {
        var byID: [UUID: TakeEntry] = [:]
        for take in sequence { byID[take.id] = take }
        let after = sequence.map(\.id).filter { !ids.contains($0) }
        var changes: [ClipChange] = []
        for shift in ClipSequence.renumbered(before: sequence.map(\.id), after: after) {
            guard let take = byID[shift.id] else { continue }
            changes.append(ClipChange(id: take.id, title: take.displayTitle,
                from: "\(roll.name) · \(ClipCode.code(shift.from))",
                to: "\(roll.name) · \(ClipCode.code(shift.to))"))
        }
        return changes
    }
}
