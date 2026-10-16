import AppIntents
import Foundation
#if canImport(AlarmKit)
import AlarmKit
#endif

/// "Start my report countdown": puts the countdown in the Dynamic Island without opening Axiom
/// (Siri, the Shortcuts app, or a Shortcuts automation such as "when I leave home").
struct StartReportCountdownIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start report countdown"
    static var description = IntentDescription("Shows the countdown to your next report in the Dynamic Island and on the Lock Screen, within 8 hours of report.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let p = Shared.load()
        await ReportLive.sync(p)
        guard let d = ReportLive.next(p) else { return .result(dialog: "No report in the next 8 hours.") }
        return .result(dialog: IntentDialog(stringLiteral: "Counting down to report at \(Speak.time(d.repDate))."))
    }
}

#if canImport(AlarmKit)
/// The Stop button on an Axiom alarm: stops it, then starts the report countdown if a duty reports within 8 hours,
/// so waking up to your alarm puts the countdown on screen even if you never open Axiom.
@available(iOS 26.0, *)
struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop alarm"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Alarm") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }   // the alarm first, always
        await ReportLive.sync(Shared.load())
        return .result()
    }
}
#endif
