import SwiftUI
import WidgetKit
import AppIntents

struct WaterEntry: TimelineEntry {
    let date: Date
    let water: Water
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry {
        WaterEntry(date: Date(), water: Water(date: Shared.todayISO(), n: 3, goal: 8, ts: 0))
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) {
        completion(WaterEntry(date: Date(), water: Shared.waterToday(Shared.load())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntry>) -> Void) {
        let now = Date()
        let p = Shared.load()
        let midnight = Shared.nextBangkokMidnight(after: now)
        let today = WaterEntry(date: now, water: Shared.waterToday(p))
        // back to zero at midnight, Bangkok time, like the dashboard
        var fresh = today.water
        fresh.n = 0
        fresh.date = Shared.todayISO(midnight.addingTimeInterval(60))
        let tomorrow = WaterEntry(date: midnight, water: fresh)
        completion(Timeline(entries: [today, tomorrow], policy: .after(midnight.addingTimeInterval(60))))
    }
}

struct WaterView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WaterEntry

    var body: some View {
        let w = entry.water
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(min(w.n, w.goal)), in: 0...Double(max(w.goal, 1))) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text("\(w.n)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        default:
            small(w)
        }
    }

    /// Option D from the dashboard: the count sits in a ring and the + on its edge adds a glass.
    @ViewBuilder
    private func small(_ w: Water) -> some View {
        let reached = w.n >= w.goal
        VStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .stroke(Ax.ink, lineWidth: 2)
                    .overlay(
                        DotText(text: "\(w.n)", height: 30)
                            .padding(22)
                    )
                    .frame(width: 84, height: 84)
                Button(intent: AddGlassIntent()) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Ax.paper)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Ax.ink))
                        .overlay(Circle().stroke(Ax.paper, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: 4)
                .accessibilityLabel("Add one glass, 250 ml")
            }
            Caption(text: reached ? "Goal reached" : "\(Fmt.litres(w.n)) of \(Fmt.litres(w.goal))",
                    color: reached ? Ax.ink : .secondary)
            glasses(w)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func glasses(_ w: Water) -> some View {
        let count = max(w.goal, w.n)
        let d: CGFloat = count > 12 ? 5 : count > 9 ? 7 : 9
        return HStack(spacing: count > 12 ? 2 : 3) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .strokeBorder(Ax.ink, lineWidth: 1.2)
                    .background(Circle().fill(i < w.n ? Ax.ink : Color.clear))
                    .frame(width: d, height: d)
            }
        }
    }
}

struct WaterWidget: Widget {
    let kind = "AxiomWater"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WaterProvider()) { entry in
            WaterView(entry: entry).axiomBackground()
        }
        .configurationDisplayName("Water")
        .description("Today's glasses. Tap + to add one without opening Axiom.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
