import SwiftUI
import WidgetKit
import AppIntents

// MARK: - To-do and Shopping: tick items off right on the Home Screen

struct ListView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PayloadEntry
    let list: String          // "todos" or "shopping"
    let title: String

    var body: some View {
        if entry.payload == nil {
            OpenAxiomNote(title: title)
        } else {
            let items = Shared.items(list, in: entry.payload)
            let open = items.filter { !$0.done }
            // unticked first, then the ones you've just ticked so they can be unticked again
            let shown = Array((open + items.filter { $0.done }).prefix(family == .systemLarge ? 11 : family == .systemMedium ? 4 : 3))
            VStack(alignment: .leading, spacing: family == .systemLarge ? 7 : 5) {
                HStack {
                    Caption(text: title)
                    Spacer(minLength: 0)
                    Caption(text: items.isEmpty ? "" : open.isEmpty ? "All done" : "\(open.count) open", color: Ax.ink)
                }
                if items.isEmpty {
                    Spacer(minLength: 0)
                    Text(list == "shopping" ? "Nothing to buy. Add items in Axiom." : "No tasks. Add them in Axiom.")
                        .font(Ax.mono(11)).foregroundStyle(.secondary).lineLimit(3)
                } else {
                    ForEach(shown, id: \.self) { item in
                        Button(intent: ToggleItemIntent(list: list, item: item.id)) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle().strokeBorder(Ax.ink, lineWidth: 1.5)
                                    if item.done { Circle().fill(Ax.ink).padding(3.5) }
                                }
                                .frame(width: 18, height: 18)
                                Text(item.text)
                                    .font(Ax.mono(12, .semibold))
                                    .strikethrough(item.done)
                                    .foregroundStyle(item.done ? Color.secondary : Ax.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let q = item.qty, !q.isEmpty {
                                    Text("×\(q)").font(Ax.mono(10)).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomTodo", provider: PayloadProvider(stepMinutes: 60, count: 4)) { e in
            ListView(entry: e, list: "todos", title: "To-do").axiomBackground()
        }
        .configurationDisplayName("To-do")
        .description("Your Axiom to-do list. Tap the circle to tick an item off; Axiom catches up next time you open it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomShopping", provider: PayloadProvider(stepMinutes: 60, count: 4)) { e in
            ListView(entry: e, list: "shopping", title: "Shopping").axiomBackground()
        }
        .configurationDisplayName("Shopping")
        .description("Your Axiom shopping list. Tap the circle to tick an item off as you shop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Countdown: days to leave, a trip home, a birthday

struct CountdownView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PayloadEntry

    private func days(_ iso: String) -> Int {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let a = f.date(from: Shared.todayISO(entry.date)), let b = f.date(from: iso) else { return 0 }
        return Int((b.timeIntervalSince(a) / 86400).rounded())
    }

    var body: some View {
        let items = (entry.payload?.counts ?? []).filter { days($0.date) >= 0 }
        if let first = items.first {
            switch family {
            case .accessoryInline:
                Text("\(first.title) in \(days(first.date))d")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(days(first.date)) days").font(Ax.mono(15, .bold)).widgetAccentable()
                    Text(first.title).font(Ax.mono(12)).lineLimit(1)
                    Text(Fmt.day(first.date)).font(Ax.mono(11))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                VStack(alignment: .leading, spacing: 7) {
                    Caption(text: "Countdown")
                    ForEach(items.prefix(3), id: \.self) { c in
                        HStack(alignment: .center, spacing: 10) {
                            DotText(text: "\(days(c.date))", height: 18).frame(width: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(c.title).font(Ax.mono(12, .semibold)).lineLimit(1)
                                Caption(text: Fmt.day(c.date))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 5) {
                    Caption(text: "Countdown")
                    Spacer(minLength: 0)
                    let n = days(first.date)
                    DotText(text: "\(n)", height: 44, showUnlit: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Caption(text: n == 0 ? "today" : n == 1 ? "day to go" : "days to go", color: Ax.ink)
                    Spacer(minLength: 0)
                    Text(first.title).font(Ax.mono(12, .bold)).lineLimit(2)
                    Caption(text: Fmt.day(first.date))
                }
            }
        } else if entry.payload == nil {
            OpenAxiomNote(title: "Countdown")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Caption(text: "Countdown")
                Spacer(minLength: 0)
                Text("Add leave, a trip home or a birthday in Axiom.").font(Ax.mono(11)).lineLimit(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomCountdown", provider: PayloadProvider(stepMinutes: 60, count: 6)) { e in
            CountdownView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Countdown")
        .description("Days to go until your next countdown event, including annual leave from your roster.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
