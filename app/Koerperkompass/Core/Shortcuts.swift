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

/// Kurzbefehl fürs Teilen-Menü: Link (Reel, Video, Rezeptseite) als Rezept speichern, ohne die App zu öffnen.
/// Einrichten: Kurzbefehle-App → neuer Kurzbefehl mit dieser Aktion → „Im Teilen-Menü anzeigen“ (Eingabe: URLs).
struct SaveRecipeLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Rezept aus Link speichern"
    static var description = IntentDescription("Speichert ein Rezept aus einem Reel, Video oder einer Rezeptseite in Körperkompass.")

    @Parameter(title: "Link")
    var url: URL

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let d = UserDefaults.standard
        guard let server = d.string(forKey: "server"), !server.isEmpty, let token = Keychain.get("token") else {
            return .result(dialog: IntentDialog("Körperkompass ist noch nicht mit einem Server verbunden."))
        }
        let r = try await API(server: server, token: token).object("POST", "/api/recipes/link", json: [
            "url": url.absoluteString, "ai": d.bool(forKey: "aiConsent"), "lang": Locale.current.language.languageCode?.identifier ?? "de",
        ])
        if let recipe = r["recipe"] as? [String: Any] {
            // Rezeptseite: sofort fertig – wird beim nächsten Öffnen der App abgeglichen
            let context = ModelContext(sharedContainer)
            context.insert(Entry(module: "recipes", values: recipe))
            try? context.save()
            return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: String(localized: "„\(recipe["title"] as? String ?? "")“ gespeichert."))))
        }
        if let id = r["id"] as? String {
            // Reel/Video: Reelkoch arbeitet, die App holt das Rezept beim Öffnen der Rezepte ab
            var jobs = RecipeJobs.all
            jobs[id] = url.absoluteString
            RecipeJobs.all = jobs
            return .result(dialog: IntentDialog("Rezept wird erstellt – in 1–2 Minuten unter Rezepte."))
        }
        return .result(dialog: IntentDialog("Daraus konnte kein Rezept erstellt werden."))
    }
}

/// Kurzbefehl fürs Teilen-Menü: Ton eines Reels/Videos als privaten Motivations-Clip speichern (nur für dich)
struct SaveClipIntent: AppIntent {
    static var title: LocalizedStringResource = "Clip speichern"
    static var description = IntentDescription("Speichert den Ton eines Reels oder Videos privat unter Motivation → Meine Clips.")

    @Parameter(title: "Link")
    var url: URL

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let server = UserDefaults.standard.string(forKey: "server"), !server.isEmpty, let token = Keychain.get("token") else {
            return .result(dialog: IntentDialog("Körperkompass ist noch nicht mit einem Server verbunden."))
        }
        let r = try await API(server: server, token: token).object("POST", "/api/clips", json: ["url": url.absoluteString])
        let title = r["title"] as? String ?? ""
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: String(localized: "Clip gespeichert: \(title)"))))
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
        AppShortcut(
            intent: SaveRecipeLinkIntent(),
            phrases: ["Rezept in \(.applicationName) speichern"],
            shortTitle: "Rezept aus Link",
            systemImageName: "book.closed.fill")
    }
}
