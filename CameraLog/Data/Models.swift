import Foundation
import SwiftData

@Model final class Production {
    @Attribute(.unique) var id: UUID
    var name: String
    var client = ""
    var director = ""
    var cinematographer = ""
    var startDate: Date
    var endDate: Date?
    var projectNumber = ""
    var notes = ""
    var defaults: CaptureSettings
    var createdAt: Date
    var updatedAt: Date
    var revision = 1
    @Relationship(deleteRule: .cascade, inverse: \ShootDay.production) var days: [ShootDay] = []
    @Relationship(deleteRule: .cascade, inverse: \Camera.production) var cameras: [Camera] = []
    // Schema 3: equipment kits. Optional so older stores migrate without inventing values.
    var lensKitData: Data?
    var filterKitData: Data?
    // Schema 4: lists offered on the sheet, the boxes the sheet shows, and lens series.
    var catalogData: Data?
    var lensSeriesData: Data?
    init(name: String) {
        id = UUID(); self.name = name; startDate = Date()
        createdAt = Date(); updatedAt = Date(); defaults = CaptureSettings()
    }
    /// Focal lengths of schema 3 (one unnamed series). Kept readable for older data.
    var lensKit: [String] {
        get { KitCoding.decode([String].self, from: lensKitData) ?? [] }
        set { lensKitData = KitCoding.encode(newValue) }
    }
    /// Lens series of the production. A schema 3 lens kit appears as one series without a name.
    /// Empty: the lens field has no menu.
    var lensSeries: [LensSeries] {
        get {
            if let series = KitCoding.decode([LensSeries].self, from: lensSeriesData) { return series }
            return lensKit.isEmpty ? [] : [LensSeries(name: "", focals: lensKit)]
        }
        set {
            lensSeriesData = KitCoding.encode(newValue)
            lensKit = newValue.flatMap { series in series.focals.map { LensSeries.value(series: series.name, focal: $0) } }
        }
    }
    /// LUT, ratio, format and resolution lists, and the boxes hidden on sheets.
    var catalog: ProjectCatalog {
        get { KitCoding.decode(ProjectCatalog.self, from: catalogData) ?? ProjectCatalog() }
        set { catalogData = KitCoding.encode(newValue) }
    }
    /// Filter families. Never edited: the standard kit.
    var filterKit: [FilterFamily] {
        get { KitCoding.decode([FilterFamily].self, from: filterKitData) ?? FilterFamily.defaultKit }
        set { filterKitData = KitCoding.encode(newValue) }
    }
}

@Model final class ShootDay {
    @Attribute(.unique) var id: UUID
    var number: Int
    var date: Date
    var location = ""
    var unit = ""
    var notes = ""
    var createdAt: Date
    var updatedAt: Date
    var revision = 1
    var production: Production?
    @Relationship(deleteRule: .cascade, inverse: \CameraReport.day) var reports: [CameraReport] = []
    init(number: Int, date: Date, production: Production) {
        id = UUID(); self.number = number; self.date = date; self.production = production
        createdAt = Date(); updatedAt = Date()
    }
}

@Model final class Camera {
    @Attribute(.unique) var id: UUID
    var name: String
    var manufacturer = ""
    var model = ""
    var serialNumber = ""
    var notes = ""
    var defaults: CaptureSettings
    var production: Production?
    @Relationship(inverse: \CameraReport.camera) var reports: [CameraReport] = []
    // Schema 4: identification color (nil: gray) and native ISO offered on sheets.
    var colorHue: Double?
    var nativeISO: String?
    init(name: String, production: Production) {
        id = UUID(); self.name = name; self.production = production; defaults = production.defaults
        colorHue = CameraColor.defaultHue(for: name)
    }
}

@Model final class CameraReport {
    @Attribute(.unique) var id: UUID
    var day: ShootDay?
    var camera: Camera?
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Roll.report) var rolls: [Roll] = []
    init(day: ShootDay, camera: Camera) {
        id = UUID(); self.day = day; self.camera = camera; createdAt = Date()
    }
    var orderedRolls: [Roll] { rolls.sorted { $0.createdAt < $1.createdAt } }
}

