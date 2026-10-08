import SwiftUI
import WidgetKit
#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
#endif

// MARK: - Next alarm: the next duty alarm or alarm of your own

struct AlarmView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: PayloadEntry

    /// Duty alarms read in Bangkok time like the rest of Axiom; your own alarms follow the phone's clock.
    private func time(_ i: AlarmItem, _ d: Date) -> String {
        i.isDuty ? TimeFmt.hm(d) : TimeFmt.hm(d, TimeZone.current.identifier)
    }
    private func day(_ i: AlarmItem, _ d: Date) -> String {
        TimeFmt.f("EEE", i.isDuty ? "Asia/Bangkok" : TimeZone.current.identifier).string(from: d).uppercased()
    }

    var body: some View {
        if let n = entry.payload?.alarms?.next(after: entry.date) {
            let item = n.item, at = n.at
            switch family {
            case .accessoryInline:
                Label("\(time(item, at)) \(item.title)", systemImage: "alarm")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "alarm.fill").font(.system(size: 11, weight: .bold))
                        Text(time(item, at)).font(Ax.mono(15, .bold))
                    }
                    .widgetAccentable()
                    Text(item.title).font(Ax.mono(12)).lineLimit(1)
                    Text("in \(Fmt.countdown(at.timeIntervalSince(entry.date)).lowercased())").font(Ax.mono(11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: "alarm.fill").font(.system(size: 10, weight: .bold))
                        Caption(text: "Alarm")
                        Spacer(minLength: 0)
                        Caption(text: day(item, at))
                    }
                    Spacer(minLength: 0)
                    DotText(text: time(item, at), height: 34, showUnlit: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(item.title).font(Ax.mono(12, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack {
                        Text(item.sub?.isEmpty == false ? item.sub! : (item.at == nil ? "Repeats" : "Once"))
                            .font(Ax.mono(10)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(Fmt.countdown(at.timeIntervalSince(entry.date))).font(Ax.mono(11, .bold))
                    }
                }
            }
        } else if entry.payload == nil {
            OpenAxiomNote(title: "Alarm")
        } else {
            switch family {
            case .accessoryInline: Label("No alarm", systemImage: "alarm")
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Caption(text: "Alarm")
                    Spacer(minLength: 0)
                    Text(entry.payload?.alarms == nil ? "Open Axiom to turn on the alarm clock." : "No alarm set.")
                        .font(Ax.mono(12)).lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct AlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomAlarm", provider: PayloadProvider(stepMinutes: 5, count: 36)) { e in
            AlarmView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Next alarm")
        .description("Your next alarm from Axiom: the one before your next duty, or one you set yourself.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Snooze countdown on the Lock Screen and in the Dynamic Island
// The ringing screen itself is the iPhone's own; this is what shows while an alarm is snoozed.

/// Plain values, so the tests can draw it without a running alarm.
struct SnoozeCard: View {
    let title: String
    let sub: String
    let fireDate: Date?          // nil while paused
    var remaining: TimeInterval = 0

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "zzz").font(.system(size: 11, weight: .bold)).foregroundStyle(Ax.yellow)
                    Text("SNOOZE").font(Ax.mono(11, .bold)).tracking(1.2).foregroundStyle(Ax.yellow)
                }
                Text(title).font(Ax.mono(15, .bold)).foregroundStyle(.white).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(Ax.mono(11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Group {
                if let f = fireDate {
                    Text(timerInterval: Date()...max(Date(), f), countsDown: true)
                } else {
                    Text(Fmt.mmss(remaining))
                }
            }
            .font(.system(size: 40, weight: .heavy, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.white)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 150, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

extension Fmt {
    /// "08:41"
    static func mmss(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AxiomAlarmMeta>.self) { context in
            SnoozeCard(title: context.attributes.metadata?.title ?? "Alarm",
                       sub: context.attributes.metadata?.sub ?? "",
                       fireDate: Self.fireDate(context.state),
                       remaining: Self.remaining(context.state))
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(Ax.yellow)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Snooze", systemImage: "zzz").font(Ax.mono(12, .bold)).foregroundStyle(Ax.yellow)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Self.countdown(context.state).font(.system(size: 22, weight: .heavy, design: .monospaced)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.metadata?.title ?? "Alarm").font(Ax.mono(13)).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(Ax.yellow)
            } compactTrailing: {
                Self.countdown(context.state).font(.system(size: 14, weight: .bold, design: .monospaced)).monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "zzz").foregroundStyle(Ax.yellow)
            }
            .keylineTint(Ax.yellow)
        }
    }

    static func fireDate(_ s: AlarmPresentationState) -> Date? {
        if case .countdown(let c) = s.mode { return c.fireDate }
        return nil
    }

    static func remaining(_ s: AlarmPresentationState) -> TimeInterval {
        if case .paused(let p) = s.mode { return p.totalCountdownDuration - p.previouslyElapsedDuration }
        return 0
    }

    @ViewBuilder static func countdown(_ s: AlarmPresentationState) -> some View {
        if let f = fireDate(s) {
            Text(timerInterval: Date()...max(Date(), f), countsDown: true)
        } else {
            Text(Fmt.mmss(remaining(s)))
        }
    }
}
#endif
