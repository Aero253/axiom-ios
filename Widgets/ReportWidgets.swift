import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit

// MARK: - Report countdown: Dynamic Island and Lock Screen
// Yellow countdown while there's time; red with caution tape for the last 30 minutes, like the dashboard's LED ticker.
// iOS draws the island's and the card's shape; these views only fill them, inside the standard margins.

struct ReportLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReportAttributes.self) { context in
            let red = context.isStale || context.state.isRed()
            ReportCard(st: context.state, red: red)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(red ? Ax.red : Ax.yellow)
        } dynamicIsland: { context in
            let st = context.state, red = context.isStale || st.isRed()
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ReportIsland.ReportTime(st: st)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ReportIsland.TimeLeft(st: st, red: red)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ReportIsland.Route(st: st, red: red)
                }
            } compactLeading: {
                ReportIsland.CompactLeading(st: st, red: red)
            } compactTrailing: {
                ReportIsland.CompactTrailing(st: st, red: red)
            } minimal: {
                Image(systemName: "airplane").foregroundStyle(red ? Ax.red : Ax.yellow)
            }
            .keylineTint(red ? Ax.red : Ax.yellow)
        }
    }
}

/// Counts down to report. `fixed` is for the preview pictures, which can't run a clock.
struct ReportCountdown: View {
    let report: Date
    var fixed: TimeInterval? = nil

    var body: some View {
        if let f = fixed {
            Text(Self.text(f))
        } else {
            Text(timerInterval: Date()...max(Date(), report), countsDown: true)
        }
    }

    /// "1:19:42", "28:14", the way iOS shows a running timer.
    static func text(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded())), h = s / 3600, m = (s % 3600) / 60, ss = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, ss) : String(format: "%d:%02d", m, ss)
    }
}

/// The red "GO" / "TIME TO GO" badge, as on the ticker.
struct GoPill: View {
    let text: String
    var size: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.axiomDots(size))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.32)
            .background(Capsule().fill(Ax.red))
    }
}

/// The app's 5-dot mark (corners and centre of a 3 × 3 grid).
struct FiveDots: View {
    var dot: CGFloat = 4

    var body: some View {
        Grid(horizontalSpacing: dot / 2, verticalSpacing: dot / 2) {
            ForEach(0..<3) { r in
                GridRow {
                    ForEach(0..<3) { c in
                        Circle().fill((r + c) % 2 == 0 ? Color.white : Color.white.opacity(0.18)).frame(width: dot, height: dot)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private func capText(_ s: String) -> some View {
    Text(s.uppercased()).font(Ax.mono(10, .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
}

/// Lock Screen card.
struct ReportCard: View {
    let st: ReportAttributes.ContentState
    let red: Bool
    var fixed: TimeInterval? = nil

    private var footer: String {
        var parts = st.flights
        if let off = st.off { parts.append("Off duty \(TimeFmt.hm(off))") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if red { GoPill(text: "TIME TO GO", size: 12) }
                else { capText("Next \(st.what) · \(TimeFmt.day(st.report))").minimumScaleFactor(0.7) }
                Spacer(minLength: 8)
                FiveDots()
            }
            Text(st.route.joined(separator: " › "))
                .font(.axiomDots(24))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .padding(.top, 12)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    capText(st.what == "Report" ? "Report" : "Starts")
                    Text(TimeFmt.hm(st.report)).font(.axiomDots(26)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    capText("In")
                    ReportCountdown(report: st.report, fixed: fixed)
                        .font(.axiomDots(red ? 30 : 26))
                        .foregroundStyle(red ? Ax.red : Ax.yellow)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .frame(maxWidth: 170, alignment: .trailing)
                }
            }
            .padding(.top, 12)
            if !footer.isEmpty {
                Text(footer).font(Ax.mono(11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, red ? 18 : 16)
        .overlay(alignment: .top) { if red { CautionTape(color: Ax.red).frame(height: 6) } }
        .overlay(alignment: .bottom) { if red { CautionTape(color: Ax.red).frame(height: 6) } }
    }
}

/// The island's pieces, kept separate so the preview tests can lay them out too.
enum ReportIsland {
    struct ReportTime: View {
        let st: ReportAttributes.ContentState
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                capText(st.what == "Report" ? "Report" : "Starts")
                Text(TimeFmt.hm(st.report)).font(.axiomDots(22)).foregroundStyle(.white).lineLimit(1)
            }
            .padding(.leading, 4)
        }
    }

    struct TimeLeft: View {
        let st: ReportAttributes.ContentState
        let red: Bool
        var fixed: TimeInterval? = nil
        var body: some View {
            VStack(alignment: .trailing, spacing: 6) {
                capText("In")
                ReportCountdown(report: st.report, fixed: fixed)
                    .font(.axiomDots(22))
                    .foregroundStyle(red ? Ax.red : Ax.yellow)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.trailing, 4)
        }
    }

    struct Route: View {
        let st: ReportAttributes.ContentState
        let red: Bool
        var body: some View {
            VStack(spacing: 8) {
                Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
                HStack(spacing: 8) {
                    if red { GoPill(text: "GO", size: 11) }
                    Text(st.route.joined(separator: " › "))
                        .font(.axiomDots(14)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                    Text(st.flights.joined(separator: " · "))
                        .font(Ax.mono(11)).foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
    }

    struct CompactLeading: View {
        let st: ReportAttributes.ContentState
        let red: Bool
        var body: some View {
            if red {
                GoPill(text: "GO", size: 11)
            } else {
                Text(st.flights.first ?? "RPT")
                    .font(.axiomDots(13)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: 62, alignment: .leading)
            }
        }
    }

    struct CompactTrailing: View {
        let st: ReportAttributes.ContentState
        let red: Bool
        var fixed: TimeInterval? = nil
        var body: some View {
            ReportCountdown(report: st.report, fixed: fixed)
                .font(.axiomDots(13))
                .foregroundStyle(red ? Ax.red : Ax.yellow)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(width: 62, alignment: .trailing)
        }
    }
}
#endif
