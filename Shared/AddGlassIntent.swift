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

/// The tick circles on the To-do and Shopping widgets.
struct ToggleItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Tick off a list item"
    static var description = IntentDescription("Marks an item on your Axiom to-do or shopping list as done, or not done.")

    @Parameter(title: "List") var list: String
    @Parameter(title: "Item") var item: String

    init() {}

    init(list: String, item: String) {
        self.list = list
        self.item = item
    }

    func perform() async throws -> some IntentResult {
        Shared.toggle(list: list, id: item)
        return .result()
    }
}
