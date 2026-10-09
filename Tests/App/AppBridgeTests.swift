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

    func testAlarmClockRoundTrip() throws {
        waitFor(30, "the dashboard's first hand-off") { Shared.load() != nil }
        XCTAssertNotNil(Shared.load()?.alarms, "the dashboard hands over its alarms")
        // the app tells the dashboard how iOS will ring them
        let web = try XCTUnwrap((UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController as? DashboardViewController).webView!
        var note = ""
        waitFor(20, "the alarm status to reach the dashboard") {
            web.evaluateJavaScript("document.querySelector('#alNote').textContent") { r, _ in note = (r as? String) ?? "" }
            return note.contains("Clock app") || note.contains("notification")
        }
        if #available(iOS 26.0, *) { XCTAssertTrue(note.contains("Clock app"), "AlarmKit on iOS 26: \(note)") }
    }

    func testAlarmIDs() {
        let a = AlarmItem(key: "d1", at: 1_800_000_000_000, h: nil, m: nil, days: nil, title: "Flight SL770", sub: "Report 06:00")
        var b = a
        XCTAssertEqual(AlarmScheduler.id(for: a, snooze: 9), AlarmScheduler.id(for: b, snooze: 9), "the same alarm keeps its ID")
        b.at = 1_800_000_060_000
        XCTAssertNotEqual(AlarmScheduler.id(for: a, snooze: 9), AlarmScheduler.id(for: b, snooze: 9), "a moved alarm gets a new one")
        XCTAssertNotEqual(AlarmScheduler.id(for: a, snooze: 9), AlarmScheduler.id(for: a, snooze: 5), "so does a new snooze length")
        let set = AlarmSet(on: true, snooze: 9, list: [a, AlarmItem(key: "d0", at: 1000, h: nil, m: nil, days: nil, title: "old", sub: nil),
                                                       AlarmItem(key: "m1", at: nil, h: 6, m: 30, days: [1], title: "Gym", sub: nil)])
        XCTAssertEqual(AlarmScheduler.upcoming(set).map(\.key), ["d1", "m1"], "past alarms are left out")
    }

    func testAlarmSounds() {
        for n in ["axiom-beep", "axiom-chime", "axiom-buzz"] {
            XCTAssertNotNil(Bundle.main.url(forResource: n, withExtension: "wav"), "\(n).wav is in the app")
        }
        var a = AlarmItem(key: "m1", at: nil, h: 6, m: 30, days: [1], title: "Gym", sub: nil)
        XCTAssertNil(a.soundFile, "no choice: the iPhone's own alarm sound")
        let before = AlarmScheduler.id(for: a, snooze: 9)
        a.snd = "beep"
        XCTAssertEqual(a.soundFile, "axiom-beep.wav")
        XCTAssertNotEqual(before, AlarmScheduler.id(for: a, snooze: 9), "a new sound sets the alarm again")
    }
}
