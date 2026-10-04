import XCTest

/// Drives the real interface on the simulator with the LES OMBRES sample in memory.
final class CameraLogUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor private func openReport() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
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

    private func wait(_ element: XCUIElement, value: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "Expected value \(value), got \(String(describing: element.value))", file: file, line: line)
    }

    @MainActor func testTapEditsInNormalModeAndCirclesInCircleMode() throws {
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

        // Normal mode: touching a take opens its label editor and never circles it.
        first.tap()
        let editor = app.navigationBars["T01"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        attach(app, "3 Edition du libellé")
        app.buttons["label-FC"].tap()
        editor.buttons["Enregistrer"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        wait(first, value: "non cerclée")
        XCTAssertTrue(first.label.contains("FC"), first.label)

        // Circle mode: touching toggles Circle immediately, without opening the editor.
        let mode = app.buttons["circle-mode"]
        mode.tap()
        wait(mode, value: "activé")
        first.tap()
        wait(first, value: "cerclée")
        XCTAssertFalse(app.navigationBars["T01 · FC"].exists)
        attach(app, "4 Mode cerclage")
        first.tap()
        wait(first, value: "non cerclée")
        XCTAssertTrue(first.label.contains("FC"), "Circle does not change the label")

        // Leaving circle mode restores editing.
        mode.tap()
        wait(mode, value: "désactivé")
        first.tap()
        XCTAssertTrue(app.navigationBars["T01 · FC"].waitForExistence(timeout: 5))
        app.navigationBars["T01 · FC"].buttons["Annuler"].tap()

        // + creates the next take of the sheet and the next clip of the card (24/04 holds C004).
        app.buttons["add-take"].tap()
        let fourth = app.buttons["take-4"]
        XCTAssertTrue(fourth.waitForExistence(timeout: 5))
        XCTAssertTrue(fourth.label.contains("C005"), fourth.label)
        attach(app, "5 T04 ajoutée")
    }

    @MainActor func testNewSheetShowsSuggestionsWithoutFillingFields() throws {
        let app = openReport()
        app.buttons["new-sheet"].tap()
        let acceptAll = app.buttons["accept-all"]
        XCTAssertTrue(acceptAll.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accept-lens"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["sheet-state"].firstMatch.label, "Rien d’enregistré")
        attach(app, "6 Nouvelle fiche, suggestions en gris")

        app.buttons["accept-lens"].tap()
        XCTAssertFalse(app.buttons["accept-lens"].exists)
        XCTAssertEqual(app.textFields["field-lens"].value as? String, "35mm")
        acceptAll.tap()
        XCTAssertFalse(app.buttons["accept-all"].exists)
        attach(app, "7 Tout reprendre")
    }
}
