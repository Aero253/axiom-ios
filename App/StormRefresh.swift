import Foundation
import BackgroundTasks

/// Lets iOS wake Axiom now and then (about hourly, when it allows) to look for storms where you are,
/// so alerts can come even without the Weather widget on the Home Screen.
enum StormRefresh {
    static let task = "com.aero253.axiom.weather"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: task, using: nil) { t in
            schedule()
            let job = Task { await StormWatch.run(Shared.load()); t.setTaskCompleted(success: true) }
            t.expirationHandler = { job.cancel() }
        }
    }

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: task)
        r.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    /// The app has come to the front: look now (after the new location has had a moment to arrive), and book the next look.
    static func onOpen() {
        schedule()
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await StormWatch.run(Shared.load())
        }
    }
}
