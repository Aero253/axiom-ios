import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// The report countdown shown in the Dynamic Island and on the Lock Screen before a duty.
/// It turns red for the last half hour on its own: the content is marked out of date then, and iOS redraws it.
struct ReportAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var report: Date
        var off: Date?
        var route: [String]       // DMK, CNX, DMK
        var flights: [String]     // SL520, SL521
        var what: String          // "Report", "Airport standby"
    }
    /// Which duty this is for (its report time), so a duty never gets two.
    var key: String
}

extension ReportAttributes.ContentState {
    /// Red, like the LED ticker, from this long before report.
    static let redBefore: TimeInterval = 30 * 60
    var redAt: Date { report.addingTimeInterval(-Self.redBefore) }
    func isRed(at now: Date = Date()) -> Bool { now >= redAt }

    init(duty d: Duty) {
        let legs = d.legs ?? []
        let route = legs.isEmpty ? d.route : [legs[0].from] + legs.map(\.to)
        let flights = legs.compactMap(\.flt).filter { !$0.isEmpty }
        self.init(report: d.repDate, off: d.off > d.rep ? d.offDate : nil, route: route,
                  flights: flights.isEmpty ? d.flts : flights,
                  what: d.type == "FDP" ? "Report" : (d.type == "ASBY" ? "Airport standby" : d.what))
    }
}
#endif
