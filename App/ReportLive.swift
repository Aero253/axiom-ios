import Foundation
import ActivityKit
import BackgroundTasks

/// Starts, updates and ends the report countdown. Live Activities can only start while Axiom is open,
/// so this runs whenever the dashboard saves and whenever the app comes to the front.
enum ReportLive {
    /// iOS keeps a Live Activity in the Dynamic Island for 8 hours at most, so it starts within 8 hours of report.
    static let window: TimeInterval = 8 * 3600
    static let endTask = "com.aero253.axiom.report-end"

    static func key(_ d: Duty) -> String { "\(Int(d.rep))" }

    /// The duty to count down to: the next flight duty or airport standby reporting within the window.
    static func next(_ p: Payload?, now: Date = Date()) -> Duty? {
        guard let p = p, !p.demo else { return nil }
        let ms = now.timeIntervalSince1970 * 1000
        return p.duties
            .filter { ($0.type == "FDP" || $0.type == "ASBY") && $0.rep > ms && $0.rep - ms <= window * 1000 }
            .min { $0.rep < $1.rep }
    }

    /// Still on screen: counting down, or past the red moment (iOS marks it "stale" then, which is how it turns red).
    static func alive(_ a: Activity<ReportAttributes>) -> Bool { a.activityState == .active || a.activityState == .stale }

    @MainActor private static var running = false
    @MainActor private static var again = false

    /// One at a time: the app coming to the front and the dashboard saving often happen together, and two overlapping
    /// runs could start the countdown twice or end the one just started. A call made during a run makes it run once more.
    @MainActor
    static func sync(_ p: Payload?, now: Date = Date()) async {
        if running { again = true; return }
        running = true
        await apply(p, now: now)
        while again { again = false; await apply(Shared.load() ?? p, now: Date()) }
        running = false
    }

    @MainActor
    private static func apply(_ p: Payload?, now: Date) async {
        let want = next(p, now: now)
        for a in Activity<ReportAttributes>.activities {
            if let d = want, a.attributes.key == key(d), alive(a) {
                let st = ReportAttributes.ContentState(duty: d)
                if a.content.state != st { await a.update(ActivityContent(state: st, staleDate: st.redAt)) }
            } else {
                await a.end(nil, dismissalPolicy: .immediate)   // reported already, or the roster changed
            }
        }
        guard let d = want, ActivityAuthorizationInfo().areActivitiesEnabled,
              !Activity<ReportAttributes>.activities.contains(where: { $0.attributes.key == key(d) && alive($0) }) else { return }
        let st = ReportAttributes.ContentState(duty: d)
        do {
            _ = try Activity.request(attributes: ReportAttributes(key: key(d)),
                                     content: ActivityContent(state: st, staleDate: st.redAt, relevanceScore: 60),
                                     pushType: nil)
            scheduleEnd(at: d.repDate)
        } catch {
            // not allowed (Live Activities off in Settings) or too many running: nothing to show
        }
    }

    /// Ask iOS to wake Axiom briefly at report time to take the countdown away. iOS decides when (often a little later);
    /// opening Axiom ends it too, and iOS itself removes it after 8 hours.
    static func scheduleEnd(at date: Date) {
        let r = BGAppRefreshTaskRequest(identifier: endTask)
        r.earliestBeginDate = date.addingTimeInterval(60)
        try? BGTaskScheduler.shared.submit(r)
    }

    static func registerEndTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: endTask, using: nil) { task in
            let job = Task { @MainActor in
                await sync(Shared.load())
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { job.cancel() }
        }
    }
}
