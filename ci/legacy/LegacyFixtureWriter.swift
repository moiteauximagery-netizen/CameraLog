import XCTest
import SwiftData
@testable import CameraLog

/// Not part of the current project. CI copies this file into commit 241fd6e — the code of the
/// IPA installed before shot sheets — so that the shipped code itself writes a real store.
/// The current test suite then opens that store (testOpeningAStoreWrittenByTheShippedVersion).
@MainActor final class LegacyFixtureWriter: XCTestCase {
    func testWriteFixture() throws {
        guard let directory = ProcessInfo.processInfo.environment["CAMERALOG_V1_FIXTURE"] else {
            throw XCTSkip("CAMERALOG_V1_FIXTURE is not set")
        }
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var ids: [String] = []
        do {
            let container = try CameraLogStore.makeContainer(url: folder.appendingPathComponent("legacy.store"))
            let repo = CameraLogRepository(context: container.mainContext)
            let production = try repo.addProduction(name: "Prod v1")
            let day = try repo.addDay(to: production, number: 3, date: Date())
            let camera = try repo.addCamera(to: production, name: "A")
            let report = try repo.addReport(to: day, camera: camera)
            let a010 = try repo.addRoll(to: report, name: "A010", card: "CARD 7")
            let a011 = try repo.addRoll(to: report, name: "A011")

            var shotA = TakeDraft()
            shotA.scene = "14"; shotA.shot = "A"; shotA.number = 1
            shotA.settings.lensName = "50mm"; shotA.settings.filters = ["ND 0.6"]
            shotA.clipName = "A010C001_typed"
            ids.append(try repo.addTake(to: a010, draft: shotA).id.uuidString)
            Thread.sleep(forTimeInterval: 0.05)

            shotA.number = 2; shotA.clipName = ""; shotA.statuses = [.vfx]
            let circled = try repo.addTake(to: a010, draft: shotA)
            try repo.toggleCircle(circled)
            ids.append(circled.id.uuidString)
            Thread.sleep(forTimeInterval: 0.05)

            var shotB = TakeDraft()
            shotB.scene = "14"; shotB.shot = "B"; shotB.number = 1
            shotB.settings.lensName = "85mm"; shotB.settings.iso = 1280; shotB.notes = "note v1"
            ids.append(try repo.addTake(to: a010, draft: shotB).id.uuidString)
            Thread.sleep(forTimeInterval: 0.05)

            // Card changed during the shot: 14/B continues on A011.
            shotB.number = 2; shotB.notes = ""
            ids.append(try repo.addTake(to: a011, draft: shotB).id.uuidString)
        }
        let data = try JSONEncoder().encode(ids)
        try data.write(to: folder.appendingPathComponent("ids.json"))
    }
}
