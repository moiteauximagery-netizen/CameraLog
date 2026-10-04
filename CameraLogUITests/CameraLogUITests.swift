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

    @MainActor func testTakeBoxEditsInNormalModeAndCirclesInCircleMode() throws {
        let app = openReport()
        attach(app, "1 Liste groupée par roll")
        let row = app.buttons["sheet-24-03"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let first = app.buttons["take-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        if !first.isHittable { app.swipeUp() }
        attach(app, "2 Fiche 24-03")
        wait(first, value: "non cerclée")
        wait(app.buttons["take-2"], value: "cerclée")

        // Normal mode: touching a take turns its box into a text field, no page opens.
        first.tap()
        let field = app.textFields["take-label-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        attach(app, "3 Édition dans la case")
        let quick = app.buttons["quick-FC"]
        if quick.waitForExistence(timeout: 2) {
            quick.tap()
        } else {
            field.tap()
            field.typeText("1FC\n")
        }
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        wait(first, labelContains: "FC")
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
        XCTAssertTrue(first.label.contains("FC"), "Circle does not change the label")

        // Leaving circle mode restores editing in the box.
        mode.tap()
        wait(mode, value: "désactivé")
        first.tap()
        XCTAssertTrue(app.textFields["take-label-field"].waitForExistence(timeout: 5))
        app.textFields["take-label-field"].typeText("\n")
        XCTAssertTrue(app.textFields["take-label-field"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("FC"))

        // + creates the next take of the sheet and the next clip of the card (24/04 holds C004).
        app.buttons["add-take"].tap()
        let fourth = app.buttons["take-4"]
        XCTAssertTrue(fourth.waitForExistence(timeout: 5))
        XCTAssertTrue(fourth.label.contains("C005"), fourth.label)
        attach(app, "5 Prise 4 ajoutée")

        // Details stay reachable with a long press: delete take 4 after confirmation.
        fourth.press(forDuration: 1.0)
        let details = app.buttons["Statuts, commentaire, suppression"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        XCTAssertTrue(app.navigationBars["4"].waitForExistence(timeout: 5))
        let deleteButton = app.buttons["Supprimer cette prise"]
        for _ in 0..<6 where !(deleteButton.exists && deleteButton.isHittable) { app.swipeUp() }
        deleteButton.tap()
        let confirm = app.buttons["Supprimer"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(fourth.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["take-3"].exists)
    }

    @MainActor func testNewSheetSuggestionsAndQuickPickers() throws {
        let app = openReport()
        app.buttons["new-sheet"].tap()
        let acceptAll = app.buttons["accept-all"]
        XCTAssertTrue(acceptAll.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accept-lens"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accept-shot"].exists, "The next plan is proposed")
        XCTAssertTrue(app.descendants(matching: .any)["sheet-state"].firstMatch.label.contains("Rien"))
        XCTAssertFalse(app.buttons["picker-lens"].exists, "No lens series in the sample: no menu")
        attach(app, "6 Nouvelle fiche, suggestions en gris")

        app.buttons["accept-lens"].tap()
        XCTAssertTrue(app.buttons["accept-lens"].waitForNonExistence(timeout: 5))
        wait(app.textFields["field-lens"], value: "35mm")

        // Diaph: full stops and thirds, one tap.
        app.buttons["picker-tStop"].tap()
        let third = app.buttons["value-2.8 ⅓"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        attach(app, "7 Menu diaph")
        third.tap()
        wait(app.textFields["field-tStop"], value: "2.8 ⅓")

        // Filters: family then grade, combined; another ND grade replaces the first.
        app.buttons["picker-filters"].tap()
        XCTAssertTrue(app.buttons["ND-0.6"].waitForExistence(timeout: 5))
        app.buttons["ND-0.6"].tap()
        app.buttons["BPM-1/4"].tap()
        app.buttons["ND-0.9"].tap()
        attach(app, "8 Menu filtres")
        app.buttons["filters-done"].tap()
        wait(app.textFields["field-filters"], value: "ND 0.9 + BPM 1/4")

        acceptAll.tap()
        XCTAssertTrue(app.buttons["accept-all"].waitForNonExistence(timeout: 5))
        attach(app, "9 Tout reprendre")
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
    }
}
