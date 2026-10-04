import Foundation
import SwiftData

/// Exact copy of the schema shipped with production kits (IPA builds 16 to 18, commit 90ec24a).
/// Frozen: SwiftData recognises existing stores by comparing these definitions.
/// Do not edit property names, types, optionality, relationships or delete rules.
enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Production.self, ShootDay.self, Camera.self, CameraReport.self, Roll.self, ShotSheet.self, TakeEntry.self]
    }

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
        var lensKitData: Data?
        var filterKitData: Data?
        init(name: String) {
            id = UUID(); self.name = name; startDate = Date()
            createdAt = Date(); updatedAt = Date(); defaults = CaptureSettings()
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
        init(name: String, production: Production) {
            id = UUID(); self.name = name; self.production = production; defaults = production.defaults
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
    }

    @Model final class Roll {
        @Attribute(.unique) var id: UUID
        var name: String
        var card = ""
        var reel = ""
        var createdAt: Date
        var report: CameraReport?
        @Relationship(deleteRule: .cascade, inverse: \TakeEntry.roll) var takes: [TakeEntry] = []
        @Relationship(deleteRule: .cascade, inverse: \ShotSheet.roll) var sheets: [ShotSheet] = []
        init(name: String, report: CameraReport) {
            id = UUID(); self.name = name; self.report = report; createdAt = Date()
        }
    }

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
    }

    @Model final class TakeEntry {
        @Attribute(.unique) var id: UUID
        var scene: String
        var shot: String
        var number: Int
        var settings: CaptureSettings
        var statusValues: [String]
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
        var label: String?
        var cardOrder: Int?
        var snapshotData: Data?
        var sheet: ShotSheet?
        init(number: Int, sheet: ShotSheet, roll: Roll) {
            id = UUID(); scene = sheet.scene; shot = sheet.shot; self.number = number
            settings = CaptureSettings(); statusValues = []
            clipName = ""; fileName = ""; tcIn = ""; tcOut = ""
            notes = ""; technicalNotes = ""; cameraNotes = ""
            createdAt = Date(); updatedAt = Date(); self.roll = roll; self.sheet = sheet
        }
    }
}
