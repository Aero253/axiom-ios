import Foundation
import WidgetKit

// MARK: - What Axiom sends to the widgets

struct Leg: Codable, Hashable {
    var flt: String?
    var from: String
    var to: String
    var dep: String?
    var arr: String?
    var depMs: Double?        // real departure instant, ms since 1970
    var arrMs: Double?
}

struct Duty: Codable, Hashable {
    var date: String          // yyyy-MM-dd, Bangkok
    var type: String          // FDP, HSBY, ASBY, RES …
    var what: String          // "Report", "Standby" …
    var start: String?        // "09:40" local
    var end: String?
    var rep: Double           // report time, ms since 1970
    var off: Double           // off-duty time, ms since 1970
    var flts: [String]
    var route: [String]
    var legs: [Leg]?
    var coords: [[Double]?]?  // lat, lon for each stop on the route
    var away: Bool?           // ends away from base (a night-stop)
    var chip: String?

    var repDate: Date { Date(timeIntervalSince1970: rep / 1000) }
    var offDate: Date { Date(timeIntervalSince1970: off / 1000) }
}

struct Water: Codable, Hashable {
    var date: String
    var n: Int
    var goal: Int
    var ts: Double            // when it last changed, ms since 1970
}

struct DayInfo: Codable, Hashable {
    var date: String
    var type: String
    var chip: String
    var start: String?
    var end: String?
    var txt: String
    var plans: Int
}

struct MonthInfo: Codable {
    var ym: String
    var days: [DayInfo]
}

struct Limits: Codable {
    var duty7: Double
    var duty14: Double
    var duty28: Double
    var flight28: Double
    var restHome: Double
    var restAway: Double
}

struct FTL: Codable {
    var duty7: Double
    var duty14: Double
    var duty28: Double
    var flight28: Double
    var lim: Limits
    var at: Double
    var lastOff: Double?
    var lastAway: Bool?
}

struct WakePlan: Codable {
    var rep: Double
    var leave: Double
    var alarm: Double
    var bed: Double
    var what: String
    var flt: String?
}

struct WorldCity: Codable, Hashable {
    var code: String
    var name: String
    var tz: String
    var roster: Bool
}

struct SunDay: Codable, Hashable {
    var d: String
    var rise: Double?
    var set: Double?
}

struct SunCity: Codable, Hashable {
    var code: String
    var name: String
    var tz: String
    var days: [SunDay]
}

struct WxNow: Codable, Hashable {
    var t: Double
    var cond: String
    var text: String
}

struct WxDay: Codable, Hashable {
    var d: String
    var hi: Double
    var lo: Double
    var p: Double
    var cond: String
}

struct WxCity: Codable, Hashable {
    var code: String
    var name: String
    var lat: Double
    var lon: Double
    var tz: String
    var current: WxNow?
    var daily: [WxDay]
    var sub: String? = nil    // your location only: the province under the district's name
}

struct Weather: Codable {
    var updatedAt: String
    var cities: [WxCity]
}

struct ListItem: Codable, Hashable {
    var id: String
    var text: String
    var done: Bool
    var qty: String?
}

struct CountItem: Codable, Hashable {
    var title: String
    var date: String
}

struct Layover: Codable, Hashable {
    var to: String
    var name: String
    var tz: String
    var arr: Double
    var hotel: String?
    var room: String?
    var pickup: String?
    var pickupMs: Double?
}

struct Payload: Codable {
    var v: Int
    var at: Double
    var demo: Bool
    var base: String
    var duties: [Duty]
    var water: Water
    var theme: String?
    // added in v2; all optional so an older save still opens
    var days: [DayInfo]?
    var month: MonthInfo?
    var ftl: FTL?
    var wake: WakePlan?
    var world: [WorldCity]?
    var sun: [SunCity]?
    var wx: Weather?
    var todos: [ListItem]?
    var shopping: [ListItem]?
    var counts: [CountItem]?
    var lays: [Layover]?
    var alarms: AlarmSet?     // added in 1.2: what the alarm clock should ring
    var notify: NotifyPlan?   // added in 1.2: duty and water reminders
}

// MARK: - Alarm clock

/// One alarm from the dashboard: either a moment (`at`, a duty alarm or a one-off) or a clock time that repeats on weekdays.
struct AlarmItem: Codable, Hashable {
    var key: String
    var at: Double?          // ms since 1970
    var h: Int?
    var m: Int?
    var days: [Int]?         // 0 = Sunday … 6 = Saturday, as in JavaScript
    var title: String
    var sub: String?
    var snd: String? = nil   // "axiom": Axiom's own chime; nil or "default": the iPhone's alarm sound

