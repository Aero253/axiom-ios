import SwiftUI
import WidgetKit

enum Ax {
    static let yellow = Color(red: 1.0, green: 0.769, blue: 0.0)      // #ffc400, the dashboard's caution yellow
    static let red = Color(red: 1.0, green: 0.255, blue: 0.212)       // #ff4136, the route and "go" red
    static let ink = Color.primary
    static var paper: Color { Color(uiColor: .systemBackground) }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Small spaced capitals, like the labels on the dashboard.
struct Caption: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(Ax.mono(10))
            .tracking(1)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The caution badge: yellow from 2 h 30 min before report, red from 35 min.
struct AlertPill: View {
    let red: Bool
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Ax.mono(10, .bold))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(red ? Ax.red : Ax.yellow))
            .foregroundStyle(red ? Color.white : Color(white: 0.07))
    }
}

extension View {
    /// Plain black or white behind the widget, following the phone's light or dark mode.
    func axiomBackground() -> some View {
        containerBackground(for: .widget) { Ax.paper }
    }
}

// MARK: - Building blocks shared by the widgets

/// A row of round dots filled to a share, like the dashboard's duty-hour bars. Turns red past the limit.
struct DotBar: View {
    let value: Double
    let limit: Double
    var count: Int = 20
    var dot: CGFloat = 6

    var body: some View {
        let lit = min(count, Int((value / max(limit, 0.001) * Double(count)).rounded()))
        let over = value > limit
        HStack(spacing: dot * 0.45) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i < lit ? (over ? Ax.red : Ax.ink) : Ax.ink.opacity(0.15))
                    .frame(width: dot, height: dot)
            }
        }
    }
}

/// The roster chip: a rounded label for the day's duty, filled for flights, outlined for the rest.
struct Chip: View {
    let text: String
    let type: String
    var size: CGFloat = 10

    var body: some View {
        let filled = type == "FDP"
        Text(text.isEmpty ? "—" : text)
            .font(Ax.mono(size, .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, size * 0.5)
            .padding(.vertical, size * 0.2)
            .foregroundStyle(filled ? Ax.paper : (type == "OFF" || type.isEmpty ? Color.secondary : Ax.ink))
            .background(
                Capsule().fill(filled ? Ax.ink : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(filled ? Color.clear : Ax.ink.opacity(type == "OFF" || type.isEmpty ? 0.3 : 0.8),
                                       style: StrokeStyle(lineWidth: 1, dash: type == "HSBY" || type == "ASBY" || type == "RES" ? [2, 2] : []))
            )
    }
}

/// The dashboard's 7×7 dot weather pictures.
enum WxIcon {
    static let grids: [String: [String]] = [
        "sun":    ["#..#..#", ".#...#.", "..###..", "#.###.#", "..###..", ".#...#.", "#..#..#"],
        "partly": ["#.#....", ".#.....", "#.#.##.", "...####", ".######", "#######", "......."],
        "cloud":  [".......", "..##...", ".####..", ".#####.", "#######", "#######", "......."],
        "rain":   ["..###..", ".#####.", "#######", ".......", "#.#.#.#", ".#.#.#.", "#.#.#.#"],
        "storm":  ["..###..", ".#####.", "#######", "...@...", "..@@...", "...@@..", "..@...."]
    ]
}

struct WxDots: View {
    let cond: String
    var size: CGFloat = 28

    var body: some View {
        let g = WxIcon.grids[cond] ?? WxIcon.grids["cloud"]!
        var lit: [DotCell] = [], hot: [DotCell] = [], off: [DotCell] = []
        for (y, row) in g.enumerated() {
            for (x, c) in row.enumerated() {
                if c == "#" { lit.append(DotCell(x: x, y: y)) } else if c == "@" { hot.append(DotCell(x: x, y: y)) } else { off.append(DotCell(x: x, y: y)) }
            }
        }
        return ZStack {
            DotShape(cells: off, columns: 7).fill(Ax.ink.opacity(0.1))
            DotShape(cells: lit, columns: 7).fill(Ax.ink)
            DotShape(cells: hot, columns: 7).fill(Ax.yellow)
        }
        .frame(width: size, height: size)
    }
}

enum TimeFmt {
    private static var cache: [String: DateFormatter] = [:]

    static func f(_ pattern: String, _ tz: String) -> DateFormatter {
        let key = pattern + "|" + tz
        if let c = cache[key] { return c }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = pattern
        cache[key] = f
        return f
    }

    /// "19:22" in a zone (Bangkok unless given).
    static func hm(_ d: Date, _ tz: String = "Asia/Bangkok") -> String { f("HH:mm", tz).string(from: d) }
    static func hm(ms: Double?, _ tz: String = "Asia/Bangkok") -> String {
        guard let ms = ms else { return "—" }
        return hm(Date(timeIntervalSince1970: ms / 1000), tz)
    }
    /// "TUE 07 OCT"
    static func day(_ d: Date, _ tz: String = "Asia/Bangkok") -> String { f("EEE dd MMM", tz).string(from: d).uppercased() }
    /// "+2h", "−1:30h", "same"
    static func offset(_ tz: String, at d: Date) -> String {
        guard let z = TimeZone(identifier: tz), let bkk = TimeZone(identifier: "Asia/Bangkok") else { return "" }
        let diff = (z.secondsFromGMT(for: d) - bkk.secondsFromGMT(for: d)) / 60
        if diff == 0 { return "same" }
        let h = abs(diff) / 60, m = abs(diff) % 60
        return (diff > 0 ? "+" : "−") + "\(h)" + (m > 0 ? String(format: ":%02d", m) : "") + "h"
    }
    /// "9:20" from hours
    static func hours(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }
}

/// Short day labels from an ISO date: ("WED", "07")
func dayParts(_ iso: String) -> (String, String) {
    let full = Fmt.day(iso)   // "WED 07 OCT"
    let parts = full.split(separator: " ")
    return (parts.count > 0 ? String(parts[0]) : "", parts.count > 1 ? String(parts[1]) : "")
}

/// Small "EXAMPLE" tag when the dashboard is still showing its sample roster.
struct ExampleTag: View {
    let demo: Bool
    var body: some View {
        if demo { Caption(text: "Example") }
    }
}

/// Shown when the app hasn't handed anything to the widgets yet.
struct OpenAxiomNote: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(text: title)
            Spacer(minLength: 0)
            Text("Open Axiom once to connect the widgets.")
                .font(Ax.mono(12))
                .lineLimit(4).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A simple timeline: the saved data, refreshed every few minutes and right after midnight.
struct PayloadEntry: TimelineEntry {
    let date: Date
    let payload: Payload?
}

struct PayloadProvider: TimelineProvider {
    var stepMinutes: Int = 5
    var count: Int = 24

    func placeholder(in context: Context) -> PayloadEntry { PayloadEntry(date: Date(), payload: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (PayloadEntry) -> Void) {
        let p = Shared.load()
        completion(PayloadEntry(date: Date(), payload: (context.isPreview && p == nil) ? .sample : p))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PayloadEntry>) -> Void) {
        let p = Shared.load()
        let now = Date()
        let start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        var entries = (0..<count).map { PayloadEntry(date: start.addingTimeInterval(Double($0 * stepMinutes) * 60), payload: p) }
        let midnight = Shared.nextBangkokMidnight(after: now)
        if let last = entries.last, midnight > last.date { entries.append(PayloadEntry(date: midnight, payload: p)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
