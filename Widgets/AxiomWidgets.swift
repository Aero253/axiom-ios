import SwiftUI
import WidgetKit

/// WidgetKit takes up to ten widgets per group, so they're split into themed groups.
@main
struct AxiomWidgets: WidgetBundle {
    var body: some Widget {
        NextDutyWidget()
        FlightProgressWidget()
        GlobeWidget()
        AgendaWidget()
        MonthWidget()
        ClockWidget()
        WorldClockWidget()
        WaterWidget()
        YearWidget()
        MoreAxiomWidgets().body
    }
}

struct MoreAxiomWidgets: WidgetBundle {
    var body: some Widget {
        WeatherWidget()
        SunWidget()
        DutyHoursWidget()
        RestWidget()
        WakeWidget()
        LayoverWidget()
        TodoWidget()
        ShoppingWidget()
        CountdownWidget()
        AlarmWidgets().body
    }
}

struct AlarmWidgets: WidgetBundle {
    var body: some Widget {
        AlarmWidget()
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            AlarmLiveActivity()
        }
        #endif
    }
}