    /// The sound file in the app, or nil for the iPhone's own alarm sound.
    var soundFile: String? { snd == nil || snd == "default" ? nil : "axiom-chime.wav" }

    /// The next time this rings after `date`, on this phone's clock.
    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        if let at = at {
            let d = Date(timeIntervalSince1970: at / 1000)
            return d > date ? d : nil
        }
        guard let h = h, let m = m else { return nil }
        let start = calendar.startOfDay(for: date)
        for i in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: i, to: start),
                  let c = calendar.date(bySettingHour: h, minute: m, second: 0, of: day) else { continue }
            let wd = calendar.component(.weekday, from: c) - 1
            if c > date && ((days ?? []).isEmpty || (days ?? []).contains(wd)) { return c }
        }
        return nil
    }

    /// Duty alarms are set from the roster; the rest are the ones you added yourself.
    var isDuty: Bool { key.hasPrefix("d") }
}

struct AlarmSet: Codable, Hashable {
    var on: Bool?
    var snooze: Int
    var list: [AlarmItem]

    /// The next alarm to ring after `date`, with when it rings.
    func next(after date: Date) -> (item: AlarmItem, at: Date)? {
        list.compactMap { i in i.next(after: date).map { (i, $0) } }.min { $0.1 < $1.1 }
    }
}

/// A tick made on a list widget, waiting to be handed to the dashboard next time the app opens.
struct ListOp: Codable, Hashable {
    var list: String      // "todos" or "shopping"
    var id: String
    var done: Bool
    var ts: Double
}

// MARK: - Shared storage between the app and the widgets

enum Shared {
    static let defaultGroup = "group.com.aero253.axiom"

    /// Sideloading tools rename the app group when they sign the app (each adds its own suffix), so work out the real name:
    /// first from the signing profile inside the app (it lists the groups this copy may use), then from the
    /// ALTAppGroups note SideStore/AltStore leave in Info.plist, and only then fall back to the name we built with.
    static let groupID: String = {
        var candidates: [String] = []
        var bundles: [Bundle] = [Bundle.main]
        let url = Bundle.main.bundleURL
        if url.pathExtension == "appex" {
            let appURL = url.deletingLastPathComponent().deletingLastPathComponent()
            if let app = Bundle(url: appURL) { bundles.append(app) }
        }
        for b in bundles { candidates += profileGroups(in: b) }
        // iloader registers group.<app ID>, where the app ID is the bundle ID with the team ID added
        if let app = bundles.last?.bundleIdentifier { candidates.append("group." + app) }
        if let me = Bundle.main.bundleIdentifier, me.hasSuffix(".widgets") { candidates.append("group." + String(me.dropLast(".widgets".count))) }
        for b in bundles {
            if let groups = b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { candidates += groups }
        }
        candidates.append(defaultGroup)
        let fm = FileManager.default
        return candidates.first(where: { fm.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }) ?? defaultGroup
    }()

