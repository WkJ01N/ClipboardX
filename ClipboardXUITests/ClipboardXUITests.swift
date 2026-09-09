import XCTest

final class ClipboardXUITests: XCTestCase {
    func testApplicationLaunches() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5) || app.state == .runningBackground)
    }

    func testFloatAnimationMovesSelectedCardToTop() {
        assertSelectedCardMovesToTop(animationStyle: "浮动飞升")
    }

    func testFadeAnimationMovesSelectedCardToTopAndRestoresVisibility() {
        assertSelectedCardMovesToTop(animationStyle: "闪现淡入")
    }

    func testClosingLastWindowKeepsMenuBarAgentRunning() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-animation"]
        app.launch()
        let testWindow = app.windows["ClipboardX UI Tests"]
        XCTAssertTrue(testWindow.waitForExistence(timeout: 5))

        app.typeKey("w", modifierFlags: .command)
        let closeSettled = expectation(description: "Window close settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { closeSettled.fulfill() }
        wait(for: [closeSettled], timeout: 1)

        XCTAssertNotEqual(app.state, .notRunning)
    }

    func testSourceFilterWidthTracksOnlyTheCurrentSelection() {
        let longApplicationName = "An Extremely Long Application Name Used for Source Width Testing"
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-source-filter", "-favoritesEnabled", "NO"]
        app.launch()

        let sourceMenu = app.descendants(matching: .any)["source-filter-menu"]
        XCTAssertTrue(sourceMenu.waitForExistence(timeout: 5))
        let defaultWidth = sourceMenu.frame.width
        XCTAssertLessThan(defaultWidth, 120)

        sourceMenu.click()
        let longSourceItem = app.menuItems[longApplicationName]
        XCTAssertTrue(longSourceItem.waitForExistence(timeout: 2))
        longSourceItem.click()

        let selectedLongSource = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                sourceMenu.exists && sourceMenu.frame.width > defaultWidth
                    && sourceMenu.frame.width <= 200
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selectedLongSource], timeout: 3), .completed)

        sourceMenu.click()
        let allSourcesItem = app.menuItems["全部来源"]
        XCTAssertTrue(allSourcesItem.waitForExistence(timeout: 2))
        allSourcesItem.click()

        let restoredDefaultWidth = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                sourceMenu.exists && abs(sourceMenu.frame.width - defaultWidth) <= 1
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restoredDefaultWidth], timeout: 3), .completed)
    }

    private func assertSelectedCardMovesToTop(animationStyle: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing", "-ui-testing-animation",
            "-animationStyle", animationStyle,
            "-bringToTopOnUse", "YES",
            "-favoritesEnabled", "NO",
            "-displayStyle", "list",
            "-fadeAnimationDuration", "0.05",
            "-floatAnimationResponse", "0.20"
        ]
        app.launch()

        let first = app.buttons["history-card-00000000-0000-0000-0000-000000000001"]
        let selected = app.buttons["history-card-00000000-0000-0000-0000-000000000004"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(selected.frame.minY, first.frame.minY)

        selected.tap()

        let movedToTop = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                selected.exists && first.exists && selected.frame.minY < first.frame.minY
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [movedToTop], timeout: 3), .completed)
        XCTAssertTrue(selected.isHittable, "The selected card should be visible after the animation finishes")
    }
}
