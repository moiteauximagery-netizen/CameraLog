import XCTest
import SwiftData
@testable import CameraLog

@MainActor final class CameraLogTests: XCTestCase {
    private func setupStore() throws -> (ModelContainer, CameraLogRepository) {
        let container = try CameraLogStore.makeContainer(inMemory: true)
        return (container, CameraLogRepository(context: container.mainContext))
    }
    private func report(_ repo: CameraLogRepository) throws -> (Production, CameraReport) {
        let production = try repo.addProduction(name: "Test")
        let day = try repo.addDay(to: production, number: 12, date: Date())
        let camera = try repo.addCamera(to: production, name: "A", model: "Custom body")
        return (production, try repo.addReport(to: day, camera: camera))
    }
    private func sheetDraft(_ scene: String, _ shot: String, roll: String,
                            _ settings: [SheetField: String] = [:]) -> SheetDraft {
        var draft = SheetDraft()
        draft[.scene] = scene; draft[.shot] = shot; draft[.roll] = roll
        for (field, value) in settings { draft[field] = value }
        return draft
    }
    private func codes(_ roll: Roll) -> [String] {
        roll.clipSequence.map { "\($0.shot)\($0.number)\($0.labelText)=\(ClipCode.code(roll.clipNumbers[$0.id] ?? 0))" }
    }
    private func temporaryStoreURL() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("test.store"))
    }

    func testHierarchyAndCreation() throws {
        let (container, repo) = try setupStore()
        let (production, report) = try report(repo)
        XCTAssertEqual(production.days.count, 1)
        XCTAssertEqual(production.cameras.count, 1)
        XCTAssertEqual(production.days.first?.reports.count, 1)
        XCTAssertEqual(report.camera?.model, "Custom body")
        let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010"), sheet: nil, in: report)
        let take = try repo.addNextTake(to: sheet)
        XCTAssertEqual(take.roll?.report?.day?.production?.id, production.id)
        XCTAssertEqual(take.sheet?.id, sheet.id)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TakeEntry>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ShotSheet>()), 1)
    }

    func testSuggestionIsDisplayedButNeverSaved() throws {
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        let previous = try repo.saveSheet(sheetDraft("14", "A", roll: "A010",
            [.lens: "50 mm", .iso: "800", .whiteBalance: "5600", .filters: "ND 0.6"]), sheet: nil, in: report)
        try repo.addNextTake(to: previous)

        var draft = repo.newSheetDraft(for: report)
        XCTAssertTrue(draft.values.isEmpty, "Suggestions must leave the fields really empty")
        XCTAssertEqual(draft.suggestion(.lens), "50 mm")
        XCTAssertEqual(draft.suggestion(.iso), "800")
        XCTAssertEqual(draft.suggestion(.whiteBalance), "5600")
        XCTAssertEqual(draft.suggestion(.filters), "ND 0.6")
        XCTAssertEqual(draft.suggestion(.roll), "A010")
        XCTAssertEqual(draft.suggestion(.shot), "B", "The next plan is proposed, not imposed")
        XCTAssertTrue(draft.isPending(.lens))
        XCTAssertNil(draft.savedContent[SheetField.lens.rawValue])

        draft[.scene] = "14"; draft[.shot] = "B"; draft[.roll] = "A010"
        let sheet = try repo.saveSheet(draft, sheet: nil, in: report)
        XCTAssertEqual(sheet.settings, [:], "Unaccepted suggestions must not be saved")
        let take = try repo.addNextTake(to: sheet)
        XCTAssertEqual(take.snapshot, [:])
        let reopened = repo.draft(for: sheet, in: report)
        XCTAssertEqual(reopened.value(.lens), "")
        XCTAssertTrue(reopened.isPending(.lens), "Still shown greyed out when the sheet is reopened")
    }

    func testAcceptingASuggestionAndTypingAnotherValue() throws {
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        try repo.saveSheet(sheetDraft("14", "A", roll: "A010",
            [.lens: "50 mm", .iso: "800", .whiteBalance: "5600", .filters: "ND 0.6"]), sheet: nil, in: report)

        var draft = repo.newSheetDraft(for: report)
        draft.accept(.roll); draft.accept(.scene); draft[.shot] = "B"
        draft.accept(.iso)
        draft[.lens] = "85 mm"                       // typed over a pending suggestion, nothing to erase
        draft.accept(.lens)                          // no effect once a value is typed
        XCTAssertEqual(draft.value(.lens), "85 mm")
        XCTAssertTrue(draft.isPending(.whiteBalance))

        var everything = draft
        everything.acceptAll()
        XCTAssertEqual(everything.value(.lens), "85 mm", "Tout reprendre never replaces a typed value")
        XCTAssertEqual(everything.value(.whiteBalance), "5600")
        XCTAssertEqual(everything.value(.filters), "ND 0.6")

        let sheet = try repo.saveSheet(draft, sheet: nil, in: report)
        XCTAssertEqual(sheet.settings, ["lens": "85 mm", "iso": "800"])
        XCTAssertEqual(sheet.roll?.name, "A010")
        XCTAssertEqual(sheet.scene, "14")
    }

    func testRollIsCreatedAutomaticallyAndSheetCanMove() throws {
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        XCTAssertTrue(report.rolls.isEmpty)
        let first = try repo.saveSheet(sheetDraft("14", "A", roll: "a010"), sheet: nil, in: report)
        XCTAssertEqual(report.rolls.count, 1)
        XCTAssertEqual(first.roll?.name, "A010")
        let second = try repo.saveSheet(sheetDraft("14", "B", roll: "A010"), sheet: nil, in: report)
        XCTAssertEqual(report.rolls.count, 1, "An existing roll of this camera and day is reused")
        XCTAssertEqual(second.roll?.id, first.roll?.id)
        XCTAssertThrowsError(try repo.saveSheet(sheetDraft("14", "a", roll: "A010"), sheet: nil, in: report))

        try repo.addNextTake(to: first); try repo.addNextTake(to: first)
        let moving = try repo.addNextTake(to: second)
        try repo.updateTake(moving, label: "PU", statuses: [], notes: "kept")
        try repo.toggleCircle(moving)
        let movingID = moving.id

        var draft = repo.draft(for: second, in: report)
        draft[.roll] = "A011"
        let preview = repo.previewRollChange(for: second, to: "A011", in: report)
        XCTAssertEqual(preview.map(\.to), ["A011 · C001"])
        XCTAssertEqual(preview.map(\.from), ["A010 · C003"])
        try repo.saveSheet(draft, sheet: second, in: report)

        XCTAssertEqual(report.rolls.count, 2)
        XCTAssertEqual(second.roll?.name, "A011")
        XCTAssertEqual(moving.id, movingID)
        XCTAssertEqual(moving.roll?.name, "A011")
        XCTAssertEqual(moving.labelText, "PU"); XCTAssertTrue(moving.isCircle); XCTAssertEqual(moving.notes, "kept")
        XCTAssertEqual(moving.roll?.clipNumbers[movingID], 1)
        XCTAssertEqual(first.roll?.clipCount, 2)

        // The same scene/shot may exist on two rolls (card change during the shot).
        let continued = try repo.saveSheet(sheetDraft("14", "A", roll: "A011"), sheet: nil, in: report)
        XCTAssertNotEqual(continued.id, first.id)
        XCTAssertEqual(report.rolls.count, 2)
    }

    func testTakesIncrementWithinASheet() throws {
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010"), sheet: nil, in: report)
        XCTAssertEqual(repo.nextTakeNumber(in: sheet), 1)
        let numbers = try (1...3).map { _ in try repo.addNextTake(to: sheet).number }
        XCTAssertEqual(numbers, [1, 2, 3])
        XCTAssertEqual(sheet.orderedTakes.map { TakeLabel.code($0.number) }, ["1", "2", "3"])
        let other = try repo.saveSheet(sheetDraft("14", "B", roll: "A010"), sheet: nil, in: report)
        XCTAssertEqual(try repo.addNextTake(to: other).number, 1)
    }

    func testClipSequenceAcrossSheetsAndRestartOnNewRoll() throws {
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        let a = try repo.saveSheet(sheetDraft("14", "A", roll: "A010"), sheet: nil, in: report)
        try repo.addNextTake(to: a); try repo.addNextTake(to: a)
        let b = try repo.saveSheet(sheetDraft("14", "B", roll: "A010"), sheet: nil, in: report)
        try repo.addNextTake(to: b)
        let falseClip = try repo.addNextTake(to: b)
        try repo.updateTake(falseClip, label: "FC", statuses: [], notes: "")
        try repo.addNextTake(to: b)
        let roll = try XCTUnwrap(a.roll)
        XCTAssertEqual(codes(roll), ["A1=C001", "A2=C002", "B1=C003", "B2FC=C004", "B3=C005"])
        XCTAssertEqual(roll.clipCount, 5)

        let c = try repo.saveSheet(sheetDraft("14", "C", roll: "A011"), sheet: nil, in: report)
        let take = try repo.addNextTake(to: c)
        XCTAssertEqual(c.roll?.clipNumbers[take.id], 1)
        XCTAssertEqual(roll.clipCount, 5, "A new card restarts its own sequence")
    }

    func testFalseClipKeepsItsPlaceAndIsIndependentFromCircle() throws {
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        let sheet = try repo.saveSheet(sheetDraft("14", "B", roll: "A010"), sheet: nil, in: report)
        try repo.addNextTake(to: sheet)
        let fc = try repo.addNextTake(to: sheet)
        try repo.updateTake(fc, label: " fc ", statuses: [TakeStatus.vfx.rawValue], notes: "")
        XCTAssertEqual(fc.labelText, "fc")
        try repo.updateTake(fc, label: "FC", statuses: [TakeStatus.vfx.rawValue], notes: "")
        XCTAssertEqual(TakeLabel.title(number: fc.number, label: fc.labelText), "2FC")
        XCTAssertFalse(fc.isCircle)
        try repo.toggleCircle(fc)
        XCTAssertEqual(fc.labelText, "FC")
        try repo.updateTake(fc, label: "PU", statuses: [], notes: "")
        XCTAssertTrue(fc.isCircle, "Changing the label keeps Circle")
        XCTAssertEqual(fc.number, 2)
        XCTAssertEqual(fc.roll?.clipNumbers[fc.id], 2)
        let next = try repo.addNextTake(to: sheet)
        XCTAssertEqual(next.number, 3)
        XCTAssertEqual(next.roll?.clipNumbers[next.id], 3)
    }

    func testLateInsertionShowsAndAppliesRenumbering() throws {
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        let a = try repo.saveSheet(sheetDraft("14", "A", roll: "A010"), sheet: nil, in: report)
        try repo.addNextTake(to: a); try repo.addNextTake(to: a)
        let b = try repo.saveSheet(sheetDraft("14", "B", roll: "A010"), sheet: nil, in: report)
        try repo.addNextTake(to: b); try repo.addNextTake(to: b)
        let roll = try XCTUnwrap(a.roll)

        let preview = repo.previewInsertion(on: roll, at: 3)
        XCTAssertEqual(preview.map { "\($0.from)→\($0.to)" }, ["C003→C004", "C004→C005"])
        XCTAssertTrue(repo.previewInsertion(on: roll, at: 5).isEmpty, "Appending renumbers nothing")
        XCTAssertEqual(codes(roll), ["A1=C001", "A2=C002", "B1=C003", "B2=C004"], "Preview changes nothing")

        XCTAssertThrowsError(try repo.insertTake(into: a, at: 3, number: 2), "Duplicate take number")
        let forgotten = try repo.insertTake(into: a, at: 3, number: 3)
        XCTAssertEqual(codes(roll), ["A1=C001", "A2=C002", "A3=C003", "B1=C004", "B2=C005"])
        XCTAssertEqual(roll.clipNumbers[forgotten.id], 3)
        for change in preview {
            XCTAssertEqual(roll.clipNumbers[change.id].map(ClipCode.code), change.to)
        }
        let after = try repo.addNextTake(to: b)
        XCTAssertEqual(roll.clipNumbers[after.id], 6)
    }

    func testTapEditsInNormalModeAndCirclesInCircleMode() throws {
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010"), sheet: nil, in: report)
        let take = try repo.addNextTake(to: sheet)
        try repo.updateTake(take, label: "PU", statuses: [TakeStatus.mos.rawValue], notes: "")

        XCTAssertEqual(try repo.tap(take, mode: .edit), .edit(take.id))
        XCTAssertFalse(take.isCircle, "Normal mode never circles")
        XCTAssertEqual(try repo.tap(take, mode: .circle), .toggleCircle(take.id))
        XCTAssertTrue(take.isCircle)
        XCTAssertEqual(try repo.tap(take, mode: .circle), .toggleCircle(take.id))
        XCTAssertFalse(take.isCircle)
        XCTAssertEqual(try repo.tap(take, mode: .circle), .toggleCircle(take.id))
        XCTAssertEqual(try repo.tap(take, mode: .edit), .edit(take.id))
        XCTAssertTrue(take.isCircle, "Leaving circle mode restores editing without touching Circle")
        XCTAssertEqual(take.labelText, "PU")
        XCTAssertTrue(take.statusValues.contains(TakeStatus.mos.rawValue))
    }

    func testTakeSnapshotsAreNotRewrittenBySheetEdits() throws {
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010", [.lens: "50 mm", .iso: "800"]),
                                       sheet: nil, in: report)
        let first = try repo.addNextTake(to: sheet)
        var draft = repo.draft(for: sheet, in: report)
        draft[.lens] = "85 mm"; draft[.iso] = ""
        try repo.saveSheet(draft, sheet: sheet, in: report)
        let second = try repo.addNextTake(to: sheet)
        XCTAssertEqual(first.snapshot, ["lens": "50 mm", "iso": "800"])
        XCTAssertEqual(second.snapshot, ["lens": "85 mm"])
        XCTAssertEqual(sheet.settings, ["lens": "85 mm"])
    }

    func testValidationDoesNotInsertInvalidRecords() throws {
        let (container, repo) = try setupStore()
        XCTAssertThrowsError(try repo.addProduction(name: "  "))
        let (production, report) = try report(repo)
        XCTAssertThrowsError(try repo.addDay(to: production, number: 12, date: Date()))
        XCTAssertThrowsError(try repo.addCamera(to: production, name: " a "))
        XCTAssertThrowsError(try repo.addReport(to: report.day!, camera: report.camera!))
        XCTAssertThrowsError(try repo.saveSheet(sheetDraft("14", "A", roll: " "), sheet: nil, in: report))
        XCTAssertThrowsError(try repo.saveSheet(sheetDraft("14", "A", roll: "A010", [.iso: "huit cents"]),
                                                sheet: nil, in: report))
        XCTAssertThrowsError(try repo.saveSheet(sheetDraft("14", "A", roll: "A010", [.shutter: "400"]),
                                                sheet: nil, in: report))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ShotSheet>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Roll>()), 0)
        let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010",
            [.whiteBalance: "5600K", .fps: "23,976", .shutter: "172.8°"]), sheet: nil, in: report)
        XCTAssertEqual(sheet.settings, ["whiteBalance": "5600", "fps": "23.976", "shutter": "172.8"])
    }

    func testDeletionPreviewAndCascade() throws {
        let (container, repo) = try setupStore()
        let (production, report) = try report(repo)
        let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010"), sheet: nil, in: report)
        let first = try repo.addNextTake(to: sheet)
        try repo.addNextTake(to: sheet)
        XCTAssertEqual(repo.previewDeletion(of: first).map(\.to), ["A010 · C001"])
        try repo.deleteTake(first)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TakeEntry>()), 1)
        try repo.deleteProduction(production)
        for count in [
            try container.mainContext.fetchCount(FetchDescriptor<Production>()),
            try container.mainContext.fetchCount(FetchDescriptor<ShootDay>()),
            try container.mainContext.fetchCount(FetchDescriptor<Camera>()),
            try container.mainContext.fetchCount(FetchDescriptor<CameraReport>()),
            try container.mainContext.fetchCount(FetchDescriptor<Roll>()),
            try container.mainContext.fetchCount(FetchDescriptor<ShotSheet>()),
            try container.mainContext.fetchCount(FetchDescriptor<TakeEntry>())
        ] { XCTAssertEqual(count, 0) }
    }

    func testDiskPersistenceAcrossContainers() throws {
        let (directory, url) = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        var savedID: UUID?
        do {
            let container = try CameraLogStore.makeContainer(url: url)
            let repo = CameraLogRepository(context: container.mainContext)
            let (_, report) = try report(repo)
            let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010", [.filters: "ND 0.6 + 1/8 BPM"]),
                                           sheet: nil, in: report)
            let take = try repo.addNextTake(to: sheet)
            try repo.updateTake(take, label: "FC", statuses: [], notes: "")
            try repo.toggleCircle(take); savedID = take.id
        }
        let reopened = try CameraLogStore.makeContainer(url: url)
        let takes = try reopened.mainContext.fetch(FetchDescriptor<TakeEntry>())
        XCTAssertEqual(takes.count, 1); XCTAssertEqual(takes.first?.id, savedID)
        XCTAssertEqual(takes.first?.snapshot["filters"], "ND 0.6 + 1/8 BPM")
        XCTAssertEqual(takes.first?.isCircle, true)
        XCTAssertEqual(takes.first?.labelText, "FC")
        XCTAssertEqual(takes.first?.sheet?.roll?.name, "A010")
        XCTAssertEqual(takes.first?.roll?.report?.camera?.name, "A")
    }

    /// A store written by the previous version (schema 1, unversioned, as shipped) must open,
    /// keep every take and identifier, and get sheets and clip order without touching old values.
    func testOpeningAStoreCreatedByThePreviousVersion() throws {
        let (directory, url) = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        var ids: [UUID] = []
        do {
            let schema = Schema([SchemaV1.Production.self, SchemaV1.ShootDay.self, SchemaV1.Camera.self,
                                 SchemaV1.CameraReport.self, SchemaV1.Roll.self, SchemaV1.TakeEntry.self])
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            let production = SchemaV1.Production(name: "Ancienne prod")
            context.insert(production)
            let day = SchemaV1.ShootDay(number: 3, date: Date(), production: production)
            context.insert(day)
            let camera = SchemaV1.Camera(name: "A", production: production)
            context.insert(camera)
            let report = SchemaV1.CameraReport(day: day, camera: camera)
            context.insert(report)
            let roll = SchemaV1.Roll(name: "A010", report: report)
            roll.card = "CARD 7"
            context.insert(roll)
            var fifty = CaptureSettings(); fifty.lensName = "50mm"; fifty.filters = ["ND 0.6"]
            var eightyFive = CaptureSettings(); eightyFive.lensName = "85mm"; eightyFive.iso = 1280
            let base = Date(timeIntervalSince1970: 1_790_000_000)
            let rows: [(String, String, Int, CaptureSettings, [String], String)] = [
                ("14", "A", 1, fifty, [], "A010C001_260924"),
                ("14", "A", 2, fifty, ["Circle", "VFX"], "A010C002_260924"),
                ("14", "B", 1, eightyFive, [], "")
            ]
            for (index, row) in rows.enumerated() {
                let take = SchemaV1.TakeEntry(scene: row.0, shot: row.1, number: row.2, settings: row.3,
                                              statusValues: row.4, clipName: row.5, roll: roll)
                take.createdAt = base.addingTimeInterval(Double(index) * 60)
                context.insert(take)
                ids.append(take.id)
            }
            try context.save()
        }

        let container = try CameraLogStore.makeContainer(url: url)
        let repo = CameraLogRepository(context: container.mainContext)
        let migrated = try repo.migrateLegacyTakes()
        XCTAssertEqual(migrated, 3)
        XCTAssertEqual(try repo.migrateLegacyTakes(), 0, "Migration is idempotent")

        let takes = try container.mainContext.fetch(FetchDescriptor<TakeEntry>())
        XCTAssertEqual(Set(takes.map(\.id)), Set(ids))
        let byID = Dictionary(uniqueKeysWithValues: takes.map { ($0.id, $0) })
        let first = try XCTUnwrap(byID[ids[0]]), second = try XCTUnwrap(byID[ids[1]]), third = try XCTUnwrap(byID[ids[2]])
        XCTAssertEqual(first.clipName, "A010C001_260924", "Typed clip names are preserved, not converted")
        XCTAssertEqual(third.clipName, "")
        XCTAssertEqual(first.settings.lensName, "50mm")
        XCTAssertEqual(third.settings.iso, 1280)
        XCTAssertEqual(Set(second.statusValues), ["Circle", "VFX"])
        XCTAssertEqual(first.labelText, "")
        XCTAssertEqual(first.snapshot["lens"], "50mm")
        XCTAssertEqual(first.snapshot["filters"], "ND 0.6")
        XCTAssertEqual(third.snapshot["iso"], "1280")

        let roll = try XCTUnwrap(first.roll)
        XCTAssertEqual(roll.card, "CARD 7")
        XCTAssertEqual(roll.currentSheets.count, 2)
        XCTAssertEqual(first.sheet?.id, second.sheet?.id)
        XCTAssertNotEqual(first.sheet?.id, third.sheet?.id)
        XCTAssertEqual(third.sheet?.settings["lens"], "85mm")
        XCTAssertEqual(roll.clipSequence.map(\.id), ids, "Clip order follows the original creation order")

        // New work continues the card sequence.
        let report = try XCTUnwrap(roll.report)
        let sheet = try XCTUnwrap(third.sheet)
        let added = try repo.addNextTake(to: sheet)
        XCTAssertEqual(added.number, 2)
        XCTAssertEqual(roll.clipNumbers[added.id], 4)
        XCTAssertEqual(repo.newSheetDraft(for: report).suggestion(.lens), "85mm")
        let production = try XCTUnwrap(report.day?.production)
        XCTAssertEqual(production.lensKit, [])
        XCTAssertEqual(production.filterKit, FilterFamily.defaultKit)
    }

    /// Store written in CI by the shipped code (commit 241fd6e, IPA of run 7), not by a replica.
    func testOpeningAStoreWrittenByTheShippedVersion() throws {
        guard let directory = ProcessInfo.processInfo.environment["CAMERALOG_V1_FIXTURE"] else {
            throw XCTSkip("The shipped-version store is produced by the CI workflow.")
        }
        let source = URL(fileURLWithPath: directory)
        let ids = try JSONDecoder().decode([String].self, from: Data(contentsOf: source.appendingPathComponent("ids.json")))
            .compactMap(UUID.init(uuidString:))
        XCTAssertEqual(ids.count, 4)
        // Work on a copy: the fixture itself must stay a version 1 store.
        let (copy, _) = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: copy) }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory) where name.hasPrefix("legacy.store") {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: copy.appendingPathComponent(name))
        }

        let container = try CameraLogStore.makeContainer(url: copy.appendingPathComponent("legacy.store"))
        let repo = CameraLogRepository(context: container.mainContext)
        XCTAssertEqual(try repo.migrateLegacyTakes(), 4)
        XCTAssertEqual(try repo.migrateLegacyTakes(), 0)

        let takes = try container.mainContext.fetch(FetchDescriptor<TakeEntry>())
        XCTAssertEqual(Set(takes.map(\.id)), Set(ids), "Every take and identifier is kept")
        let byID = Dictionary(uniqueKeysWithValues: takes.map { ($0.id, $0) })
        let t1 = try XCTUnwrap(byID[ids[0]]), t2 = try XCTUnwrap(byID[ids[1]])
        let t3 = try XCTUnwrap(byID[ids[2]]), t4 = try XCTUnwrap(byID[ids[3]])
        XCTAssertEqual(t1.clipName, "A010C001_typed")
        XCTAssertEqual(t1.settings.lensName, "50mm"); XCTAssertEqual(t1.settings.filters, ["ND 0.6"])
        XCTAssertTrue(t2.isCircle); XCTAssertTrue(t2.statusValues.contains("VFX"))
        XCTAssertEqual(t3.notes, "note v1"); XCTAssertEqual(t3.settings.iso, 1280)
        XCTAssertEqual(t3.snapshot["lens"], "85mm")
        XCTAssertEqual([t1, t2, t3, t4].map(\.labelText), ["", "", "", ""])

        let a010 = try XCTUnwrap(t1.roll), a011 = try XCTUnwrap(t4.roll)
        XCTAssertEqual(a010.card, "CARD 7")
        XCTAssertEqual(a010.clipSequence.map(\.id), [ids[0], ids[1], ids[2]])
        XCTAssertEqual(a011.clipNumbers[t4.id], 1, "Each card keeps its own sequence")
        XCTAssertEqual(a010.currentSheets.count, 2)
        XCTAssertEqual(a011.currentSheets.map(\.title), ["14 / B"], "Same shot on two rolls")
        XCTAssertEqual(t1.sheet?.id, t2.sheet?.id)

        let added = try repo.addNextTake(to: try XCTUnwrap(t1.sheet))
        XCTAssertEqual(added.number, 3)
        XCTAssertEqual(a010.clipNumbers[added.id], 4)

        // The migrated store reopens as a version 2 store.
        let reopened = try CameraLogStore.makeContainer(url: copy.appendingPathComponent("legacy.store"))
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<TakeEntry>()), 5)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<ShotSheet>()), 3)
    }

    /// Store written in CI by the code of IPA build 15 (commit 20df5d9, schema 2, shot sheets).
    func testOpeningAStoreWrittenByBuild15() throws {
        guard let directory = ProcessInfo.processInfo.environment["CAMERALOG_V2_FIXTURE"] else {
            throw XCTSkip("The build 15 store is produced by the CI workflow.")
        }
        let source = URL(fileURLWithPath: directory)
        let ids = try JSONDecoder().decode([String].self, from: Data(contentsOf: source.appendingPathComponent("ids.json")))
            .compactMap(UUID.init(uuidString:))
        XCTAssertEqual(ids.count, 6)
        let (copy, _) = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: copy) }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory) where name.hasPrefix("build15.store") {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: copy.appendingPathComponent(name))
        }
        let url = copy.appendingPathComponent("build15.store")
        let container = try CameraLogStore.makeContainer(url: url)
        let repo = CameraLogRepository(context: container.mainContext)
        XCTAssertEqual(try repo.migrateLegacyTakes(), 0, "Build 15 takes already belong to sheets")

        let takes = try container.mainContext.fetch(FetchDescriptor<TakeEntry>())
        XCTAssertEqual(Set(takes.map(\.id)), Set(ids))
        let byID = Dictionary(uniqueKeysWithValues: takes.map { ($0.id, $0) })
        let a1 = try XCTUnwrap(byID[ids[0]]), a2 = try XCTUnwrap(byID[ids[1]]), a3 = try XCTUnwrap(byID[ids[2]])
        let b1 = try XCTUnwrap(byID[ids[3]]), a4 = try XCTUnwrap(byID[ids[4]]), c1 = try XCTUnwrap(byID[ids[5]])
        XCTAssertEqual(a2.labelText, "FC")
        XCTAssertTrue(a3.isCircle); XCTAssertTrue(a3.statusValues.contains("VFX")); XCTAssertEqual(a3.notes, "bonne")
        XCTAssertEqual(a1.snapshot["lens"], "50mm", "Snapshots are kept")
        XCTAssertEqual(a1.sheet?.settings["lens"], "85mm")
        XCTAssertEqual(a4.number, 4)
        let a010 = try XCTUnwrap(a1.roll)
        XCTAssertEqual(a010.clipSequence.map(\.id), [a1.id, a2.id, a4.id, a3.id, b1.id], "Card order is kept")
        XCTAssertEqual(c1.roll?.name, "A011"); XCTAssertEqual(c1.roll?.clipNumbers[c1.id], 1)
        let day = try XCTUnwrap(a010.report?.day)
        XCTAssertEqual(day.location, "Studio 2")
        let production = try XCTUnwrap(day.production)
        XCTAssertEqual(production.lensKit, [])
        XCTAssertEqual(production.filterKit, FilterFamily.defaultKit)

        try repo.updateProduction(production, name: production.name, client: "", director: "", cinematographer: "",
                                  start: production.startDate, end: nil, projectNumber: "", notes: "",
                                  lensKit: ["25 mm", "50 mm"], filterKit: [FilterFamily(name: "ND", grades: ["0.3"])])
        let added = try repo.addNextTake(to: try XCTUnwrap(a1.sheet))
        XCTAssertEqual(added.number, 5)
        XCTAssertEqual(a010.clipNumbers[added.id], 6)
        let reopened = try CameraLogStore.makeContainer(url: url)
        let productions = try reopened.mainContext.fetch(FetchDescriptor<Production>())
        XCTAssertEqual(productions.first?.lensKit, ["25 mm", "50 mm"])
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<TakeEntry>()), 7)
    }

    func testNextPlanIsIncremented() {
        XCTAssertEqual(ShotIncrement.next(after: "2"), "3")
        XCTAssertEqual(ShotIncrement.next(after: "09"), "10")
        XCTAssertEqual(ShotIncrement.next(after: "03"), "04")
        XCTAssertEqual(ShotIncrement.next(after: "99"), "100")
        XCTAssertEqual(ShotIncrement.next(after: "A"), "B")
        XCTAssertEqual(ShotIncrement.next(after: "14A"), "14B")
        XCTAssertEqual(ShotIncrement.next(after: "3b"), "3c")
        XCTAssertNil(ShotIncrement.next(after: "Z"))
        XCTAssertNil(ShotIncrement.next(after: " "))
    }

    func testAddingCamerasUsesTheNextLetter() throws {
        let (_, repo) = try setupStore()
        let production = try repo.addProduction(name: "P")
        let day = try repo.addDay(to: production, number: 1, date: Date())
        let names = try (1...3).map { _ in try repo.addNextCamera(to: day).camera?.name }
        XCTAssertEqual(names, ["A", "B", "C"])
        XCTAssertEqual(day.reports.count, 3)
        let b = try XCTUnwrap(day.reports.first { $0.camera?.name == "B" })
        try repo.deleteReport(b)
        XCTAssertEqual(try repo.addNextCamera(to: day).camera?.name, "B", "A free letter is reused")
        let next = try repo.addDay(to: production, number: 2, date: Date())
        let reused = try repo.addNextCamera(to: next)
        XCTAssertEqual(reused.camera?.name, "A")
        XCTAssertEqual(production.cameras.count, 3, "Day 2 reuses the production camera A")
        XCTAssertEqual(CameraNaming.next(used: ["a", "B"]), "C")
    }

    func testEveryCommitChangesTheRevisionReadByScreens() throws {
        let (_, repo) = try setupStore()
        let start = repo.revision
        let production = try repo.addProduction(name: "P")
        let day = try repo.addDay(to: production, number: 1, date: Date())
        try repo.addNextCamera(to: day)
        XCTAssertEqual(repo.revision, start + 3)
    }

    func testEditingDayCameraAndRoll() throws {
        let (_, repo) = try setupStore()
        let (production, report) = try report(repo)
        let day = try XCTUnwrap(report.day)
        try repo.updateDay(day, number: 12, date: day.date, location: "Plateau 5", unit: "2nd unit", notes: "Pluie")
        XCTAssertEqual(day.location, "Plateau 5"); XCTAssertEqual(day.unit, "2nd unit")
        try repo.addDay(to: production, number: 13, date: Date())
        XCTAssertThrowsError(try repo.updateDay(day, number: 13, date: day.date, location: "", unit: "", notes: ""))
        XCTAssertEqual(day.number, 12)

        let camera = try XCTUnwrap(report.camera)
        try repo.updateCamera(camera, name: "A", manufacturer: "ARRI", model: "Alexa 35", serialNumber: "123")
        XCTAssertEqual(camera.model, "Alexa 35")
        try repo.addCamera(to: production, name: "B")
        XCTAssertThrowsError(try repo.updateCamera(camera, name: "b", manufacturer: "", model: "", serialNumber: ""))
        XCTAssertEqual(camera.name, "A")

        let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010"), sheet: nil, in: report)
        let take = try repo.addNextTake(to: sheet)
        try repo.saveSheet(sheetDraft("15", "A", roll: "A011"), sheet: nil, in: report)
        let roll = try XCTUnwrap(sheet.roll)
        XCTAssertThrowsError(try repo.updateRoll(roll, name: "a011", card: "", reel: ""))
        try repo.updateRoll(roll, name: "a012", card: "CARD 3", reel: "R1")
        XCTAssertEqual(sheet.roll?.name, "A012"); XCTAssertEqual(roll.card, "CARD 3")
        XCTAssertEqual(roll.clipNumbers[take.id], 1, "Renaming a roll keeps its clip numbers")
    }

    func testLensAndFilterKitsOfTheProduction() throws {
        XCTAssertEqual(LensKit.parse("18, 25 32;50mm\n75"), ["18 mm", "25 mm", "32 mm", "50mm", "75 mm"])
        XCTAssertEqual(LensKit.merged(["50 mm", "18 mm"], adding: ["25 mm", "50 MM", "Macro"]),
                       ["18 mm", "25 mm", "50 mm", "Macro"])
        let (_, repo) = try setupStore()
        let (production, report) = try report(repo)
        XCTAssertEqual(production.lensKit, [], "No series: the lens field has no menu")
        XCTAssertEqual(production.filterKit, FilterFamily.defaultKit)
        try repo.updateProduction(production, name: "Test", client: "", director: "", cinematographer: "",
            start: production.startDate, end: nil, projectNumber: "", notes: "",
            lensKit: ["18 mm", "50 mm"], filterKit: [FilterFamily(name: "ND", grades: ["0.3", "0.6"]),
                                                     FilterFamily(name: "  ", grades: [])])
        XCTAssertEqual(report.day?.production?.lensKit, ["18 mm", "50 mm"])
        XCTAssertEqual(production.filterKit, [FilterFamily(name: "ND", grades: ["0.3", "0.6"])], "Unnamed families are dropped")
        try repo.updateProduction(production, name: "Test", client: "", director: "", cinematographer: "",
            start: production.startDate, end: nil, projectNumber: "", notes: "", lensKit: [], filterKit: [])
        XCTAssertEqual(production.filterKit, [], "An emptied kit stays empty")
        XCTAssertEqual(FilterFamily.parseGrades("1/8, 1/4 ;1/2"), ["1/8", "1/4", "1/2"])
    }

    func testFilterAndApertureSelection() {
        var text = FilterSelection.apply(family: "ND", grade: "0.6", to: "")
        XCTAssertEqual(text, "ND 0.6")
        text = FilterSelection.apply(family: "BPM", grade: "1/4", to: text)
        XCTAssertEqual(text, "ND 0.6 + BPM 1/4")
        text = FilterSelection.apply(family: "ND", grade: "0.9", to: text)
        XCTAssertEqual(text, "ND 0.9 + BPM 1/4", "Another grade of the same family replaces it")
        text = FilterSelection.apply(family: "IRND", grade: "0.3", to: text)
        XCTAssertEqual(text, "ND 0.9 + BPM 1/4 + IRND 0.3", "IRND is not ND")
        text = FilterSelection.apply(family: "ND", grade: "0.9", to: text)
        XCTAssertEqual(text, "BPM 1/4 + IRND 0.3", "Choosing the selected value removes it")
        text = FilterSelection.apply(family: "POLA", grade: "", to: text)
        XCTAssertEqual(text, "BPM 1/4 + IRND 0.3 + POLA")
        XCTAssertTrue(FilterSelection.isSelected(family: "POLA", grade: "", in: text))
        XCTAssertEqual(Aperture.rows.count, 10)
        XCTAssertEqual(Aperture.rows.first, ["1", "1 ⅓", "1 ⅔"])
        XCTAssertEqual(Aperture.rows[3], ["2.8", "2.8 ⅓", "2.8 ⅔"])
        XCTAssertEqual(Aperture.rows.last, ["22"])
    }

    func testInlineTakeLabel() throws {
        XCTAssertEqual(TakeLabel.label(fromTyped: "4PU", number: 4), "PU")
        XCTAssertEqual(TakeLabel.label(fromTyped: " FC ", number: 4), "FC")
        XCTAssertEqual(TakeLabel.label(fromTyped: "4", number: 4), "")
        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010"), sheet: nil, in: report)
        let take = try repo.addNextTake(to: sheet)
        try repo.updateTake(take, label: "", statuses: [TakeStatus.mos.rawValue], notes: "note")
        try repo.toggleCircle(take)
        let revision = take.revision
        try repo.updateLabel(take, label: TakeLabel.label(fromTyped: "1PU", number: 1))
        XCTAssertEqual(TakeLabel.title(number: take.number, label: take.labelText), "1PU")
        XCTAssertTrue(take.isCircle); XCTAssertEqual(take.notes, "note")
        XCTAssertTrue(take.statusValues.contains(TakeStatus.mos.rawValue))
        XCTAssertEqual(take.revision, revision + 1)
        try repo.updateLabel(take, label: "PU")
        XCTAssertEqual(take.revision, revision + 1, "Unchanged label: nothing written")
    }

    func testRollLetterIsImposedByTheCamera() throws {
        XCTAssertEqual(RollNaming.prefix(forCamera: "a"), "A")
        XCTAssertNil(RollNaming.prefix(forCamera: "Drone"))
        XCTAssertEqual(RollNaming.suffix(of: "A010", prefix: "A"), "010")
        XCTAssertEqual(RollNaming.suffix(of: "B12", prefix: "A"), "B12")
        XCTAssertEqual(RollNaming.compose(prefix: "A", suffix: "011"), "A011")
        XCTAssertEqual(RollNaming.compose(prefix: "A", suffix: "a011"), "a011")
        XCTAssertEqual(RollNaming.compose(prefix: "A", suffix: " "), "")
        XCTAssertEqual(RollNaming.normalized("a1", camera: "A"), "A001")
        XCTAssertEqual(RollNaming.normalized("A12", camera: "A"), "A012")
        XCTAssertEqual(RollNaming.normalized("A0105", camera: "A"), "A0105")
        XCTAssertEqual(RollNaming.normalized("x7", camera: "Drone"), "X7")
        XCTAssertEqual(RollNaming.normalized("7", camera: "B"), "B007")
        XCTAssertEqual(RollNaming.normalized("7", camera: "Drone"), "7")

        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        var draft = sheetDraft("14", "A", roll: RollNaming.compose(prefix: "A", suffix: "1"))
        let sheet = try repo.saveSheet(draft, sheet: nil, in: report)
        XCTAssertEqual(sheet.roll?.name, "A001")
        draft = sheetDraft("14", "B", roll: "A001")
        XCTAssertEqual(try repo.saveSheet(draft, sheet: nil, in: report).roll?.id, sheet.roll?.id)
        XCTAssertEqual(report.rolls.count, 1)
    }

    func testTakeBoxCanBeRewrittenEntirely() throws {
        XCTAssertEqual(TakeLabel.parse("4PU")?.number, 4); XCTAssertEqual(TakeLabel.parse("4PU")?.label, "PU")
        XCTAssertEqual(TakeLabel.parse("FC")?.number, 0); XCTAssertEqual(TakeLabel.parse("FC")?.label, "FC")
        XCTAssertEqual(TakeLabel.parse(" 12 ")?.number, 12); XCTAssertEqual(TakeLabel.parse("12")?.label, "")
        XCTAssertNil(TakeLabel.parse("  "))
        XCTAssertEqual(TakeLabel.title(number: 0, label: "FC"), "FC")
        XCTAssertEqual(TakeLabel.title(number: 0, label: ""), "—")

        let (_, repo) = try setupStore()
        let (_, report) = try report(repo)
        let sheet = try repo.saveSheet(sheetDraft("14", "A", roll: "A010"), sheet: nil, in: report)
        try repo.addNextTake(to: sheet)
        let falseClip = try repo.addNextTake(to: sheet)
        try repo.toggleCircle(falseClip)
        try repo.renameTake(falseClip, typed: "FC")
        XCTAssertEqual(falseClip.number, 0, "A false clip frees its take number")
        XCTAssertEqual(falseClip.labelText, "FC")
        XCTAssertTrue(falseClip.isCircle, "Circle is independent")
        XCTAssertEqual(falseClip.roll?.clipNumbers[falseClip.id], 2, "The clip keeps its place on the card")
        let next = try repo.addNextTake(to: sheet)
        XCTAssertEqual(next.number, 2, "The next take takes back the freed number")
        XCTAssertEqual(next.roll?.clipNumbers[next.id], 3)

        XCTAssertThrowsError(try repo.renameTake(falseClip, typed: "2"), "Duplicate take number")
        XCTAssertEqual(falseClip.number, 0)
        try repo.renameTake(next, typed: "2PU")
        XCTAssertEqual(TakeLabel.title(number: next.number, label: next.labelText), "2PU")
        try repo.renameTake(next, typed: "   ")
        XCTAssertEqual(next.labelText, "PU", "An empty box changes nothing")

        try repo.applyQuickLabel(next, "FC")
        XCTAssertEqual(next.number, 0)
        try repo.renameTake(next, typed: "3")
        try repo.applyQuickLabel(next, "PU")
        XCTAssertEqual(next.number, 3); XCTAssertEqual(next.labelText, "PU")
        try repo.applyQuickLabel(next, "")
        XCTAssertEqual(TakeLabel.title(number: next.number, label: next.labelText), "3")
    }

    func testProjectSearchFiltersByDayCameraRollSequenceAndStatus() throws {
        let (_, repo) = try setupStore()
        let (production, report) = try report(repo)
        let a = try repo.saveSheet(sheetDraft("14", "A", roll: "A010", [.lens: "50 mm"]), sheet: nil, in: report)
        try repo.addNextTake(to: a)
        let a2 = try repo.addNextTake(to: a)
        try repo.toggleCircle(a2)
        let b = try repo.saveSheet(sheetDraft("15", "A", roll: "A011", [.lens: "85 mm"]), sheet: nil, in: report)
        let b1 = try repo.addNextTake(to: b)
        try repo.renameTake(b1, typed: "FC")
        let day13 = try repo.addDay(to: production, number: 13, date: Date())
        try repo.addNextCamera(to: day13)
        let camB = try repo.addNextCamera(to: day13)
        let c = try repo.saveSheet(sheetDraft("14", "B", roll: "1"), sheet: nil, in: camB)
        let c1 = try repo.addNextTake(to: c)
        try repo.toggleCircle(c1)

        var filters = SearchFilters()
        XCTAssertFalse(filters.isActive)
        var result = ProjectSearch.run(production, filters: filters)
        XCTAssertEqual(result.hits.count, 3)
        XCTAssertEqual(result.options[.day], ["12", "13"])
        XCTAssertEqual(result.options[.camera], ["A", "B"])
        XCTAssertEqual(result.options[.roll], ["A010", "A011", "B001"], "Roll typed « 1 » on CAM B")
        XCTAssertEqual(result.options[.scene], ["14", "15"])
        XCTAssertEqual(result.options[.status], ["Circle", "FC"])

        filters.toggle("13", in: .day)
        XCTAssertEqual(ProjectSearch.run(production, filters: filters).hits.map(\.sheet.id), [c.id])
        filters.toggle("12", in: .day)
        XCTAssertEqual(ProjectSearch.run(production, filters: filters).hits.count, 3, "Values of one filter add up")
        XCTAssertEqual(filters.summary(.day), "Jour : 12, 13")
        filters.toggle("14", in: .scene)
        XCTAssertEqual(ProjectSearch.run(production, filters: filters).hits.map(\.sheet.id), [a.id, c.id])
        filters.toggle("Circle", in: .status)
        result = ProjectSearch.run(production, filters: filters)
        XCTAssertEqual(result.hits.map(\.sheet.id), [a.id, c.id])
        XCTAssertEqual(result.hits.first?.takes.map(\.id), [a2.id], "Only the circled takes are listed")
        XCTAssertEqual(result.takeCount, 2); XCTAssertEqual(result.circleCount, 2)
        XCTAssertEqual(filters.summary(.status), "Statut : Cerclée")

        filters.clearAll()
        filters.toggle("FC", in: .status)
        result = ProjectSearch.run(production, filters: filters)
        XCTAssertEqual(result.hits.map(\.sheet.id), [b.id]); XCTAssertEqual(result.takeCount, 1)
        filters.clearAll()
        filters.text = "85"
        XCTAssertEqual(ProjectSearch.run(production, filters: filters).hits.map(\.sheet.id), [b.id])
        filters.text = "14A"
        XCTAssertEqual(ProjectSearch.run(production, filters: filters).hits.map(\.sheet.id), [a.id])
        filters.clearAll()
        filters.toggle("B001", in: .roll)
        XCTAssertEqual(ProjectSearch.run(production, filters: filters).hits.map(\.sheet.id), [c.id])
        filters.toggle("B001", in: .roll)
        filters.toggle("A", in: .camera)
        XCTAssertEqual(ProjectSearch.run(production, filters: filters).hits.map(\.sheet.id), [a.id, b.id])
    }

    /// Same columns, units and value forms as a real ZoeLog export (files received on 4 October 2026).
    func testExportsMatchTheZoeLogFilesReadBySilverstack() throws {
        let (_, repo) = try setupStore()
        let production = try repo.addProduction(name: "Prod")
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        let day = try repo.addDay(to: production, number: 12, date: date, location: "Plateau 3")
        let report = try repo.addNextCamera(to: day)
        let a = try repo.saveSheet(sheetDraft("14", "A", roll: "1", [.lens: "50 mm", .tStop: "2.8 ⅓",
            .filters: "ND 0.6 + BPM 1/4", .iso: "800", .whiteBalance: "5600", .fps: "23,976", .shutter: "172.8"]),
            sheet: nil, in: report)
        let t1 = try repo.addNextTake(to: a)
        try repo.toggleCircle(t1)
        try repo.renameTake(try repo.addNextTake(to: a), typed: "2PU")
        let b = try repo.saveSheet(sheetDraft("24", "3", roll: "A001", [.lens: "35mm"]), sheet: nil, in: report)
        let fc = try repo.addNextTake(to: b)
        try repo.updateTake(fc, label: "", statuses: [], notes: "batterie")
        try repo.renameTake(fc, typed: "FC")

        let csv = ReportExport.csv(day: day, reports: [report])
        XCTAssertFalse(csv.hasSuffix("\n"), "No final line break, like ZoeLog")
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], #""Scene","Date","Camera","Roll","Take","Clip","Circled","Lens","Filters","Stop","Focus","Lens Height","Color Temp","FPS","Shutter","ISO","Time Code","Tilt","Lut","Aspect Ratio","Format","Resolution","Description","Notes","Origin Date","Take Origin""#)
        XCTAssertTrue(lines[1].hasPrefix(#""14A","2026-09-24","A","A001","1","1","true","50mm","ND 0.6 + BPM 1/4","T2.8 1/3",,,"5600K","23.976fps","172.8 degrees","800EI",,,,,,,,,""#), lines[1])
        XCTAssertTrue(lines[2].hasPrefix(#""14A","2026-09-24","A","A001","2PU","2","false","#), lines[2])
        XCTAssertTrue(lines[3].hasPrefix(#""24/3","2026-09-24","A","A001","FC","3","false","35mm",,,,,,,,,,,,,,,,"batterie","#), lines[3])
        XCTAssertEqual(lines[1].components(separatedBy: ",\"2026").count, 4, "Date, Origin Date and Take Origin")

        let object = try JSONSerialization.jsonObject(with: ReportExport.json(production: production, day: day, reports: [report]))
        let root = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(root["production_title"] as? String, "Prod")
        let rolls = try XCTUnwrap(root["reports"] as? [[String: Any]])
        XCTAssertEqual(rolls.first?["roll"] as? String, "A001")
        XCTAssertEqual(rolls.first?["camera"] as? String, "A")
        XCTAssertEqual(rolls.first?["shooting_date"] as? String, "2026-09-24")
        let entries = try XCTUnwrap(rolls.first?["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.map { $0["scene"] as? String }, ["14A", "24/3"])
        let takes = try XCTUnwrap(entries.first?["takes"] as? [[String: Any]])
        XCTAssertEqual(takes.map { $0["name"] as? String }, ["1", "2PU"])
        XCTAssertEqual(takes.map { $0["clip"] as? Int }, [1, 2])
        XCTAssertEqual(takes.map { $0["circled"] as? Bool }, [true, false])
        let log = try XCTUnwrap(entries.first?["log_data"] as? [String: String])
        XCTAssertEqual(log["Shutter"], "172.8∢"); XCTAssertEqual(log["Stop"], "T2.8 1/3")
        XCTAssertTrue(entries.first?["slate"] is NSNull)

        let pdf = ReportPDF.make(production: production, day: day, reports: [report])
        XCTAssertEqual(String(decoding: pdf.prefix(4), as: UTF8.self), "%PDF")
        XCTAssertEqual(ReportExport.baseName(production: production, day: day, camera: report.camera),
                       "Prod-DAY12-2026-09-24-CAM-A")
        XCTAssertEqual(ReportExport.sceneLabel(scene: "24", shot: ""), "24")
    }

    func testSampleData() throws {
        let (container, repo) = try setupStore()
        try SampleData.load(into: repo)
        let takes = try container.mainContext.fetch(FetchDescriptor<TakeEntry>())
        XCTAssertEqual(takes.count, 4)
        XCTAssertEqual(takes.filter(\.isCircle).count, 1)
        XCTAssertEqual(Set(takes.map(\.scene)), ["24"])
        XCTAssertEqual(Set(takes.compactMap { $0.snapshot["lens"] }), ["35mm", "50mm", "75mm"])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Roll>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ShotSheet>()), 2)
    }
}
