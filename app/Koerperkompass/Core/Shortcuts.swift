import AppIntents
import SwiftData

/// Siri und Kurzbefehle: „Hey Siri, Wasser in Körperkompass eintragen“ – trägt das Getränk ein, ohne die App zu öffnen.
enum DrinkKind: String, AppEnum {
    case water, coffee, tea, beer, wine

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Getränk"
    static var caseDisplayRepresentations: [DrinkKind: DisplayRepresentation] = [
        .water: "Wasser", .coffee: "Kaffee", .tea: "Tee", .beer: "Bier", .wine: "Wein",
    ]
}

struct LogDrinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Getränk eintragen"
    static var description = IntentDescription("Trägt ein Getränk in Körperkompass ein.")

    @Parameter(title: "Getränk")
    var drink: DrinkKind

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let d = Drink.all.first(where: { $0.id == drink.rawValue }) else {
            return .result(dialog: IntentDialog("Das kenne ich leider nicht."))
        }
        let context = ModelContext(sharedContainer)
        context.insert(d.entry())
        try? context.save()
        let text = "\(d.emoji) \(String(localized: d.name)) (\(d.ml.whole) ml) eingetragen."
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: text)))
    }
}

struct KoerperkompassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogDrinkIntent(),
            phrases: [
                "\(\.$drink) in \(.applicationName) eintragen",
                "Trag \(\.$drink) in \(.applicationName) ein",
                "\(.applicationName) \(\.$drink)",
            ],
            shortTitle: "Getränk eintragen",
            systemImageName: "drop.fill")
    }
}
