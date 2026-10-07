import AppIntents
import WidgetKit

/// The + on the Water widget: adds one 250 ml glass without opening the app.
struct AddGlassIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a glass of water"
    static var description = IntentDescription("Adds one 250 ml glass to today's water in Axiom.")

    func perform() async throws -> some IntentResult {
        Shared.addGlass()
        return .result()
    }
}
