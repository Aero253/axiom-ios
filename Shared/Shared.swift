import Foundation
import WidgetKit

// MARK: - What Axiom sends to the widgets

struct Leg: Codable, Hashable {
    var flt: String?
    var from: String
    var to: String
    var dep: String?
    var arr: String?
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

    var repDate: Date { Date(timeIntervalSince1970: rep / 1000) }
    var offDate: Date { Date(timeIntervalSince1970: off / 1000) }
}

struct Water: Codable, Hashable {
    var date: String
    var n: Int
    var goal: Int
    var ts: Double            // when it last changed, ms since 1970
}

struct Payload: Codable {
    var v: Int
    var at: Double
    var demo: Bool
    var base: String
    var duties: [Duty]
    var water: Water
    var theme: String?
}

// MARK: - Shared storage between the app and the widgets

enum Shared {
    static let defaultGroup = "group.com.aero253.axiom"

    /// SideStore and AltStore rename the app group when they sign the app and record the new name in
    /// Info.plist under ALTAppGroups, so look there first (in this bundle and, for the widgets, in the app around them).
    static var groupID: String {
        var bundles: [Bundle] = [Bundle.main]
        let url = Bundle.main.bundleURL
        if url.pathExtension == "appex" {
            let appURL = url.deletingLastPathComponent().deletingLastPathComponent()
            if let app = Bundle(url: appURL) { bundles.append(app) }
        }
        for b in bundles {
            if let groups = b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let first = groups.first {
                return first
            }
        }
        return defaultGroup
    }

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("axiom-widgets.json")
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
