import XCTest
import CoreText
import UIKit
import SwiftUI
import WidgetKit

/// Checks the widgets against real data from the dashboard and draws every widget at every size,
/// light and dark, into PNGs so they can be looked at before anything is installed.
final class WidgetPreviewTests: XCTestCase {

    private var payload: Payload!
    private var now: Date!
    private let outDir: URL = {
        let path = ProcessInfo.processInfo.environment["PREVIEW_DIR"] ?? (NSTemporaryDirectory() + "axiom-previews")
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: WidgetPreviewTests.self).url(forResource: "payload", withExtension: "json"))
        payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
        now = Date(timeIntervalSince1970: payload.at / 1000)
        if let font = Bundle(for: WidgetPreviewTests.self).url(forResource: "AxiomDots", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        }
    }

    // MARK: data

    func testDashboardDataDecodes() throws {
        XCTAssertFalse(payload.duties.isEmpty, "duties")
        XCTAssertEqual(payload.days?.count, 14, "next 14 days")
        XCTAssertNotNil(payload.month, "month")
        XCTAssertNotNil(payload.ftl, "duty hours")
        XCTAssertNotNil(payload.wake, "wake-up plan")
        XCTAssertFalse(payload.world?.isEmpty ?? true, "world clock")
        XCTAssertFalse(payload.sun?.isEmpty ?? true, "sun")
        XCTAssertFalse(payload.wx?.cities.isEmpty ?? true, "weather")
        XCTAssertFalse(payload.todos?.isEmpty ?? true, "to-do")
        XCTAssertFalse(payload.counts?.isEmpty ?? true, "countdowns")
        XCTAssertNotNil(payload.status(at: now), "a next duty")
        XCTAssertFalse(payload.alarms?.list.isEmpty ?? true, "alarms")
        XCTAssertEqual(payload.notify?.water, true, "reminders")
        XCTAssertNotNil(UIFont(name: "AxiomDots-Regular", size: 20), "the dot font for the snooze countdown")
        XCTAssertTrue(payload.duties.contains { !($0.coords ?? []).isEmpty }, "route coordinates for the globe")
        XCTAssertTrue(payload.duties.contains { ($0.legs ?? []).contains { $0.depMs != nil } }, "leg times for flight progress")
    }

    func testOldSaveStillDecodes() throws {
        // a save from the first version, before the extra widget data existed
        let v1 = #"{"v":1,"at":1791300000000,"demo":true,"base":"DMK","duties":[],"water":{"date":"2026-10-06","n":2,"goal":8,"ts":0},"theme":"dark"}"#
        let p = try JSONDecoder().decode(Payload.self, from: Data(v1.utf8))
        XCTAssertNil(p.days)
        XCTAssertEqual(p.water.n, 2)
    }

    func testStorageNameFromSigningProfile() {
        // the shape of an embedded.mobileprovision: signature bytes around a plain XML plist
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Entitlements</key><dict>
        <key>com.apple.security.application-groups</key><array><string>group.com.aero253.axiom.ABCDE12345</string></array>
        </dict></dict></plist>
        """
        var data = Data([0x30, 0x82, 0x01, 0x02, 0x06, 0x09])
        data.append(Data(xml.utf8))
        data.append(Data([0xA0, 0x82, 0x00, 0x10]))
        XCTAssertEqual(Shared.profileGroups(data: data), ["group.com.aero253.axiom.ABCDE12345"])
        XCTAssertEqual(Shared.profileGroups(data: Data("no plist here".utf8)), [])
    }

    func testListTicksLayOverTheList() {
        let items = Shared.items("todos", in: payload)
        XCTAssertEqual(items.count, payload.todos?.count)
    }

    func testSiriAnswers() throws {
        let next = Speak.nextReport(payload, now: now)
        print("Siri next report:", next)
        XCTAssertFalse(next.isEmpty)
        let tmr = Speak.tomorrow(payload, now: now)
        print("Siri tomorrow:", tmr)
        XCTAssertTrue(tmr.hasPrefix("Tomorrow") || tmr.hasPrefix("Your roster") || tmr.hasPrefix("Nothing"), tmr)
        print("Siri next alarm:", Speak.nextAlarm(payload, now: now))
        XCTAssertEqual(Speak.place("CNX", in: nil), "Chiang Mai")
        XCTAssertEqual(Speak.place("ZZZ", in: nil), "Z Z Z")
        XCTAssertEqual(Speak.span(9 * 3600 + 20 * 60), "9 hours 20 minutes")
        XCTAssertEqual(Speak.water(Water(date: "", n: 3, goal: 8, ts: 0)), "Added. 3 of 8 glasses today, 5 to go.")
        // the example roster in the test data is marked demo, so read it as if it were imported
        var real = payload!; real.demo = false
        let spoken = Speak.nextReport(real, now: now)
        print("Siri next report (imported):", spoken)
        XCTAssertTrue(spoken.contains("That's in"), spoken)
    }

    func testWaterReminders() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let at1300 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 13)))
        XCTAssertEqual(Reminders.expected(goal: 8, hour: 22), 8)
        let behind = Reminders.waterTimes(now: at1300, water: Water(date: "2026-10-08", n: 1, goal: 8, ts: 0), calendar: cal)
        XCTAssertEqual(behind.first.map { cal.component(.hour, from: $0.at) }, 14, "next nudge at 14:00 when behind")
        let ahead = Reminders.waterTimes(now: at1300, water: Water(date: "2026-10-08", n: 8, goal: 8, ts: 0), calendar: cal)
        XCTAssertTrue(ahead.allSatisfy { cal.component(.day, from: $0.at) == 9 }, "goal reached: nothing more today, only tomorrow's")
        XCTAssertEqual(ahead.count, Reminders.waterHours.count)
    }

    func testAlarmTimes() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        // Thursday 8 Oct 2026, 20:00 in Bangkok
        let thu = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 20)))
        let gym = AlarmItem(key: "m1", at: nil, h: 6, m: 30, days: [1, 3, 5], title: "Gym", sub: nil)   // Mon Wed Fri
        let next = try XCTUnwrap(gym.next(after: thu, calendar: cal))
        XCTAssertEqual(cal.component(.weekday, from: next), 6, "Friday")
        XCTAssertEqual(cal.component(.hour, from: next), 6)
        XCTAssertEqual(cal.component(.minute, from: next), 30)
        let daily = AlarmItem(key: "m2", at: nil, h: 21, m: 0, days: [], title: "Once", sub: nil)
        XCTAssertEqual(daily.next(after: thu, calendar: cal).map { cal.component(.day, from: $0) }, 8, "later the same evening")
        let past = AlarmItem(key: "d1", at: (thu.timeIntervalSince1970 - 60) * 1000, h: nil, m: nil, days: nil, title: "Duty", sub: nil)
        XCTAssertNil(past.next(after: thu), "a duty alarm that has gone off doesn't come back")
        let set = AlarmSet(on: true, snooze: 9, list: [gym, daily, past])
        XCTAssertEqual(set.next(after: thu)?.item.key, "m2")
    }

    // MARK: pictures

    private let small = CGSize(width: 170, height: 170)
    private let medium = CGSize(width: 364, height: 170)
    private let large = CGSize(width: 364, height: 382)
    private let rect = CGSize(width: 172, height: 76)
    private let circle = CGSize(width: 76, height: 76)
    private let inline = CGSize(width: 234, height: 26)

    @MainActor
    private func draw<V: View>(_ name: String, _ size: CGSize, accessory: Bool = false, @ViewBuilder _ view: () -> V) {
        for dark in [true, false] {
            let content = view()
                .padding(accessory ? 0 : 16)
                .frame(width: size.width, height: size.height)
                .background(dark ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: accessory ? 12 : 22))
                .environment(\.colorScheme, dark ? .dark : .light)
            let r = ImageRenderer(content: content)
            r.scale = 2
            guard let png = r.uiImage?.pngData() else { XCTFail("could not draw \(name)"); continue }
            XCTAssertNoThrow(try png.write(to: outDir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")))
        }
    }

    /// A moment in the middle of a sector, for the in-flight pictures.
    private var midFlight: Date {
        let legs = payload.duties.flatMap { $0.legs ?? [] }.filter { $0.depMs != nil && ($0.depMs ?? 0) > payload.at - 864e5 }
        guard let l = legs.first, let d = l.depMs, let a = l.arrMs else { return now }
        return Date(timeIntervalSince1970: (d + a) / 2000)
    }

    /// Two hours and twenty minutes before the next report: yellow; twenty minutes before: red.
    private func beforeReport(minutes: Double) -> Date {
        guard let st = payload.status(at: now), !st.onDuty else { return now }
        return st.target.addingTimeInterval(-minutes * 60)
    }

    @MainActor
    func testDrawEveryWidget() throws {
        let e = DutyEntry(date: now, payload: payload)
        let pe = PayloadEntry(date: now, payload: payload)
        let me = MinuteEntry(date: now, payload: payload)

        // roster
        draw("01-next-duty-small", small) { NextDutyView(forcedFamily: .systemSmall, entry: e) }
        draw("01-next-duty-small-yellow", small) { NextDutyView(forcedFamily: .systemSmall, entry: DutyEntry(date: beforeReport(minutes: 140), payload: payload)) }
        draw("01-next-duty-small-red", small) { NextDutyView(forcedFamily: .systemSmall, entry: DutyEntry(date: beforeReport(minutes: 20), payload: payload)) }
        draw("02-next-duty-medium", medium) { NextDutyView(forcedFamily: .systemMedium, entry: e) }
        draw("03-next-duty-large", large) { NextDutyView(forcedFamily: .systemLarge, entry: DutyEntry(date: midFlight, payload: payload)) }
        draw("04-next-duty-lock-rect", rect, accessory: true) { NextDutyView(forcedFamily: .accessoryRectangular, entry: e) }
        draw("05-flight-small", small) { FlightProgressView(forcedFamily: .systemSmall, entry: DutyEntry(date: midFlight, payload: payload)) }
        draw("05-flight-medium", medium) { FlightProgressView(forcedFamily: .systemMedium, entry: DutyEntry(date: midFlight, payload: payload)) }
        draw("05-flight-medium-next", medium) { FlightProgressView(forcedFamily: .systemMedium, entry: e) }
        draw("06-globe-small", small) { GlobeView(forcedFamily: .systemSmall, entry: e) }
        draw("06-globe-medium", medium) { GlobeView(forcedFamily: .systemMedium, entry: e) }
        draw("06-globe-large", large) { GlobeView(forcedFamily: .systemLarge, entry: e) }
        draw("07-agenda-medium", medium) { AgendaView(forcedFamily: .systemMedium, entry: pe) }
        draw("07-agenda-large", large) { AgendaView(forcedFamily: .systemLarge, entry: pe) }
        draw("08-month-large", large) { MonthView(forcedFamily: .systemLarge, entry: pe) }

        // time
        draw("09-clock-small", small) { ClockView(forcedFamily: .systemSmall, entry: me) }
        draw("09-clock-medium", medium) { ClockView(forcedFamily: .systemMedium, entry: me) }
        draw("10-world-small", small) { WorldClockView(forcedFamily: .systemSmall, entry: pe) }
        draw("10-world-medium", medium) { WorldClockView(forcedFamily: .systemMedium, entry: pe) }
        draw("10-world-large", large) { WorldClockView(forcedFamily: .systemLarge, entry: pe) }
        draw("11-year-small", small) { YearView(forcedFamily: .systemSmall, entry: YearEntry(date: now)) }
        draw("11-year-medium", medium) { YearView(forcedFamily: .systemMedium, entry: YearEntry(date: now)) }

        // crew
        draw("12-duty-hours-small", small) { DutyHoursView(forcedFamily: .systemSmall, entry: pe) }
        draw("12-duty-hours-medium", medium) { DutyHoursView(forcedFamily: .systemMedium, entry: pe) }
        draw("13-rest-small", small) { RestView(entry: pe) }
        draw("14-wake-small", small) { WakeView(forcedFamily: .systemSmall, entry: pe) }
        draw("14-wake-lock-rect", rect, accessory: true) { WakeView(forcedFamily: .accessoryRectangular, entry: pe) }
        draw("15-layover-small", small) { LayoverView(forcedFamily: .systemSmall, entry: pe) }
        draw("15-layover-medium", medium) { LayoverView(forcedFamily: .systemMedium, entry: pe) }

        // everyday
        let wx = WxEntry(date: now, wx: payload.wx, demo: payload.demo)
        draw("16-weather-small", small) { WeatherView(forcedFamily: .systemSmall, entry: wx) }
        draw("16-weather-medium", medium) { WeatherView(forcedFamily: .systemMedium, entry: wx) }
        draw("16-weather-large", large) { WeatherView(forcedFamily: .systemLarge, entry: wx) }
        draw("17-sun-small", small) { SunView(forcedFamily: .systemSmall, entry: pe) }
        draw("17-sun-medium", medium) { SunView(forcedFamily: .systemMedium, entry: pe) }
        let water = Shared.waterToday(payload)
        draw("18-water-small", small) { WaterView(forcedFamily: .systemSmall, entry: WaterEntry(date: now, water: water)) }
        draw("18-water-medium", medium) { WaterView(forcedFamily: .systemMedium, entry: WaterEntry(date: now, water: water)) }
        draw("19-todo-small", small) { ListView(forcedFamily: .systemSmall, entry: pe, list: "todos", title: "To-do") }
        draw("19-todo-medium", medium) { ListView(forcedFamily: .systemMedium, entry: pe, list: "todos", title: "To-do") }
        draw("20-shopping-large", large) { ListView(forcedFamily: .systemLarge, entry: pe, list: "shopping", title: "Shopping") }
        draw("21-countdown-small", small) { CountdownView(forcedFamily: .systemSmall, entry: pe) }
        draw("21-countdown-medium", medium) { CountdownView(forcedFamily: .systemMedium, entry: pe) }
        draw("21-countdown-lock-rect", rect, accessory: true) { CountdownView(forcedFamily: .accessoryRectangular, entry: pe) }

        // alarm clock
        draw("22-alarm-small", small) { AlarmView(forcedFamily: .systemSmall, entry: pe) }
        draw("22-alarm-small-later", small) { AlarmView(forcedFamily: .systemSmall, entry: PayloadEntry(date: now.addingTimeInterval(86400), payload: payload)) }
        draw("22-alarm-lock-rect", rect, accessory: true) { AlarmView(forcedFamily: .accessoryRectangular, entry: pe) }
        draw("22-alarm-lock-inline", inline, accessory: true) { AlarmView(forcedFamily: .accessoryInline, entry: pe) }
        draw("23-snooze-lock-screen", CGSize(width: 364, height: 96), accessory: true) {
            SnoozeCard(title: "Alarm", sub: "Mon Wed Fri", fireDate: nil, remaining: 8 * 60 + 41).background(Color.black)
        }

        // before Axiom has ever been opened
        let empty = PayloadEntry(date: now, payload: nil)
        draw("99-not-connected", small) { NextDutyView(forcedFamily: .systemSmall, entry: DutyEntry(date: now, payload: nil)) }
        draw("99-not-connected-agenda", medium) { AgendaView(forcedFamily: .systemMedium, entry: empty) }
    }
}
