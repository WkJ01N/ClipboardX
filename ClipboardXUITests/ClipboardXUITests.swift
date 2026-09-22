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
        let maximumExpansion: CGFloat = 150
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-source-filter", "-favoritesEnabled", "NO"]
        app.launch()

        let sourceMenu = app.descendants(matching: .any)["source-filter-menu"]
        XCTAssertTrue(sourceMenu.waitForExistence(timeout: 5))
        let defaultWidth = sourceMenu.frame.width

        sourceMenu.click()
        let longSourceItem = app.menuItems[longApplicationName]
        XCTAssertTrue(longSourceItem.waitForExistence(timeout: 2))
        longSourceItem.click()

        let selectedLongSource = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let expansion = sourceMenu.frame.width - defaultWidth
                return sourceMenu.exists && expansion > 1
                    && expansion <= maximumExpansion
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selectedLongSource], timeout: 3), .completed)
    }

    func testMouseLongPressOpensPreviewWithoutActivatingCard() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing", "-ui-testing-animation",
            "-favoritesEnabled", "NO",
            "-displayStyle", "list",
            "-bringToTopOnUse", "YES",
            "-mousePreviewLongPressDuration", "0.3",
            "-mousePreviewPersistsAfterRelease", "YES"
        ]
        app.launch()

        let first = app.buttons["history-card-00000000-0000-0000-0000-000000000001"]
        let target = app.buttons["history-card-00000000-0000-0000-0000-000000000004"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        target.press(forDuration: 0.6)

        XCTAssertTrue(app.descendants(matching: .any)["quick-look-preview"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(target.frame.minY, first.frame.minY, "Long press must not activate or reorder the card")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.descendants(matching: .any)["quick-look-preview"].exists)

        let cardAfterPreview = app.buttons["history-card-00000000-0000-0000-0000-000000000004"]
        let cardReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in cardAfterPreview.exists && cardAfterPreview.isHittable },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [cardReady], timeout: 3), .completed)
        cardAfterPreview.tap()
        let movedAfterShortPress = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                cardAfterPreview.exists && first.exists && cardAfterPreview.frame.minY < first.frame.minY
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [movedAfterShortPress], timeout: 3), .completed)
    }

    func testMousePreviewClosesOnReleaseWhenConfigured() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing", "-ui-testing-animation",
            "-favoritesEnabled", "NO",
            "-displayStyle", "list",
            "-mousePreviewLongPressDuration", "0.3",
            "-mousePreviewPersistsAfterRelease", "NO"
        ]
        app.launch()

        let first = app.buttons["history-card-00000000-0000-0000-0000-000000000001"]
        let target = app.buttons["history-card-00000000-0000-0000-0000-000000000004"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.press(forDuration: 0.6)
        XCTAssertFalse(app.descendants(matching: .any)["quick-look-preview"].exists)
        XCTAssertGreaterThan(target.frame.minY, first.frame.minY)
    }

    func testHoldDoesNotPreviewWhenOnlyForceClickIsEnabled() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing", "-ui-testing-animation",
            "-favoritesEnabled", "NO",
            "-displayStyle", "list",
            "-bringToTopOnUse", "YES",
            "-mousePreviewLongPressEnabled", "NO",
            "-forceClickPreviewEnabled", "YES"
        ]
        app.launch()

        let first = app.buttons["history-card-00000000-0000-0000-0000-000000000001"]
        let target = app.buttons["history-card-00000000-0000-0000-0000-000000000004"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.press(forDuration: 0.7)
        XCTAssertFalse(app.descendants(matching: .any)["quick-look-preview"].exists)
        let movedAfterRelease = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                target.exists && first.exists && target.frame.minY < first.frame.minY
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [movedAfterRelease], timeout: 3), .completed)
    }

    func testDraggingAwayBeforeDelayCancelsPreviewAndActivation() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing", "-ui-testing-animation",
            "-favoritesEnabled", "NO",
            "-mousePreviewLongPressDuration", "0.5"
        ]
        app.launch()

        let first = app.buttons["history-card-00000000-0000-0000-0000-000000000001"]
        let target = app.buttons["history-card-00000000-0000-0000-0000-000000000004"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.press(forDuration: 0.1, thenDragTo: first)

        XCTAssertFalse(app.descendants(matching: .any)["quick-look-preview"].exists)
        XCTAssertGreaterThan(target.frame.minY, first.frame.minY)
    }

    func testCardContextMenuStillOpens() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-animation", "-favoritesEnabled", "NO"]
        app.launch()

        let card = app.buttons["history-card-00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.rightClick()
        XCTAssertTrue(app.menuItems["固定在顶部"].waitForExistence(timeout: 3))
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
