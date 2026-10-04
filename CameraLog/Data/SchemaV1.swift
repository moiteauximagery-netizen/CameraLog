import Foundation
import SwiftData

/// Exact copy of the schema shipped before shot sheets (IPA of 4 October 2026).
/// Frozen: SwiftData recognises existing stores by comparing these definitions.
/// Do not edit property names, types, optionality, relationships or delete rules.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Production.self, ShootDay.self, Camera.self, CameraReport.self, Roll.self, TakeEntry.self]
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
        init(name: String, report: CameraReport) {
            id = UUID(); self.name = name; self.report = report; createdAt = Date()
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
        /// Used by migration tests to recreate a version 1 store.
        init(scene: String, shot: String, number: Int, settings: CaptureSettings,
             statusValues: [String], clipName: String, roll: Roll) {
            id = UUID(); self.scene = scene; self.shot = shot; self.number = number
            self.settings = settings; self.statusValues = statusValues; self.clipName = clipName
            fileName = ""; tcIn = ""; tcOut = ""; notes = ""; technicalNotes = ""; cameraNotes = ""
            createdAt = Date(); updatedAt = Date(); self.roll = roll
        }
    }
}
