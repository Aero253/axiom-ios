import SwiftUI
import WidgetKit

struct DutyEntry: TimelineEntry {
    let date: Date
    let payload: Payload?
}

struct DutyProvider: TimelineProvider {
    func placeholder(in context: Context) -> DutyEntry {
        DutyEntry(date: Date(), payload: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DutyEntry) -> Void) {
        let p = Shared.load()
        let usable = (p?.status(at: Date()) != nil) ? p : Payload.sample
        completion(DutyEntry(date: Date(), payload: context.isPreview ? usable : p))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DutyEntry>) -> Void) {
        let p = Shared.load()
        let now = Date()
        let start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        // one entry a minute keeps the countdown and the yellow/red badge on time for the next 90 minutes
        let entries = (0..<90).map { DutyEntry(date: start.addingTimeInterval(Double($0) * 60), payload: p) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct NextDutyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DutyEntry

    var body: some View {
        if let p = entry.payload, let st = p.status(at: entry.date) {
            switch family {
            case .systemMedium: medium(p, st)
            case .accessoryRectangular: rectangular(st)
            case .accessoryInline: inline(st)
            default: small(p, st)
            }
        } else {
            empty(entry.payload == nil)
        }
    }

    // MARK: pieces

    private func headline(_ st: DutyStatus) -> String {
        if st.onDuty { return "Off \(st.duty.end ?? "")" }
        return "\(st.duty.what) \(st.duty.start ?? "")"
    }

    private func route(_ d: Duty) -> String {
        d.route.isEmpty ? (d.flts.first ?? d.what) : d.route.joined(separator: " › ")
    }

    /// Yellow from 150 min before report, red from 35 min: the same windows as the dashboard ticker.
    private func alert(_ st: DutyStatus) -> (red: Bool, text: String)? {
        guard !st.onDuty else { return nil }
        let left = st.target.timeIntervalSince(entry.date)
        guard left > 0, left <= 150 * 60 else { return nil }
        if left <= 35 * 60 { return (true, "Go · \(Fmt.countdown(left))") }
        return (false, "\(st.duty.what) in \(Fmt.countdown(left))")
    }

    @ViewBuilder
    private func topLine(_ p: Payload, _ st: DutyStatus) -> some View {
        HStack(spacing: 6) {
            if let a = alert(st) {
                AlertPill(red: a.red, text: a.text)
            } else {
                Caption(text: st.onDuty ? "On duty · off in" : "Next duty in")
            }
            Spacer(minLength: 0)
            if p.demo { Caption(text: "Example") }
        }
    }

    @ViewBuilder
    private func small(_ p: Payload, _ st: DutyStatus) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            topLine(p, st)
            Spacer(minLength: 0)
            DotText(text: Fmt.countdown(st.target.timeIntervalSince(entry.date)), height: 30, showUnlit: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(headline(st))
                .font(Ax.mono(15, .bold))
                .lineLimit(1).minimumScaleFactor(0.7)
            Caption(text: Fmt.day(st.duty.date))
            Text(route(st.duty))
                .font(Ax.mono(11, .semibold))
                .lineLimit(1).minimumScaleFactor(0.55)
        }
    }

    @ViewBuilder
    private func medium(_ p: Payload, _ st: DutyStatus) -> some View {
        HStack(alignment: .top, spacing: 14) {
            small(p, st)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Caption(text: st.duty.legs?.isEmpty == false ? "Sectors" : st.duty.what)
                if let legs = st.duty.legs, !legs.isEmpty {
                    ForEach(Array(legs.prefix(4).enumerated()), id: \.offset) { _, l in
                        HStack(spacing: 6) {
                            Text(l.flt ?? "—").font(Ax.mono(11, .bold)).lineLimit(1)
                            Text("\(l.from)›\(l.to)").font(Ax.mono(11)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(l.dep ?? "").font(Ax.mono(11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .minimumScaleFactor(0.7)
                    }
                    if legs.count > 4 { Caption(text: "+\(legs.count - 4) more") }
                } else {
                    Text("\(st.duty.start ?? "")–\(st.duty.end ?? "")").font(Ax.mono(13, .bold))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func rectangular(_ st: DutyStatus) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(headline(st)) · \(Fmt.day(st.duty.date))")
                .font(Ax.mono(13, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                .widgetAccentable()
            Text(route(st.duty)).font(Ax.mono(12)).lineLimit(1).minimumScaleFactor(0.6)
            Text(st.target, style: .relative).font(Ax.mono(12)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ st: DutyStatus) -> some View {
        Text("\(headline(st)) · \(st.duty.flts.first ?? route(st.duty))")
    }

    @ViewBuilder
    private func empty(_ noData: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(text: "Next duty")
            Spacer(minLength: 0)
            Text(noData ? "Open Axiom once to connect the widgets." : "Nothing ahead. Import next month's eCrew PDF in Axiom.")
                .font(Ax.mono(12))
                .lineLimit(4).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NextDutyWidget: Widget {
    let kind = "AxiomNextDuty"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DutyProvider()) { entry in
            NextDutyView(entry: entry).axiomBackground()
        }
        .configurationDisplayName("Next duty")
        .description("Countdown to your next report, with the route. Turns yellow, then red, as report time gets close.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
