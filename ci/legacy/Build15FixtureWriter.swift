import XCTest
import SwiftData
@testable import CameraLog

/// Not part of the current project. CI copies this file into commit 20df5d9 — the code of IPA
/// build 15, with shot sheets (schema 2) — so that the shipped code itself writes a real store.
/// The current test suite then opens it (testOpeningAStoreWrittenByBuild15).
@MainActor final class Build15FixtureWriter: XCTestCase {
    func testWriteFixture() throws {
        guard let directory = ProcessInfo.processInfo.environment["CAMERALOG_V2_FIXTURE"] else {
            throw XCTSkip("CAMERALOG_V2_FIXTURE is not set")
        }
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var ids: [String] = []
        do {
            let container = try CameraLogStore.makeContainer(url: folder.appendingPathComponent("build15.store"))
            let repo = CameraLogRepository(context: container.mainContext)
            let production = try repo.addProduction(name: "Prod build 15")
            let day = try repo.addDay(to: production, number: 4, date: Date(), location: "Studio 2")
            let camera = try repo.addCamera(to: production, name: "A")
            let report = try repo.addReport(to: day, camera: camera)

            var shotA = SheetDraft()
            shotA[.scene] = "14"; shotA[.shot] = "A"; shotA[.roll] = "A010"
            shotA[.lens] = "50mm"; shotA[.iso] = "800"
            let sheetA = try repo.saveSheet(shotA, sheet: nil, in: report)
            let a1 = try repo.addNextTake(to: sheetA)
            let a2 = try repo.addNextTake(to: sheetA)
            try repo.updateTake(a2, label: "FC", statuses: [], notes: "")
            let a3 = try repo.addNextTake(to: sheetA)
            try repo.updateTake(a3, label: "", statuses: [TakeStatus.vfx.rawValue], notes: "bonne")
            try repo.toggleCircle(a3)

            var shotB = SheetDraft()
            shotB[.scene] = "14"; shotB[.shot] = "B"; shotB[.roll] = "A010"
            let sheetB = try repo.saveSheet(shotB, sheet: nil, in: report)
            let b1 = try repo.addNextTake(to: sheetB)

            // Forgotten take 4 of 14/A inserted before C003.
            let a4 = try repo.insertTake(into: sheetA, at: 3, number: 4)

            // Lens changed on the sheet after the takes: snapshots keep 50mm.
            shotA[.lens] = "85mm"
            try repo.saveSheet(shotA, sheet: sheetA, in: report)

            var shotC = SheetDraft()
            shotC[.scene] = "15"; shotC[.shot] = "A"; shotC[.roll] = "A011"
            let c1 = try repo.addNextTake(to: repo.saveSheet(shotC, sheet: nil, in: report))

            ids = [a1, a2, a3, b1, a4, c1].map(\.id.uuidString)
        }
        try JSONEncoder().encode(ids).write(to: folder.appendingPathComponent("ids.json"))
    }
}
