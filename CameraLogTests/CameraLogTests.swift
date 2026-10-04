import XCTest
import SwiftData
@testable import CameraLog

@MainActor final class CameraLogTests: XCTestCase {
    private func setupStore() throws -> (ModelContainer, CameraLogRepository) {
        let container = try CameraLogStore.makeContainer(inMemory: true)
        return (container, CameraLogRepository(context: container.mainContext))
    }
    private func hierarchy(_ repo: CameraLogRepository) throws -> (Production, CameraReport, Roll) {
        let production = try repo.addProduction(name: "Test")
        let day = try repo.addDay(to: production, number: 12, date: Date())
        let camera = try repo.addCamera(to: production, name: "A", model: "Custom body")
        let report = try repo.addReport(to: day, camera: camera)
        return (production, report, try repo.addRoll(to: report, name: "A004"))
    }

    func testHierarchyAndCreation() throws {
        let (container, repo) = try setupStore()
        let (production, report, roll) = try hierarchy(repo)
        XCTAssertEqual(production.days.count, 1)
        XCTAssertEqual(production.cameras.count, 1)
        XCTAssertEqual(production.days.first?.reports.count, 1)
        XCTAssertEqual(report.rolls.count, 1)
        XCTAssertEqual(report.camera?.model, "Custom body")
        let take = try repo.addTake(to: roll, draft: TakeDraft())
        XCTAssertEqual(roll.takes.count, 1)
        XCTAssertEqual(take.roll?.report?.day?.production?.id, production.id)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TakeEntry>()), 1)
    }

    func testSmartFillCopiesSettingsButClearsPerTakeData() {
        var previous = TakeDraft()
        previous.scene = "24A"; previous.shot = "03"; previous.number = 4
        previous.settings.lensName = "50mm"; previous.settings.filters = ["ND 0.6", "1/8 BPM"]
        previous.settings.fps = 23.976; previous.settings.lut = "Show LUT"
        previous.statuses = [.circle, .vfx]; previous.notes = "Only this take"
        previous.tcIn = "01:00:00:00"; previous.clipName = "clip001"
        let next = SmartFill.next(after: previous, defaults: CaptureSettings())
        XCTAssertEqual(next.scene, "24A"); XCTAssertEqual(next.shot, "03"); XCTAssertEqual(next.number, 5)
        XCTAssertEqual(next.settings, previous.settings)
        XCTAssertTrue(next.statuses.isEmpty); XCTAssertTrue(next.notes.isEmpty)
        XCTAssertTrue(next.tcIn.isEmpty); XCTAssertTrue(next.clipName.isEmpty)
    }

    func testRollChangeRetainsSettingsAndCameraHistoryIsIsolated() throws {
        let (_, repo) = try setupStore()
        let (production, report, firstRoll) = try hierarchy(repo)
        var draft = TakeDraft(); draft.settings.iso = 1250; draft.number = 3
        try repo.addTake(to: firstRoll, draft: draft)
        let secondRoll = try repo.addRoll(to: report, name: "A005")
        let next = repo.nextDraft(for: report)
        XCTAssertEqual(next.settings.iso, 1250); XCTAssertEqual(next.number, 4)
        let take = try repo.addTake(to: secondRoll, draft: next)
        XCTAssertEqual(take.roll?.name, "A005")
        let cameraB = try repo.addCamera(to: production, name: "B")
        let reportB = try repo.addReport(to: report.day!, camera: cameraB)
        XCTAssertEqual(repo.nextDraft(for: reportB).settings.iso, 800)
        XCTAssertEqual(repo.nextDraft(for: reportB).number, 1)
    }

    func testCirclePreservesOtherStatusesAndHistoricSettings() throws {
        let (_, repo) = try setupStore()
        let (_, report, roll) = try hierarchy(repo)
        var draft = TakeDraft(); draft.statuses = [.vfx, .mos]
        let take = try repo.addTake(to: roll, draft: draft)
        try repo.toggleCircle(take)
        XCTAssertTrue(take.isCircle)
        try repo.toggleCircle(take)
        XCTAssertFalse(take.isCircle)
        XCTAssertEqual(Set(take.statusValues), Set(["VFX", "MOS"]))
        XCTAssertEqual(take.revision, 3)
        var defaults = report.camera!.defaults; defaults.iso = 320
        report.camera!.defaults = defaults
        XCTAssertEqual(take.settings.iso, 800)
    }

    func testEditingTakeKeepsIdentityAndRejectsDuplicateNumber() throws {
        let (_, repo) = try setupStore()
        let (_, _, roll) = try hierarchy(repo)
        let first = try repo.addTake(to: roll, draft: TakeDraft())
        var secondDraft = TakeDraft(); secondDraft.number = 2
        let second = try repo.addTake(to: roll, draft: secondDraft)
        let id = first.id
        var edited = first.draft
        edited.settings.lensName = "75mm"
        edited.notes = "Bonne prise"
        edited.statuses = [.circle]
        try repo.updateTake(first, draft: edited)
        XCTAssertEqual(first.id, id)
        XCTAssertEqual(first.settings.lensName, "75mm")
        XCTAssertEqual(first.notes, "Bonne prise")
        XCTAssertTrue(first.isCircle)
        XCTAssertEqual(first.revision, 2)
        edited.number = second.number
        XCTAssertThrowsError(try repo.updateTake(first, draft: edited))
        XCTAssertEqual(first.number, 1)
    }

    func testValidationDoesNotInsertInvalidRecords() throws {
        let (container, repo) = try setupStore()
        XCTAssertThrowsError(try repo.addProduction(name: "  "))
        let (production, report, roll) = try hierarchy(repo)
        XCTAssertThrowsError(try repo.addDay(to: production, number: 12, date: Date()))
        XCTAssertThrowsError(try repo.addCamera(to: production, name: " a "))
        XCTAssertThrowsError(try repo.addReport(to: report.day!, camera: report.camera!))
        XCTAssertThrowsError(try repo.addRoll(to: report, name: "A004"))
        var draft = TakeDraft(); draft.settings.fps = 0
        XCTAssertThrowsError(try repo.addTake(to: roll, draft: draft))
        draft.settings.fps = 24
        try repo.addTake(to: roll, draft: draft)
        XCTAssertThrowsError(try repo.addTake(to: roll, draft: draft))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TakeEntry>()), 1)
    }

    func testDeletionAndCascade() throws {
        let (container, repo) = try setupStore()
        let (production, _, roll) = try hierarchy(repo)
        let take = try repo.addTake(to: roll, draft: TakeDraft())
        try repo.deleteTake(take)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TakeEntry>()), 0)
        try repo.addTake(to: roll, draft: TakeDraft())
        try repo.deleteProduction(production)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Production>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ShootDay>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Camera>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CameraReport>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Roll>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TakeEntry>()), 0)
    }

    func testDiskPersistenceAcrossContainers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        var savedID: UUID?
        do {
            let container = try CameraLogStore.makeContainer(url: url)
            let repo = CameraLogRepository(context: container.mainContext)
            let (_, _, roll) = try hierarchy(repo)
            var draft = TakeDraft(); draft.settings.filters = ["ND 0.6", "1/8 BPM"]
            let take = try repo.addTake(to: roll, draft: draft)
            try repo.toggleCircle(take); savedID = take.id
        }
        let reopened = try CameraLogStore.makeContainer(url: url)
        let takes = try reopened.mainContext.fetch(FetchDescriptor<TakeEntry>())
        XCTAssertEqual(takes.count, 1); XCTAssertEqual(takes.first?.id, savedID)
        XCTAssertEqual(takes.first?.settings.filters, ["ND 0.6", "1/8 BPM"])
        XCTAssertEqual(takes.first?.isCircle, true)
        XCTAssertEqual(takes.first?.roll?.report?.camera?.name, "A")
    }

    func testSampleData() throws {
        let (container, repo) = try setupStore()
        try SampleData.load(into: repo)
        let takes = try container.mainContext.fetch(FetchDescriptor<TakeEntry>())
        XCTAssertEqual(takes.count, 4)
        XCTAssertEqual(takes.filter(\.isCircle).count, 1)
        XCTAssertEqual(Set(takes.map(\.scene)), ["24"])
        XCTAssertEqual(Set(takes.map { $0.settings.lensName }), ["35mm", "50mm", "75mm"])
    }
}
