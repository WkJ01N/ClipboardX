import XCTest

final class ClipboardXUITests: XCTestCase {
    func testApplicationLaunches() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5) || app.state == .runningBackground)
    }
}
