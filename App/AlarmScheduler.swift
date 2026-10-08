import Foundation
import SwiftUI
import UserNotifications
import CryptoKit
#if canImport(AlarmKit)
import AlarmKit
#endif

/// What the dashboard is told about its alarms.
struct AlarmStatus: Encodable, Equatable {
    var mode: String        // "alarmkit" (rings like the Clock app) or "notify" (notifications, older iOS)
    var auth: String        // "authorized", "denied", "notDetermined"
    var count: Int          // alarms iOS is holding
    var error: String? = nil
}

/// Hands the dashboard's alarms to iOS.
/// iOS 26 and later: AlarmKit, so they ring through silent mode and Focus with the system alarm screen.
/// Earlier iOS: local notifications (a sound if the ringer is on).
@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()

    private var busy = false
    private var queued: AlarmSet?
    private var lastStatus: AlarmStatus?

    /// Bring iOS's alarms in line with `set`, then report back. Calls made while a sync is running are merged into one.
    func sync(_ set: AlarmSet, report: @escaping (AlarmStatus) -> Void) {
        if busy { queued = set; return }
        busy = true
        Task { @MainActor in
            var next: AlarmSet? = set
            var status = AlarmStatus(mode: "notify", auth: "notDetermined", count: 0)
            while let s = next {
                queued = nil
                status = await apply(s)
                next = queued
            }
            busy = false
            lastStatus = status
            report(status)
        }
    }

    private func apply(_ set: AlarmSet) async -> AlarmStatus {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return await applyAlarmKit(set) }
        #endif
        return await applyNotifications(set)
    }

    /// A stable ID for one alarm as it is now: the same alarm keeps its ID, a changed one gets a new ID (and the old one goes).
    nonisolated static func id(for item: AlarmItem, snooze: Int) -> UUID {
        let days = (item.days ?? []).sorted().map(String.init).joined(separator: ",")
        let sig = [item.key, item.at.map { String(Int64($0)) } ?? "", item.h.map(String.init) ?? "", item.m.map(String.init) ?? "",
                   days, item.title, item.sub ?? "", String(snooze)].joined(separator: "|")
        var b = Array(SHA256.hash(data: Data(sig.utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50     // a name-based UUID
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// Only what is still ahead, at most 40 (iOS limits how many alarms one app may hold).
    nonisolated static func upcoming(_ set: AlarmSet, now: Date = Date()) -> [AlarmItem] {
        Array(set.list.filter { $0.at == nil ? ($0.h != nil && $0.m != nil) : $0.at! / 1000 > now.timeIntervalSince1970 + 5 }.prefix(40))
    }

    // MARK: AlarmKit (iOS 26+)

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func applyAlarmKit(_ set: AlarmSet) async -> AlarmStatus {
        let manager = AlarmManager.shared
        let items = Self.upcoming(set)
        var auth = manager.authorizationState
        if auth == .notDetermined && !items.isEmpty {
            auth = (try? await manager.requestAuthorization()) ?? manager.authorizationState
        }
        guard auth == .authorized else {
            return AlarmStatus(mode: "alarmkit", auth: auth == .denied ? "denied" : "notDetermined", count: 0)
        }
        var want: [UUID: AlarmItem] = [:]
        for i in items { want[Self.id(for: i, snooze: set.snooze)] = i }
        let have = (try? manager.alarms) ?? []
        // drop alarms that changed or were removed; never touch one that is ringing or snoozing
        for a in have where want[a.id] == nil && a.state == .scheduled {
            try? manager.cancel(id: a.id)
        }
        let haveIDs = Set(have.map(\.id))
        var lastError: String?
        for (id, item) in want where !haveIDs.contains(id) {
            guard let schedule = Self.schedule(for: item) else { continue }
            do {
                _ = try await manager.schedule(id: id, configuration: Self.configuration(for: item, schedule: schedule, snooze: set.snooze))
            } catch {
                lastError = String(describing: error)
            }
        }
        let count = ((try? manager.alarms) ?? []).count
        return AlarmStatus(mode: "alarmkit", auth: "authorized", count: count, error: lastError)
    }

    @available(iOS 26.0, *)
    nonisolated static func schedule(for item: AlarmItem) -> Alarm.Schedule? {
        if let at = item.at { return .fixed(Date(timeIntervalSince1970: at / 1000)) }
        guard let h = item.h, let m = item.m else { return nil }
        let all: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let days = (item.days ?? []).filter { (0..<7).contains($0) }.map { all[$0] }
        return .relative(.init(time: .init(hour: h, minute: m), repeats: days.isEmpty ? .never : .weekly(days)))
    }

    @available(iOS 26.0, *)
    nonisolated static func configuration(for item: AlarmItem, schedule: Alarm.Schedule, snooze: Int) -> AlarmManager.AlarmConfiguration<AxiomAlarmMeta> {
        let yellow = Color(red: 1.0, green: 0.769, blue: 0.0)
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: item.title),
            stopButton: AlarmButton(text: "Stop", textColor: .black, systemImageName: "stop.fill"),
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .countdown)
        let countdown = AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: "Snooze · " + item.title), pauseButton: nil)
        let attributes = AlarmAttributes<AxiomAlarmMeta>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown),
            metadata: AxiomAlarmMeta(title: item.title, sub: item.sub ?? ""),
            tintColor: yellow)
        return AlarmManager.AlarmConfiguration<AxiomAlarmMeta>(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(max(1, snooze) * 60)),
            schedule: schedule,
            attributes: attributes,
            sound: .default)
    }
    #endif

    // MARK: Notifications (before iOS 26)

    private static let prefix = "axiom.alarm."

    private func applyNotifications(_ set: AlarmSet) async -> AlarmStatus {
        let center = UNUserNotificationCenter.current()
        let items = Self.upcoming(set)
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined && !items.isEmpty {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        let ok: Bool = [UNAuthorizationStatus.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard ok else {
            return AlarmStatus(mode: "notify", auth: settings.authorizationStatus == .denied ? "denied" : "notDetermined", count: 0)
        }
        var requests: [UNNotificationRequest] = []
        let cal = Calendar.current
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = "⏰ " + item.title
            content.body = item.sub?.isEmpty == false ? item.sub! : "Alarm"
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let base = Self.id(for: item, snooze: set.snooze).uuidString
            if let at = item.at {
                // a notification only plays its sound once, so repeat it a few times a minute apart
                for k in 0..<3 {
                    let d = Date(timeIntervalSince1970: at / 1000 + Double(k * 60))
                    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
                    requests.append(UNNotificationRequest(identifier: "\(Self.prefix)\(base).\(k)", content: content,
                                                          trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                }
            } else if let h = item.h, let m = item.m {
                let days = (item.days ?? []).isEmpty ? [nil] : (item.days ?? []).map { Optional($0) }
                for d in days {
                    var comps = DateComponents(hour: h, minute: m)
                    if let d = d { comps.weekday = d + 1 }
                    // without repeat days it rings once, the next time the clock shows h:m
                    requests.append(UNNotificationRequest(identifier: "\(Self.prefix)\(base).\(d ?? 9)", content: content,
                                                          trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: d != nil)))
                }
            }
        }
        var lastError: String?
        for r in requests.prefix(60) {   // iOS keeps at most 64 waiting notifications per app
            do { try await center.add(r) } catch { lastError = error.localizedDescription }
        }
        return AlarmStatus(mode: "notify", auth: "authorized", count: min(requests.count, 60), error: lastError)
    }
}
