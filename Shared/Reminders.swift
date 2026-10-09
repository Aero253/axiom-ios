import Foundation
import UserNotifications

/// One notification the dashboard asks for (duty reminders: bedtime, time to leave, report soon).
struct Reminder: Codable, Hashable {
    var key: String
    var at: Double          // ms since 1970
    var title: String
    var body: String
}

struct NotifyPlan: Codable, Hashable {
    var duty: [Reminder]
    var water: Bool
}

/// Axiom's notifications. Scheduled ahead on the phone, so they arrive with the app closed and no internet.
/// Called by the app whenever the dashboard saves, and by the Water widget's + so the water reminders follow your glasses.
enum Reminders {
    static let prefix = "axiom.rem."
    static let waterHours = [10, 12, 14, 16, 18, 20]

    /// How many glasses you'd want by `hour` to reach the goal by 22:00, starting at 08:00.
    static func expected(goal: Int, hour: Int) -> Int {
        Int((Double(goal) * Double(hour - 8) / 14.0).rounded(.up))
    }

    /// The water reminders still worth sending: today and tomorrow, only at times you're behind.
    static func waterTimes(now: Date, water: Water, calendar: Calendar = .current) -> [(at: Date, have: Int, want: Int)] {
        var out: [(Date, Int, Int)] = []
        let start = calendar.startOfDay(for: now)
        for day in 0...1 {
            guard let d = calendar.date(byAdding: .day, value: day, to: start) else { continue }
            for h in waterHours {
                guard let at = calendar.date(bySettingHour: h, minute: 0, second: 0, of: d), at > now else { continue }
                let have = day == 0 ? water.n : 0
                let want = expected(goal: water.goal, hour: h)
                if have < want { out.append((at, have, want)) }
            }
        }
        return out
    }

    /// Replace Axiom's waiting notifications with what `payload` asks for.
    /// `ask`: may show the iPhone's "allow notifications" question (only from the app, never from a widget).
    static func sync(_ payload: Payload?, ask: Bool) async {
        guard let p = payload else { return }
        let plan = p.notify
        let wantsAny = !(plan?.duty.isEmpty ?? true) || plan?.water == true
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined && wantsAny && ask {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard [UNAuthorizationStatus.authorized, .provisional, .ephemeral].contains(status), let plan = plan else { return }

        let cal = Calendar.current
        let now = Date()
        var requests: [UNNotificationRequest] = []
        for r in plan.duty {
            let at = Date(timeIntervalSince1970: r.at / 1000)
            guard at > now else { continue }
            let c = UNMutableNotificationContent()
            c.title = r.title
            c.body = r.body
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            c.threadIdentifier = "axiom.duty"
            requests.append(UNNotificationRequest(identifier: prefix + "duty." + r.key, content: c,
                trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at), repeats: false)))
        }
        if plan.water {
            let w = Shared.waterToday(p)
            for (at, have, _) in waterTimes(now: now, water: w, calendar: cal) {
                let c = UNMutableNotificationContent()
                c.title = "Drink water"
                c.body = have == 0 ? "No water yet today. Have a glass now." : "\(have) of \(w.goal) glasses so far. Time for another."
                c.sound = .default
                c.threadIdentifier = "axiom.water"
                requests.append(UNNotificationRequest(identifier: prefix + "water." + String(Int(at.timeIntervalSince1970)), content: c,
                    trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: at), repeats: false)))
            }
        }
        for r in requests.prefix(36) { try? await center.add(r) }   // iOS keeps 64 waiting notifications per app; leave room for alarms
    }
}
