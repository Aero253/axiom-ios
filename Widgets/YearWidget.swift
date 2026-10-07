import SwiftUI
import WidgetKit

/// Day numbers for the year countdown, worked out on the Bangkok calendar.
struct YearInfo {
    let year: Int
    let dayOfYear: Int        // 1-based
    let daysInYear: Int
    let monthLengths: [Int]
    let month: Int            // 1-12
    let day: Int

    init(_ date: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        year = c.year ?? 2026
        month = c.month ?? 1
        day = c.day ?? 1
        dayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        daysInYear = leap ? 366 : 365
        monthLengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    }

    var daysLeft: Int { daysInYear - dayOfYear }
    var fraction: Double { Double(dayOfYear) / Double(daysInYear) }
}

struct YearEntry: TimelineEntry {
    let date: Date
}

struct YearProvider: TimelineProvider {
    func placeholder(in context: Context) -> YearEntry { YearEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (YearEntry) -> Void) { completion(YearEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<YearEntry>) -> Void) {
        let now = Date()
        let midnight = Shared.nextBangkokMidnight(after: now)
        completion(Timeline(entries: [YearEntry(date: now), YearEntry(date: midnight)],
                            policy: .after(midnight.addingTimeInterval(60))))
    }
}

/// Every day of the year as a dot: gone days lit, days to come dark, today ringed.
struct YearGrid: Shape {
    enum Kind { case gone, toCome, today }
    let info: YearInfo
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let step = min(rect.width / 31, rect.height / 12)
        let r = step * 0.36
        var p = Path()
        for (m, len) in info.monthLengths.enumerated() {
            for d in 0..<len {
                let isToday = m + 1 == info.month && d + 1 == info.day
                let gone = (m + 1 < info.month) || (m + 1 == info.month && d + 1 < info.day)
                let want: Bool
                switch kind {
                case .today: want = isToday
                case .gone: want = gone
                case .toCome: want = !gone && !isToday
                }
                guard want else { continue }
                let cx = rect.minX + (CGFloat(d) + 0.5) * step
                let cy = rect.minY + (CGFloat(m) + 0.5) * step
                let rr = kind == .today ? step * 0.42 : r
                p.addEllipse(in: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2))
            }
        }
        return p
    }
}

struct YearView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: YearEntry

    private static let monthLetters: [String] = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    var body: some View {
        let y = YearInfo(entry.date)
        switch family {
        case .systemMedium: medium(y)
        case .accessoryCircular:
            Gauge(value: y.fraction) {
                Text("\(y.year)")
            } currentValueLabel: {
                Text("\(y.daysLeft)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryInline:
            Text("\(y.daysLeft) days left in \(y.year)")
        default: small(y)
        }
    }

    private func summary(_ y: YearInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                DotText(text: "\(y.year)", height: 11)
                Spacer(minLength: 0)
                Caption(text: String(format: "%.0f%%", y.fraction * 100))
            }
            Spacer(minLength: 0)
            DotText(text: "\(y.daysLeft)", height: 42, showUnlit: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Caption(text: y.daysLeft == 1 ? "day left" : "days left")
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func small(_ y: YearInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            summary(y)
            progress(y, dots: 16)
        }
    }

    @ViewBuilder
    private func medium(_ y: YearInfo) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                summary(y)
                Caption(text: "Day \(y.dayOfYear) of \(y.daysInYear)")
            }
            .frame(width: 104)
            HStack(spacing: 4) {
                VStack(spacing: 0) {
                    ForEach(Self.monthLetters.indices, id: \.self) { i in
                        Text(Self.monthLetters[i])
                            .font(Ax.mono(7, i + 1 == y.month ? .bold : .regular))
                            .foregroundStyle(i + 1 == y.month ? Ax.ink : Color.secondary)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 8)
                ZStack {
                    YearGrid(info: y, kind: .toCome).fill(Ax.ink.opacity(0.16))
                    YearGrid(info: y, kind: .gone).fill(Ax.ink)
                    YearGrid(info: y, kind: .today).stroke(Ax.ink, lineWidth: 1.4)
                }
                .aspectRatio(31.0 / 12.0, contentMode: .fit)
            }
        }
    }

    private func progress(_ y: YearInfo, dots: Int) -> some View {
        let lit = Int((y.fraction * Double(dots)).rounded())
        return HStack(spacing: 3) {
            ForEach(0..<dots, id: \.self) { i in
                Circle()
                    .fill(i < lit ? Ax.ink : Ax.ink.opacity(0.16))
                    .frame(width: 5.5, height: 5.5)
            }
        }
    }
}

struct YearWidget: Widget {
    let kind = "AxiomYear"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: YearProvider()) { entry in
            YearView(entry: entry).axiomBackground()
        }
        .configurationDisplayName("Year")
        .description("Days left this year, with every day of the year as a dot.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}
