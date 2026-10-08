import Foundation
#if canImport(AlarmKit)
import AlarmKit

/// What an alarm carries to its Lock Screen snooze countdown (shared by the app, which schedules it,
/// and the widget extension, which draws the countdown).
@available(iOS 26.0, *)
struct AxiomAlarmMeta: AlarmMetadata {
    var title: String
    var sub: String
}
#endif
