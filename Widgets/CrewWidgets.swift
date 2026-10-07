import SwiftUI
import WidgetKit

// MARK: - Duty hours (FTL): rolling totals against the limits

struct DutyHoursView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: PayloadEntry

    var body: some View {
        if let f = entry.payload?.ftl {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(f.duty28, f.lim.duty28), in: 0...f.lim.duty28) {
                    Text("28d")
                } currentValueLabel: {
                    Text("\(Int(f.duty28.rounded()))")
                }
                .gaugeStyle(.accessoryCircular)
            case .systemMedium:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Caption(text: "Duty hours · rolling")
                        Spacer(minLength: 0)
                        ExampleTag(demo: entry.payload?.demo ?? false)
                    }
                    row("Duty 7d", f.duty7, f.lim.duty7)
                    row("Duty 14d", f.duty14, f.lim.duty14)
                    row("Duty 28d", f.duty28, f.lim.duty28)
                    row("Flight 28d", f.flight28, f.lim.flight28)
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 5) {
                    Caption(text: "Duty · 28 days")
                    Spacer(minLength: 0)
                    DotText(text: TimeFmt.hours(f.duty28), height: 26, showUnlit: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Caption(text: "of \(Int(f.lim.duty28)) h", color: f.duty28 > f.lim.duty28 ? Ax.red : .secondary)
                    DotBar(value: f.duty28, limit: f.lim.duty28, count: 14, dot: 6)
                    Spacer(minLength: 0)
                    HStack {
                        Caption(text: "Flight 28d")
                        Spacer(minLength: 0)
                        Text("\(TimeFmt.hours(f.flight28))/\(Int(f.lim.flight28))").font(Ax.mono(11, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        } else {
            OpenAxiomNote(title: "Duty hours")
        }
    }

    private func row(_ label: String, _ v: Double, _ lim: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Ax.mono(10)).foregroundStyle(.secondary).lineLimit(1).frame(width: 66, alignment: .leading)
            DotBar(value: v, limit: lim, count: 16, dot: 5.5)
            Spacer(minLength: 0)
            Text("\(TimeFmt.hours(v))/\(Int(lim))").font(Ax.mono(11, .bold)).foregroundStyle(v > lim ? Ax.red : Ax.ink)
        }
    }
}

struct DutyHoursWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomDutyHours", provider: PayloadProvider(stepMinutes: 30, count: 8)) { e in
            DutyHoursView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Duty hours")
        .description("Rolling duty and flight hours against the limits (60 / 110 / 190 h, 100 h flying). Red past a limit.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

// MARK: - Rest: how much rest you've had and when you're legal again

struct RestView: View {
    let entry: PayloadEntry

    var body: some View {
        if let p = entry.payload, let f = p.ftl {
            let ms = entry.date.timeIntervalSince1970 * 1000
            let onDuty = p.duties.first(where: { $0.rep <= ms && $0.off > ms })
            let next = p.duties.filter { $0.rep > ms }.min(by: { $0.rep < $1.rep })
            let lastOff = p.duties.filter { $0.off <= ms }.map(\.off).max() ?? f.lastOff
            let away = p.duties.filter { $0.off <= ms }.max(by: { $0.off < $1.off })?.away ?? (f.lastAway ?? false)
            let minH = away ? f.lim.restAway : f.lim.restHome
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Caption(text: onDuty != nil ? "On duty" : "Rest")
                    Spacer(minLength: 0)
                    Caption(text: away ? "Away · \(Int(minH))h" : "Home · \(Int(minH))h")
                }
                Spacer(minLength: 0)
                if let d = onDuty {
                    Text("Off duty \(d.end ?? "")").font(Ax.mono(14, .bold))
                    Caption(text: "Rest starts then")
                } else if let off = lastOff {
                    let had = (ms - off) / 3_600_000
                    let legalAt = off + minH * 3_600_000
                    DotText(text: TimeFmt.hours(max(0, had)), height: 24, showUnlit: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Caption(text: "rest so far")
                    DotBar(value: min(had, minH), limit: minH, count: 14, dot: 6)
                    Spacer(minLength: 0)
                    if ms < legalAt {
                        Text("Legal at \(TimeFmt.hm(ms: legalAt))").font(Ax.mono(11, .bold))
                    } else if let n = next {
                        let gap = (n.rep - off) / 3_600_000
                        Text(gap >= minH ? "Rest OK · next \(n.start ?? "")" : "Short by \(TimeFmt.hours(minH - gap))")
                            .font(Ax.mono(11, .bold))
                            .foregroundStyle(gap >= minH ? Ax.ink : Ax.red)
                    } else {
                        Text("Minimum rest met").font(Ax.mono(11, .bold))
                    }
                } else {
                    Text("No recent duty on the roster.").font(Ax.mono(11))
                }
            }
        } else {
            OpenAxiomNote(title: "Rest")
        }
    }
}

