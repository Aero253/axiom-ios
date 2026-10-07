import XCTest
import WidgetKit
@testable import Axiom

/// Runs inside the real app in the simulator: the dashboard loads from the app bundle, hands its data to the
/// shared storage the widgets read, and picks up a glass added on the Water widget.
final class AppBridgeTests: XCTestCase {

    private func waitFor(_ seconds: Double, _ what: String, _ ok: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if ok() { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("timed out waiting for: \(what)")
    }

    func testDashboardHandsItsDataToTheWidgets() throws {
        XCTAssertNotNil(Shared.container, "the app can reach the shared storage (\(Shared.groupID))")
        waitFor(30, "the dashboard's first hand-off") { Shared.load() != nil }
        let p = try XCTUnwrap(Shared.load())
        XCTAssertGreaterThanOrEqual(p.v, 2)
        XCTAssertFalse(p.duties.isEmpty, "duties")
        XCTAssertEqual(p.days?.count, 14, "next 14 days")
        XCTAssertNotNil(p.ftl, "duty hours")
        XCTAssertFalse(p.world?.isEmpty ?? true, "world clock")
        XCTAssertNotNil(p.status(at: Date()), "a next duty for the Next duty widget")
    }

    func testGlassAddedOnTheWidgetReachesTheDashboard() throws {
        waitFor(30, "the dashboard's first hand-off") { Shared.load() != nil }
        let before = Shared.waterToday(Shared.load()).n
        Shared.addGlass()                                   // what the + on the widget does
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        // the dashboard itself must now hold the new count
        let web = try XCTUnwrap((UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController as? DashboardViewController).webView!
        var stored = ""
        waitFor(20, "the dashboard to take the widget's glass") {
            web.evaluateJavaScript("localStorage.getItem('dotboard.water')") { r, _ in stored = (r as? String) ?? "" }
            return stored.contains("\"n\":\(before + 1)")
        }
    }

    func testTickOnTheListWidgetIsHandedOver() throws {
        waitFor(30, "the dashboard's first hand-off") { Shared.load() != nil }
        Shared.saveOps([ListOp(list: "todos", id: "does-not-exist", done: true, ts: Date().timeIntervalSince1970 * 1000)])
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        // the app passes the tick to the dashboard and clears its queue once the dashboard has it
        waitFor(20, "the tick queue to be handed over") { Shared.loadOps().isEmpty }
    }
}
