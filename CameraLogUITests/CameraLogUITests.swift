import XCTest

/// Drives the real interface on the simulator with the LES OMBRES sample in memory.
final class CameraLogUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    @MainActor private func openReport() -> XCUIApplication {
        let app = launch()
        let resume = app.buttons["resume-report"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        resume.tap()
        return app
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func wait(_ element: XCUIElement, value: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "Expected value \(value), got \(String(describing: element.value))", file: file, line: line)
    }

    @MainActor private func wait(_ element: XCUIElement, labelContains text: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "Expected label containing \(text), got \(element.label)", file: file, line: line)
    }

    @MainActor private func waitForKeyboardFocus(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "Field should have focus",
                       file: file, line: line)
    }

    @MainActor func testTakeBoxEditsInNormalModeAndCirclesInCircleMode() throws {
        let app = openReport()
        attach(app, "1 Liste groupée par roll")
        let row = app.buttons["sheet-24-03"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let first = app.buttons["take-C001"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        if !first.isHittable { app.swipeUp() }
        attach(app, "2 Fiche 24-03")
        wait(first, value: "non cerclée")
        wait(app.buttons["take-C002"], value: "cerclée")

        // Normal mode: touching a take turns its box into a text field holding « 1 ».
        first.tap()
        let field = app.textFields["take-label-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        wait(field, value: "1")
        waitForKeyboardFocus(field)
        attach(app, "3 Édition dans la case")
        app.typeText("PU\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        wait(first, labelContains: "Prise 1, clip C001, libellé PU")
        wait(first, value: "non cerclée")

        // Circle mode: touching toggles Circle immediately, without editing.
        let mode = app.buttons["circle-mode"]
        mode.tap()
        wait(mode, value: "activé")
        first.tap()
        wait(first, value: "cerclée")
        XCTAssertFalse(app.textFields["take-label-field"].exists)
        attach(app, "4 Mode cerclage")
        first.tap()
        wait(first, value: "non cerclée")
        XCTAssertTrue(first.label.contains("PU"), "Circle does not change the label")

        // Leaving circle mode: the whole box can be rewritten, number included.
        mode.tap()
        wait(mode, value: "désactivé")
        first.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        wait(field, value: "1PU")
        waitForKeyboardFocus(field)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "FC\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        wait(first, labelContains: "Sans numéro de prise, clip C001, libellé FC")

        // + creates the next take of the sheet and the next clip of the card (24/04 holds C004).
        app.buttons["add-take"].tap()
        let added = app.buttons["take-C005"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertTrue(added.label.contains("Prise 4"), added.label)
        attach(app, "5 Prise 4 ajoutée")

        // Long press: quick labels and deletion after confirmation.
        added.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["PU"].waitForExistence(timeout: 5))
        attach(app, "6 Menu appui long")
        app.buttons["Supprimer"].tap()
        let confirm = app.buttons["Supprimer la prise"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(added.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["take-C003"].exists)
    }

    @MainActor func testNewSheetSuggestionsPickersAndAutomaticSaving() throws {
        let app = openReport()
        app.buttons["new-sheet"].tap()
        let acceptAll = app.buttons["accept-all"]
        XCTAssertTrue(acceptAll.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accept-lens"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accept-shot"].exists, "The next plan is proposed")
        XCTAssertTrue(app.descendants(matching: .any)["sheet-state"].firstMatch.label.contains("Rien"))
        XCTAssertFalse(app.buttons["picker-lens"].exists, "No lens series in the sample: no menu")
        XCTAssertFalse(app.buttons["save-sheet"].exists, "No save button any more")
        attach(app, "7 Nouvelle fiche, suggestions en gris")

        app.buttons["accept-lens"].tap()
        XCTAssertTrue(app.buttons["accept-lens"].waitForNonExistence(timeout: 5))
        wait(app.textFields["field-lens"], value: "35mm")

        // Diaph first (written at once), then an optional fraction that closes the menu.
        app.buttons["picker-tStop"].tap()
        let stop = app.buttons["stop-2.8"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        wait(app.textFields["field-tStop"], value: "2.8")
        attach(app, "8 Menu diaph")
        app.buttons["fraction-+⅓"].tap()
        wait(app.textFields["field-tStop"], value: "2.8 ⅓")
        XCTAssertTrue(app.buttons["stop-2.8"].waitForNonExistence(timeout: 5), "The fraction closes the menu")

        // Filters: family then grade, combined; another ND grade replaces the first.
        app.buttons["picker-filters"].tap()
        XCTAssertTrue(app.buttons["ND-0.6"].waitForExistence(timeout: 5))
        app.buttons["ND-0.6"].tap()
        app.buttons["BPM-1/4"].tap()
        app.buttons["ND-0.9"].tap()
        attach(app, "9 Menu filtres")
        app.buttons["filters-done"].tap()
        wait(app.textFields["field-filters"], value: "ND 0.9 + BPM 1/4")

        // VFX switch reveals camera height, focus distance and tilt.
        XCTAssertFalse(app.textFields["field-focus"].exists)
        let vfx = app.switches["vfx-toggle"]
        for _ in 0..<8 where !(vfx.exists && vfx.isHittable) { app.swipeUp() }
        vfx.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["field-lensHeight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["field-focus"].exists)
        XCTAssertTrue(app.textFields["field-tilt"].exists)
        attach(app, "9b Bloc VFX")
        for _ in 0..<8 where !(acceptAll.exists && acceptAll.isHittable) { app.swipeDown() }

        // Tout reprendre fills scene, plan 05 and roll: the roll box shows only 004 after the A.
        acceptAll.tap()
        XCTAssertTrue(app.buttons["accept-all"].waitForNonExistence(timeout: 5))
        wait(app.textFields["field-roll"], value: "004")
        let state = app.descendants(matching: .any)["sheet-state"].firstMatch
        wait(state, labelContains: "Fiche enregistrée")
        attach(app, "10 Enregistrée automatiquement")

        // Saved without a button: back to the list and reopen.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let saved = app.buttons["sheet-24-05"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        wait(app.textFields["field-tStop"], value: "2.8 ⅓")
        wait(app.textFields["field-filters"], value: "ND 0.9 + BPM 1/4")
    }

    @MainActor func testProjectSearchWithFiltersAndTakesMode() throws {
        let app = launch()
        let production = app.buttons["production-LES OMBRES"]
        XCTAssertTrue(production.waitForExistence(timeout: 15))
        production.tap()

        let status = app.buttons["facet-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        attach(app, "12 Page projet avec filtres")
        status.tap()
        let circle = app.buttons["option-Circle"]
        XCTAssertTrue(circle.waitForExistence(timeout: 5))
        circle.tap()
        attach(app, "13 Filtre statut")
        app.buttons["facet-done"].tap()

        XCTAssertTrue(app.buttons["result-sheet-24-03"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["result-sheet-24-04"].exists)
        wait(app.staticTexts["results-count"], labelContains: "1 fiche(s) · 1 prise(s) · 1 cerclée(s)")
        attach(app, "14 Résultats fiches")

        app.buttons["Prises"].tap()
        let take = app.buttons["result-take-A004-C002"]
        XCTAssertTrue(take.waitForExistence(timeout: 5))
        attach(app, "15 Résultats prises")
        take.tap()
        XCTAssertTrue(app.buttons["take-C002"].waitForExistence(timeout: 5), "The sheet opens directly")
    }

    @MainActor func testNewCameraAndDayEditsAppearImmediately() throws {
        let app = launch()
        let production = app.buttons["production-LES OMBRES"]
        XCTAssertTrue(production.waitForExistence(timeout: 15))
        production.tap()
        let day = app.buttons["day-12"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()

        XCTAssertTrue(app.buttons["camera-A"].waitForExistence(timeout: 5))
        app.buttons["add-camera"].tap()
        XCTAssertTrue(app.buttons["camera-B"].waitForExistence(timeout: 5), "No need to leave the page")
        app.buttons["add-camera"].tap()
        XCTAssertTrue(app.buttons["camera-C"].waitForExistence(timeout: 5))
        attach(app, "10 Caméras A B C")

        // Camera B: native ISO set from its swipe action, shown at once on the day.
        app.buttons["camera-B"].swipeLeft()
        let editCamera = app.buttons["edit-camera-B"]
        XCTAssertTrue(editCamera.waitForExistence(timeout: 5))
        editCamera.tap()
        let iso = app.textFields["native-iso"]
        XCTAssertTrue(iso.waitForExistence(timeout: 5))
        attach(app, "10b Couleur et ISO natif")
        iso.tap()
        iso.typeText("1280")
        app.navigationBars["CAM B"].buttons["Enregistrer"].tap()
        wait(app.buttons["camera-B"], labelContains: "ISO 1280")

        app.buttons["edit-day"].tap()
        let location = app.textFields["day-location"]
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        location.tap()
        location.typeText(" bis")
        app.navigationBars["Modifier la journée"].buttons["Enregistrer"].tap()
        let details = app.staticTexts["day-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        wait(details, labelContains: "Plateau 3 bis")
        attach(app, "11 Lieu modifié")

        app.buttons["export-day"].tap()
        let share = app.descendants(matching: .any)["share-export"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), "PDF and CSV are ready to share")
        attach(app, "12 Export")
    }
}