    /// The app groups listed in a bundle's embedded.mobileprovision (a signed plist; the XML sits inside it as plain text).
    private static func profileGroups(in bundle: Bundle) -> [String] {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return [] }
        return profileGroups(data: data)
    }

    static func profileGroups(data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return [] }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any],
              let groups = ent["com.apple.security.application-groups"] as? [String] else { return [] }
        return groups.filter { !$0.contains("*") }
    }

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    static var fileURL: URL? { container?.appendingPathComponent("axiom-widgets.json") }
    static var opsURL: URL? { container?.appendingPathComponent("axiom-list-ops.json") }
    static var wxURL: URL? { container?.appendingPathComponent("axiom-weather.json") }

    // MARK: ticks from the list widgets

    static func loadOps() -> [ListOp] {
        guard let url = opsURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ListOp].self, from: data)) ?? []
    }

    static func saveOps(_ ops: [ListOp]) {
        guard let url = opsURL, let data = try? JSONEncoder().encode(ops) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// A list as the widget should show it: the dashboard's last save, with any ticks made since laid on top.
    static func items(_ list: String, in p: Payload?) -> [ListItem] {
        var items = (list == "shopping" ? p?.shopping : p?.todos) ?? []
        for op in loadOps() where op.list == list {
            if let i = items.firstIndex(where: { $0.id == op.id }) { items[i].done = op.done }
        }
        return items
    }

    static func toggle(list: String, id: String) {
        let current = items(list, in: load())
        guard let item = current.first(where: { $0.id == id }) else { return }
        var ops = loadOps().filter { !($0.list == list && $0.id == id) }
        ops.append(ListOp(list: list, id: id, done: !item.done, ts: Date().timeIntervalSince1970 * 1000))
        saveOps(ops)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: weather the widget fetched itself

    static func loadWeather() -> Weather? {
        if let url = wxURL, let data = try? Data(contentsOf: url), let w = try? JSONDecoder().decode(Weather.self, from: data) { return w }
        return load()?.wx
    }

    static func saveWeather(_ w: Weather) {
        guard let url = wxURL, let data = try? JSONEncoder().encode(w) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> Payload? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func save(_ p: Payload) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(p) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Bangkok calendar day, the same one Axiom uses for the water count.
    static func todayISO(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func nextBangkokMidnight(after date: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        let start = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86400)
    }

    /// Today's water, counting from zero once the day has changed.
    static func waterToday(_ p: Payload?) -> Water {
        let today = todayISO()
        guard let w = p?.water else { return Water(date: today, n: 0, goal: 8, ts: 0) }
        if w.date == today { return w }
        return Water(date: today, n: 0, goal: w.goal, ts: w.ts)
    }

    /// Used by the + button on the Water widget.
    static func addGlass() {
        let now = Date().timeIntervalSince1970 * 1000
        var p = load() ?? Payload(v: 1, at: now, demo: true, base: "DMK", duties: [],
                                  water: Water(date: todayISO(), n: 0, goal: 8, ts: 0), theme: nil)
        var w = waterToday(p)
        w.n = min(30, w.n + 1)
        w.ts = now
        p.water = w
        save(p)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Next duty, the same rules as the dashboard

struct DutyStatus {
    let duty: Duty
    let onDuty: Bool
    let target: Date        // report time, or off-duty time while on duty
}

extension Payload {
    func status(at now: Date) -> DutyStatus? {
        let ms = now.timeIntervalSince1970 * 1000
        if let cur = duties.first(where: { $0.rep <= ms && $0.off > ms }) {
            return DutyStatus(duty: cur, onDuty: true, target: cur.offDate)
        }
        if let nx = duties.filter({ $0.rep > ms }).min(by: { $0.rep < $1.rep }) {
            return DutyStatus(duty: nx, onDuty: false, target: nx.repDate)
        }
        return nil
    }
}

enum Fmt {
    /// "13H 02M", "45M", "2D 04H" — the dashboard's countdown wording.
    static func countdown(_ seconds: TimeInterval) -> String {
        let m = max(0, Int((seconds / 60).rounded(.up)))
        if m >= 1440 { return "\(m / 1440)D \(String(format: "%02d", (m % 1440) / 60))H" }
        if m >= 60 { return "\(m / 60)H \(String(format: "%02d", m % 60))M" }
        return "\(m)M"
    }

    /// "2026-10-07" → "WED 07 OCT"
    static func day(_ iso: String) -> String {
        let p = DateFormatter()
        p.locale = Locale(identifier: "en_US_POSIX")
        p.timeZone = TimeZone(identifier: "UTC")
        p.dateFormat = "yyyy-MM-dd"
        guard let d = p.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE dd MMM"
        return f.string(from: d).uppercased()
    }

    static func litres(_ glasses: Int) -> String {
        let ml = glasses * 250
        if ml >= 1000 {
            let l = Double(ml) / 1000
            return (l == l.rounded() ? String(Int(l)) : String(format: "%.2f", l).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)) + " L"
        }
        return "\(ml) ML"
    }
}

extension Payload {
    static var sample: Payload {
        let now = Date().timeIntervalSince1970 * 1000
        let rep = now + (13 * 60 + 2) * 60_000
        let d = Duty(date: Shared.todayISO(Date().addingTimeInterval(13 * 3600)), type: "FDP", what: "Report",
                     start: "09:40", end: "19:05", rep: rep, off: rep + 9.4 * 3_600_000,
                     flts: ["SL770", "SL771", "SL750", "SL751"], route: ["DMK", "HKT", "DMK", "HDY", "DMK"],
                     legs: [Leg(flt: "SL770", from: "DMK", to: "HKT", dep: "10:55", arr: "12:20"),
                            Leg(flt: "SL771", from: "HKT", to: "DMK", dep: "13:00", arr: "14:25"),
                            Leg(flt: "SL750", from: "DMK", to: "HDY", dep: "15:20", arr: "16:45"),
                            Leg(flt: "SL751", from: "HDY", to: "DMK", dep: "17:15", arr: "18:35")])
        return Payload(v: 1, at: now, demo: true, base: "DMK", duties: [d],
                       water: Water(date: Shared.todayISO(), n: 3, goal: 8, ts: now), theme: "dark")
    }
}
