import XCTest
import SwiftData
@testable import CameraLog

/// Not part of the current project. CI copies this file into commit 90ec24a — the code of IPA
/// build 18, with production kits (schema 3) — so that the shipped code itself writes a real store.
/// The current test suite then opens it (testOpeningAStoreWrittenByBuild18).
@MainActor final class Build18FixtureWriter: XCTestCase {
    func testWriteFixture() throws {
        guard let directory = ProcessInfo.processInfo.environment["CAMERALOG_V3_FIXTURE"] else {
            throw XCTSkip("CAMERALOG_V3_FIXTURE is not set")
        }
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var ids: [String] = []
        do {
            let container = try CameraLogStore.makeContainer(url: folder.appendingPathComponent("build18.store"))
            let repo = CameraLogRepository(context: container.mainContext)
            let production = try repo.addProduction(name: "Prod build 18")
            try repo.updateProduction(production, name: "Prod build 18", client: "", director: "Réal", cinematographer: "DOP",
                start: production.startDate, end: nil, projectNumber: "", notes: "",
                lensKit: ["25 mm", "50 mm"], filterKit: [FilterFamily(name: "ND", grades: ["0.3", "0.6"])])
            let day = try repo.addDay(to: production, number: 7, date: Date(), location: "Forêt")
            let report = try repo.addNextCamera(to: day)

            var shot = SheetDraft()
            shot[.scene] = "31"; shot[.shot] = "A"; shot[.roll] = "A2"
            shot[.lens] = "50 mm"; shot[.tStop] = "2.8 ⅓"; shot[.filters] = "ND 0.6"
            let sheet = try repo.saveSheet(shot, sheet: nil, in: report)
            let first = try repo.addNextTake(to: sheet)
            let falseClip = try repo.addNextTake(to: sheet)
            try repo.renameTake(falseClip, typed: "FC")
            let third = try repo.addNextTake(to: sheet)
            try repo.renameTake(third, typed: "2PU")
            try repo.toggleCircle(third)
            let roll = try XCTUnwrap(sheet.roll)
            try repo.updateRoll(roll, name: roll.name, card: "E", reel: "")
            ids = [first, falseClip, third].map(\.id.uuidString)
        }
        try JSONEncoder().encode(ids).write(to: folder.appendingPathComponent("ids.json"))
    }
}
