import SwiftUI
import WidgetKit

// MARK: - Next 7 days

struct AgendaView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: PayloadEntry

    var body: some View {
        if let p = entry.payload, let days = p.days, !days.isEmpty {
            let today = Shared.todayISO(entry.date)
            let upcoming = days.filter { $0.date >= today }
            let n = family == .systemLarge ? 7 : 4
            VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 5) {
                HStack {
                    Caption(text: "Next \(n) days")
                    Spacer(minLength: 0)
                    ExampleTag(demo: p.demo)
                }
                ForEach(Array(upcoming.prefix(n).enumerated()), id: \.offset) { i, d in
                    row(d, first: i == 0)
                }
                Spacer(minLength: 0)
            }
        } else {
            OpenAxiomNote(title: "Next 7 days")
        }
    }

    private func row(_ d: DayInfo, first: Bool) -> some View {
        let (dow, num) = dayParts(d.date)
        return Group {
            if family == .systemLarge { tallRow(d, first: first, dow: dow, num: num) } else { shortRow(d, first: first, dow: dow, num: num) }
        }
    }

    private func shortRow(_ d: DayInfo, first: Bool, dow: String, num: String) -> some View {
        HStack(spacing: 8) {
            Text(first ? "TODAY" : "\(dow) \(num)").font(Ax.mono(11, .bold)).foregroundStyle(first ? Ax.ink : .secondary)
                .frame(width: 58, alignment: .leading)
            Chip(text: d.chip.isEmpty ? "—" : d.chip, type: d.type, size: 10)
                .frame(width: 66, alignment: .leading)
            Text(d.start.map { "\($0)–\(d.end ?? "")" } ?? (d.txt.isEmpty ? "Nothing rostered" : d.txt))
                .font(Ax.mono(11, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if d.plans > 0 { Circle().fill(Ax.ink).frame(width: 6, height: 6) }
        }
    }

    private func tallRow(_ d: DayInfo, first: Bool, dow: String, num: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(first ? "TODAY" : dow).font(Ax.mono(9, .bold)).foregroundStyle(first ? Ax.ink : .secondary)
                Text(num).font(Ax.mono(15, .bold))
            }
            .frame(width: 40, alignment: .leading)
            Chip(text: d.chip.isEmpty ? "—" : d.chip, type: d.type, size: 10)
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(d.txt.isEmpty ? "Nothing rostered" : d.txt).font(Ax.mono(11, .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                if let s = d.start, let e = d.end {
                    Text("\(s)–\(e)").font(Ax.mono(10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if d.plans > 0 {
                Circle().fill(Ax.ink).frame(width: 6, height: 6)
            }
        }
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomAgenda", provider: PayloadProvider(stepMinutes: 30, count: 8)) { e in
            AgendaView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Next 7 days")
        .description("Your roster for the week ahead, one line a day. A dot marks days with plans.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Month calendar with duty chips

struct MonthView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: PayloadEntry

    var body: some View {
        if let p = entry.payload, let m = p.month, !m.days.isEmpty {
            let today = Shared.todayISO(entry.date)
            let lead = leadingBlanks(m.days.first?.date ?? today)
            let cells: [DayInfo?] = Array(repeating: nil, count: lead) + m.days.map { Optional($0) }
            let rows = Int((Double(cells.count) / 7).rounded(.up))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(monthTitle(m.ym)).font(Ax.mono(13, .bold))
                    Spacer(minLength: 0)
                    ExampleTag(demo: p.demo)
                }
                HStack(spacing: 2) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                        Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(Ax.mono(8, .bold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: 2) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { c in
                                let i = r * 7 + c
                                cell(i < cells.count ? cells[i] : nil, today: today)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            OpenAxiomNote(title: "Roster month")
        }
    }

    private func cell(_ d: DayInfo?, today: String) -> some View {
        let isToday = d?.date == today
        return VStack(spacing: 1) {
            if let d = d {
                Text(String(d.date.suffix(2)).replacingOccurrences(of: #"^0"#, with: "", options: .regularExpression))
                    .font(Ax.mono(9, isToday ? .bold : .regular))
                    .foregroundStyle(d.date < today ? Color.secondary : Ax.ink)
                Text(d.chip.isEmpty ? " " : d.chip)
                    .font(Ax.mono(7, .bold))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(d.type == "FDP" ? Ax.paper : (d.type == "OFF" ? Color.secondary : Ax.ink))
                    .background(RoundedRectangle(cornerRadius: 3).fill(d.type == "FDP" ? Ax.ink : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(d.type == "FDP" || d.type.isEmpty ? Color.clear : Ax.ink.opacity(d.type == "OFF" ? 0.25 : 0.6), lineWidth: 0.8))
                    .opacity(d.date < today ? 0.45 : 1)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 5).strokeBorder(isToday ? Ax.ink : Color.clear, lineWidth: 1.2))
    }

    private func leadingBlanks(_ iso: String) -> Int {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wd = cal.component(.weekday, from: d)   // 1 = Sunday
        return (wd + 5) % 7                          // weeks start on Monday
    }

    private func monthTitle(_ ym: String) -> String {
        let names = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), m >= 1, m <= 12 else { return ym }
        return "\(names[m - 1]) \(parts[0])"
    }
}

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomMonth", provider: PayloadProvider(stepMinutes: 60, count: 6)) { e in
            MonthView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Roster month")
        .description("This month's roster as a calendar, with a chip for every duty.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Flight progress: where you are in today's sectors

struct FlightProgressView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: DutyEntry

    private struct LegState {
        let leg: Leg
        let flying: Bool          // true while airborne on this sector
        let progress: Double      // 0…1 through the sector
        let target: Date          // arrival when flying, departure otherwise
        let index: Int
        let total: Int
    }

    private func state(_ p: Payload) -> LegState? {
        let ms = entry.date.timeIntervalSince1970 * 1000
        // the duty you're on, or the next one with sectors (standby and reserve days have none)
        let timed: (Duty) -> [Leg] = { ($0.legs ?? []).filter { $0.depMs != nil && $0.arrMs != nil } }
        let current = p.duties.first(where: { $0.rep <= ms && $0.off > ms && !timed($0).isEmpty })
        let upcoming = p.duties.filter { $0.off > ms && !timed($0).isEmpty }.min(by: { $0.rep < $1.rep })
        guard let d = current ?? upcoming else { return nil }
        let legs = timed(d)
        for (i, l) in legs.enumerated() {
            let dep = l.depMs!, arr = l.arrMs!
            if ms >= dep && ms < arr {
                return LegState(leg: l, flying: true, progress: (ms - dep) / max(1, arr - dep), target: Date(timeIntervalSince1970: arr / 1000), index: i, total: legs.count)
            }
            if ms < dep {
                return LegState(leg: l, flying: false, progress: 0, target: Date(timeIntervalSince1970: dep / 1000), index: i, total: legs.count)
            }
        }
        return nil
    }

    var body: some View {
        if let p = entry.payload, let s = state(p) {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(s.leg.flt ?? "Sector") \(s.leg.from)›\(s.leg.to)").font(Ax.mono(13, .bold)).widgetAccentable()
                    ProgressView(value: s.progress).tint(.primary)
                    Text(s.flying ? "Lands \(s.leg.arr ?? "")" : "Departs \(s.leg.dep ?? "")").font(Ax.mono(11))
                }
            default:
                full(p, s)
            }
        } else if entry.payload == nil {
            OpenAxiomNote(title: "Flight")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Caption(text: "Flight")
                Spacer(minLength: 0)
                Text("No sectors ahead on your roster.").font(Ax.mono(12)).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func full(_ p: Payload, _ s: LegState) -> some View {
        let medium = family == .systemMedium
        VStack(alignment: .leading, spacing: medium ? 8 : 6) {
            HStack {
                Caption(text: medium ? (s.flying ? "In flight · sector \(s.index + 1) of \(s.total)" : "Next sector · \(s.index + 1) of \(s.total)")
                                     : (s.flying ? "In flight \(s.index + 1)/\(s.total)" : "Next \(s.index + 1)/\(s.total)"),
                        color: s.flying ? Ax.ink : .secondary)
                Spacer(minLength: 0)
                if medium { ExampleTag(demo: p.demo) }
            }
            Text(s.leg.flt ?? "Sector").font(Ax.mono(medium ? 18 : 15, .bold))
            // the route as a dotted line with the aircraft dot along it
            HStack(spacing: 6) {
                Text(s.leg.from).font(Ax.mono(medium ? 16 : 13, .bold))
                GeometryReader { g in
                    let n = max(8, Int(g.size.width / 7))
                    let at = Int((s.progress * Double(n - 1)).rounded())
                    HStack(spacing: 0) {
                        ForEach(0..<n, id: \.self) { i in
                            Circle()
                                .fill(i == at && s.flying ? Ax.red : (i < at ? Ax.ink : Ax.ink.opacity(0.18)))
                                .frame(width: i == at && s.flying ? 8 : 4, height: i == at && s.flying ? 8 : 4)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: g.size.height)
                }
                .frame(height: 10)
                Text(s.leg.to).font(Ax.mono(medium ? 16 : 13, .bold))
            }
            HStack {
                Text("\(s.leg.dep ?? "") → \(s.leg.arr ?? "")").font(Ax.mono(11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline) {
                Caption(text: s.flying ? "Lands in" : "Departs in")
                Spacer(minLength: 0)
                DotText(text: Fmt.countdown(s.target.timeIntervalSince(entry.date)), height: medium ? 20 : 15)
            }
        }
    }
}

struct FlightProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomFlight", provider: DutyProvider()) { e in
            FlightProgressView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Flight progress")
        .description("While you fly: the sector, a dot moving along the route and time to landing. Otherwise your next departure.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