struct RestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomRest", provider: PayloadProvider(stepMinutes: 5, count: 36)) { e in
            RestView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Rest")
        .description("Rest since your last duty, the time you're legal again (12 h at home, 10 h away), and whether the next report leaves enough.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Wake-up: alarm, bedtime and leaving time for the next report

struct WakeView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: PayloadEntry

    var body: some View {
        if let w = entry.payload?.wake, w.rep > entry.date.timeIntervalSince1970 * 1000 {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Alarm \(TimeFmt.hm(ms: w.alarm))").font(Ax.mono(14, .bold)).widgetAccentable()
                    Text("Bed by \(TimeFmt.hm(ms: w.bed))").font(Ax.mono(12))
                    Text("\(w.what) \(TimeFmt.hm(ms: w.rep))").font(Ax.mono(12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Caption(text: "Alarm")
                        Spacer(minLength: 0)
                        if let f = w.flt { Caption(text: f) }
                    }
                    Spacer(minLength: 0)
                    DotText(text: TimeFmt.hm(ms: w.alarm), height: 34, showUnlit: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    line("Bed by", TimeFmt.hm(ms: w.bed))
                    line("Leave", TimeFmt.hm(ms: w.leave))
                    line(w.what, TimeFmt.hm(ms: w.rep))
                }
            }
        } else if entry.payload == nil {
            OpenAxiomNote(title: "Wake-up")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Caption(text: "Wake-up")
                Spacer(minLength: 0)
                Text("No report ahead on your roster.").font(Ax.mono(12)).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Ax.mono(10)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(v).font(Ax.mono(12, .bold))
        }
    }
}

struct WakeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomWake", provider: PayloadProvider(stepMinutes: 15, count: 16)) { e in
            WakeView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Wake-up")
        .description("When to set the alarm, go to bed and leave home for your next report, from the Wake-up planner in Axiom.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Layover: the night-stop city, its local time, hotel and pickup

struct LayoverView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: PayloadEntry

    var body: some View {
        if let lays = entry.payload?.lays, let l = lays.first {
            let tz = TimeZone(identifier: l.tz) ?? .current
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Caption(text: "Layover")
                    Spacer(minLength: 0)
                    Caption(text: TimeFmt.day(Date(timeIntervalSince1970: l.arr / 1000), l.tz))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(l.to).font(Ax.mono(family == .systemMedium ? 22 : 18, .bold))
                    Text(l.name).font(Ax.mono(11)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    Caption(text: "Local")
                    Text(entry.date, style: .time)
                        .environment(\.timeZone, tz)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                        .font(Ax.mono(14, .bold))
                    Text(TimeFmt.offset(l.tz, at: entry.date)).font(Ax.mono(10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let h = l.hotel, !h.isEmpty {
                    Text(h + (l.room.map { $0.isEmpty ? "" : " · room \($0)" } ?? "")).font(Ax.mono(11, .semibold)).lineLimit(family == .systemMedium ? 2 : 1).minimumScaleFactor(0.8)
                }
                if let pm = l.pickupMs, pm > entry.date.timeIntervalSince1970 * 1000 {
                    if family == .systemMedium {
                        HStack {
                            Caption(text: "Pickup \(l.pickup ?? "") local")
                            Spacer(minLength: 0)
                            Text(Date(timeIntervalSince1970: pm / 1000), style: .timer).font(Ax.mono(12, .bold)).multilineTextAlignment(.trailing)
                        }
                    } else {
                        Caption(text: "Pickup \(l.pickup ?? "") · in")
                        Text(Date(timeIntervalSince1970: pm / 1000), style: .timer).font(Ax.mono(12, .bold))
                    }
                } else if l.hotel == nil {
                    Caption(text: "Add the hotel and pickup in Axiom")
                }
            }
        } else if entry.payload == nil {
            OpenAxiomNote(title: "Layover")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Caption(text: "Layover")
                Spacer(minLength: 0)
                Text("No night-stops in the next 14 days.").font(Ax.mono(12)).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LayoverWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomLayover", provider: PayloadProvider(stepMinutes: 30, count: 8)) { e in
            LayoverView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Layover")
        .description("Your next night-stop: local time, hotel, room and a countdown to pickup.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
