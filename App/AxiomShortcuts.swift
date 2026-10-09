import AppIntents

/// The phrases Siri knows for Axiom. They also appear in the Shortcuts app, ready to use, with nothing to set up.
struct AxiomShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextReportIntent(), phrases: [
            "When's my next report in \(.applicationName)",
            "When do I report in \(.applicationName)",
            "Next report in \(.applicationName)",
            "\(.applicationName) next duty",
        ], shortTitle: "Next report", systemImageName: "airplane.departure")
        AppShortcut(intent: TomorrowIntent(), phrases: [
            "Where am I flying tomorrow in \(.applicationName)",
            "What's my duty tomorrow in \(.applicationName)",
            "Tomorrow in \(.applicationName)",
            "\(.applicationName) tomorrow",
        ], shortTitle: "Tomorrow", systemImageName: "calendar")
        AppShortcut(intent: NextAlarmIntent(), phrases: [
            "What's my next alarm in \(.applicationName)",
            "When is my alarm in \(.applicationName)",
            "\(.applicationName) next alarm",
        ], shortTitle: "Next alarm", systemImageName: "alarm")
        AppShortcut(intent: AddGlassIntent(), phrases: [
            "Add a glass of water in \(.applicationName)",
            "Log water in \(.applicationName)",
            "\(.applicationName) add water",
        ], shortTitle: "Add water", systemImageName: "drop.fill")
    }
}
