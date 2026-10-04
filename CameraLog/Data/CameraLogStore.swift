import Foundation
import SwiftData

enum CameraLogStore {
    static let schema = Schema([
        Production.self, ShootDay.self, Camera.self, CameraReport.self, Roll.self, TakeEntry.self
    ])

    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema,
                isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
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

    @discardableResult func addRoll(to report: CameraReport, name: String,
        card: String = "", reel: String = "") throws -> Roll {
        let name = try required(name, "Le roll")
        guard !report.rolls.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
            throw LogError.invalid("Ce roll existe déjà dans ce rapport.")
        }
        let roll = Roll(name: name, report: report); roll.card = card; roll.reel = reel
        context.insert(roll); try commit(); return roll
    }

    func nextDraft(for report: CameraReport) -> TakeDraft {
        let latest = report.rolls.flatMap(\.takes).max { $0.createdAt < $1.createdAt }
        return SmartFill.next(after: latest?.draft, defaults: report.camera?.defaults ?? CaptureSettings())
    }

    @discardableResult func addTake(to roll: Roll, draft: TakeDraft) throws -> TakeEntry {
        var draft = draft
        try validate(&draft, on: roll)
        let take = TakeEntry(draft: draft, roll: roll)
        context.insert(take); try commit(); return take
    }

    func updateTake(_ take: TakeEntry, draft: TakeDraft) throws {
        guard let roll = take.roll else { throw LogError.invalid("Roll introuvable.") }
        var draft = draft
        try validate(&draft, on: roll, excluding: take.id)
        take.scene = draft.scene; take.shot = draft.shot; take.number = draft.number
        take.settings = draft.settings; take.statusValues = draft.statuses.map(\.rawValue)
        take.clipName = draft.clipName; take.fileName = draft.fileName
        take.tcIn = draft.tcIn; take.tcOut = draft.tcOut; take.notes = draft.notes
        take.technicalNotes = draft.technicalNotes; take.cameraNotes = draft.cameraNotes
        take.updatedAt = Date(); take.revision += 1; try commit()
    }

    private func validate(_ draft: inout TakeDraft, on roll: Roll, excluding id: UUID? = nil) throws {
        draft.scene = try required(draft.scene, "La scène")
        draft.shot = try required(draft.shot, "Le plan")
        guard draft.number > 0, draft.number < 100_000,
              draft.settings.fps.isFinite, draft.settings.fps > 0,
              draft.settings.iso > 0, draft.settings.whiteBalance > 0,
              draft.settings.shutterAngle.isFinite,
              draft.settings.shutterAngle > 0, draft.settings.shutterAngle <= 360 else {
            throw LogError.invalid("Vérifie le numéro de prise et les paramètres caméra.")
        }
        guard !roll.takes.contains(where: {
            $0.id != id &&
            $0.scene.caseInsensitiveCompare(draft.scene) == .orderedSame &&
            $0.shot.caseInsensitiveCompare(draft.shot) == .orderedSame && $0.number == draft.number
        }) else { throw LogError.duplicateTake }
    }

    func toggleCircle(_ take: TakeEntry) throws {
        if take.isCircle { take.statusValues.removeAll { $0 == TakeStatus.circle.rawValue } }
        else { take.statusValues.append(TakeStatus.circle.rawValue) }
        take.updatedAt = Date(); take.revision += 1; try commit()
    }

    func deleteTake(_ take: TakeEntry) throws { context.delete(take); try commit() }
    func deleteProduction(_ production: Production) throws { context.delete(production); try commit() }
}
