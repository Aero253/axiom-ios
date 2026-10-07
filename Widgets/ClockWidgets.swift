import SwiftUI
import WidgetKit

// MARK: - Clock: Bangkok time in big dots, with UTC

struct MinuteEntry: TimelineEntry {
    let date: Date
    let payload: Payload?
}

/// One entry per minute for the next two hours, so the dot clock stays on time.
struct MinuteProvider: TimelineProvider {
    func placeholder(in context: Context) -> MinuteEntry { MinuteEntry(date: Date(), payload: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (MinuteEntry) -> Void) {
        completion(MinuteEntry(date: Date(), payload: Shared.load() ?? (context.isPreview ? .sample : nil)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MinuteEntry>) -> Void) {
        let p = Shared.load()
        let start = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60)
        let entries = (0..<120).map { MinuteEntry(date: start.addingTimeInterval(Double($0) * 60), payload: p) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct ClockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MinuteEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(text: "Bangkok · UTC+7")
            Spacer(minLength: 0)
            DotText(text: TimeFmt.hm(entry.date), height: 40, showUnlit: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(TimeFmt.day(entry.date)).font(Ax.mono(13, .bold))
            Caption(text: "UTC \(TimeFmt.hm(entry.date, "UTC"))Z")
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                Caption(text: "World")
                ForEach((entry.payload?.world ?? []).filter { $0.code != "UTC" }.prefix(3), id: \.self) { c in
                    HStack(spacing: 6) {
                        Text(c.code).font(Ax.mono(12, .bold))
                        Spacer(minLength: 0)
                        Text(TimeFmt.hm(entry.date, c.tz)).font(Ax.mono(15, .bold))
                    }
                }
                Spacer(minLength: 0)
                if let st = entry.payload?.status(at: entry.date) {
                    Caption(text: st.onDuty ? "Off duty \(st.duty.end ?? "")" : "Next \(st.duty.what.lowercased()) \(st.duty.start ?? "")", color: Ax.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomClock", provider: MinuteProvider()) { e in
            ClockView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Clock")
        .description("Bangkok time in big dots, with UTC. The medium size adds your world cities.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - World clock: your cities from the dashboard, live

struct WorldClockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PayloadEntry

    var body: some View {
        let cities = entry.payload?.world ?? []
        if entry.payload == nil {
            OpenAxiomNote(title: "World clock")
        } else {
            let limit = family == .systemLarge ? 9 : family == .systemMedium ? 4 : 3
            VStack(alignment: .leading, spacing: family == .systemLarge ? 9 : 6) {
                HStack {
                    Caption(text: "World clock")
                    Spacer(minLength: 0)
                    Caption(text: "BKK \(TimeFmt.hm(entry.date))")
                }
                ForEach(cities.prefix(limit), id: \.self) { c in
                    row(c)
                    if family == .systemLarge, c != cities.prefix(limit).last {
                        Rectangle().fill(Ax.ink.opacity(0.12)).frame(height: 1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ c: WorldCity) -> some View {
        let tz = TimeZone(identifier: c.tz) ?? .current
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(c.code).font(Ax.mono(family == .systemSmall ? 12 : 13, .bold))
                if family != .systemSmall {
                    Text(c.name + (c.roster ? " · roster" : "")).font(Ax.mono(10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if family != .systemSmall {
                Text(TimeFmt.offset(c.tz, at: entry.date)).font(Ax.mono(10)).foregroundStyle(.secondary)
            }
            // a live clock in that city's time zone; the system keeps it ticking
            Text(entry.date, style: .time)
                .environment(\.timeZone, tz)
                .environment(\.locale, Locale(identifier: "en_GB"))
                .font(Ax.mono(family == .systemLarge ? 22 : 17, .bold))
                .monospacedDigit()
        }
    }
}

struct WorldClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomWorld", provider: PayloadProvider(stepMinutes: 30, count: 8)) { e in
            WorldClockView(entry: e).axiomBackground()
        }
        .configurationDisplayName("World clock")
        .description("UTC, your roster layovers and the cities you added in Axiom.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