@Model final class Roll {
    @Attribute(.unique) var id: UUID
    var name: String
    var card = ""
    var reel = ""
    var createdAt: Date
    var report: CameraReport?
    @Relationship(deleteRule: .cascade, inverse: \TakeEntry.roll) var takes: [TakeEntry] = []
    // Schema 2: rolls are created automatically from the ROLL field of a sheet.
    @Relationship(deleteRule: .cascade, inverse: \ShotSheet.roll) var sheets: [ShotSheet] = []
    init(name: String, report: CameraReport) {
        id = UUID(); self.name = name; self.report = report; createdAt = Date()
    }
    /// Every clip recorded on this card, all sheets included, in card order.
    var clipSequence: [TakeEntry] {
        takes.filter { $0.roll?.id == id }.sorted(by: TakeEntry.precedesOnCard)
    }
    var clipNumbers: [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (index, take) in clipSequence.enumerated() { result[take.id] = index + 1 }
        return result
    }
    var clipCount: Int { clipSequence.count }
    var currentSheets: [ShotSheet] { sheets.filter { $0.roll?.id == id } }
}

/// One shot on one roll: identification, current settings and its takes.
@Model final class ShotSheet {
    @Attribute(.unique) var id: UUID
    var scene: String
    var shot: String
    var settingsData: Data?
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var roll: Roll?
    @Relationship(deleteRule: .cascade, inverse: \TakeEntry.sheet) var takes: [TakeEntry] = []
    init(scene: String, shot: String, roll: Roll) {
        id = UUID(); self.scene = scene; self.shot = shot; notes = ""; revision = 1
        createdAt = Date(); updatedAt = Date(); self.roll = roll
    }
    /// Values typed or accepted by the user. A missing key means « not known ».
    var settings: [String: String] {
        get { SettingsCoding.decode(settingsData) ?? [:] }
        set { settingsData = SettingsCoding.encode(newValue) }
    }
    var orderedTakes: [TakeEntry] {
        takes.filter { $0.sheet?.id == id }.sorted(by: TakeEntry.precedesOnCard)
    }
    var lastActivity: Date { max(updatedAt, takes.map(\.createdAt).max() ?? updatedAt) }
    var title: String { "\(scene) / \(shot)" }
}

@Model final class TakeEntry {
    @Attribute(.unique) var id: UUID
    var scene: String
    var shot: String
    var number: Int
    /// Schema 1 settings. Kept untouched for takes recorded before sheets; unused for new takes.
    var settings: CaptureSettings
    var statusValues: [String]
    /// Schema 1 free clip name. Never edited nor converted; shown as legacy information.
    var clipName: String
    var fileName: String
    var tcIn: String
    var tcOut: String
    var notes: String
    var technicalNotes: String
    var cameraNotes: String
    var createdAt: Date
    var updatedAt: Date
    var revision = 1
    var roll: Roll?
    // Schema 2 additions are optional so version 1 stores migrate without inventing values.
    var label: String?
    var cardOrder: Int?
    var snapshotData: Data?
    var sheet: ShotSheet?
    init(number: Int, sheet: ShotSheet, roll: Roll, cardOrder: Int) {
        id = UUID(); scene = sheet.scene; shot = sheet.shot; self.number = number
        settings = CaptureSettings(); statusValues = []
        clipName = ""; fileName = ""; tcIn = ""; tcOut = ""
        notes = ""; technicalNotes = ""; cameraNotes = ""
        createdAt = Date(); updatedAt = Date()
        label = ""; self.cardOrder = cardOrder
        snapshotData = SettingsCoding.encode(sheet.settings)
        self.roll = roll; self.sheet = sheet
    }
    var isCircle: Bool { statusValues.contains(TakeStatus.circle.rawValue) }
    var labelText: String { label ?? "" }
    /// Settings when the take was created. Later sheet edits never change it.
    var snapshot: [String: String] { SettingsCoding.decode(snapshotData) ?? settings.sheetValues }
    var displayTitle: String { "\(scene) / \(shot) · \(TakeLabel.title(number: number, label: labelText))" }

    static func precedesOnCard(_ a: TakeEntry, _ b: TakeEntry) -> Bool {
        (a.cardOrder ?? Int.max, a.createdAt, a.id.uuidString) < (b.cardOrder ?? Int.max, b.createdAt, b.id.uuidString)
    }
}
