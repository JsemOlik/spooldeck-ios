import XCTest

/// Walks through the main screens against a running Spooldeck server.
/// Run with `TEST_RUNNER_SPOOLDECK_SERVER=http://localhost:3000 TEST_RUNNER_SPOOLDECK_TOKEN=<token> xcodebuild test …`;
/// skipped when no server is configured.
final class SpooldeckUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let server = env["SPOOLDECK_SERVER"], let token = env["SPOOLDECK_TOKEN"] else {
            throw XCTSkip("Set SPOOLDECK_SERVER and SPOOLDECK_TOKEN to run UI tests against a server.")
        }
        app = XCUIApplication()
        app.launchArguments = ["-serverURL", server, "-debugToken", token, "-scanOpensLogUsage", "NO"]
        app.launch()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testMainFlow() throws {
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 10))
        snapshot("1-dashboard")

        // Spools → first spool → log usage with a localised decimal.
        app.tabBars.buttons["Spools"].tap()
        XCTAssertTrue(app.navigationBars["Spools"].waitForExistence(timeout: 5))
        let firstSpool = app.collectionViews.cells.firstMatch
        XCTAssertTrue(firstSpool.waitForExistence(timeout: 10))
        snapshot("2-spools")
        firstSpool.tap()

        let logButton = app.buttons["Log usage"]
        XCTAssertTrue(logButton.waitForExistence(timeout: 10))
        snapshot("3-spool-detail")
        logButton.tap()
        let grams = app.textFields["Grams used"]
        XCTAssertTrue(grams.waitForExistence(timeout: 5))
        grams.tap()
        grams.typeText("1,5")
        app.textFields["Print name (optional)"].tap()
        app.textFields["Print name (optional)"].typeText("UI test print")
        snapshot("4-log-usage")
        app.navigationBars.buttons["Log"].tap()
        XCTAssertTrue(app.staticTexts["UI test print"].waitForExistence(timeout: 10))

        app.buttons["Weigh in"].tap()
        XCTAssertTrue(app.textFields["Scale reading"].waitForExistence(timeout: 5))
        snapshot("5-weigh-in")
        app.navigationBars.buttons["Cancel"].tap()

        app.swipeUp()
        app.swipeUp()
        snapshot("6-spool-detail-bottom")

        // Filaments → first filament.
        app.tabBars.buttons["Filaments"].tap()
        let firstFilament = app.collectionViews.cells.firstMatch
        XCTAssertTrue(firstFilament.waitForExistence(timeout: 10))
        snapshot("7-filaments")
        firstFilament.tap()
        XCTAssertTrue(app.staticTexts["Stats"].waitForExistence(timeout: 10) || app.staticTexts["STATS"].exists)
        snapshot("8-filament-detail")

        // Scan → type a code that doesn't exist.
        app.tabBars.buttons["Scan"].tap()
        let codeField = app.textFields["Link or 6-character code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText("ZZZZZZ\n")
        XCTAssertTrue(app.staticTexts["No spool with code ZZZZZZ."].waitForExistence(timeout: 10))
        snapshot("9-scan")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snapshot("10-settings")
    }
}
