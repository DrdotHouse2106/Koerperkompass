import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence direkt auf dem iPhone (Foundation Models, ab iOS 26 auf unterstützten Geräten):
/// kostenlos, offline, die Daten verlassen das Gerät nicht. Für kurze Aufgaben – Sprüche, Training, Sprach-Coach.
/// Ohne Apple Intelligence liefern die Funktionen nil; die App nutzt dann Claude oder einfache Regeln.
enum OnDevice {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Persönliche Motivationssprüche
    static func motivation(count: Int, context: String) async -> [String]? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), available {
            let session = LanguageModelSession(instructions:
                "Du schreibst kurze, motivierende Push-Mitteilungen für eine Gesundheits-App: per Du, warm, abwechslungsreich, konkret auf die Daten bezogen, höchstens 140 Zeichen, gern mit einem Emoji. Keine Diagnosen, nicht belehrend.")
            let prompt = "Schreibe \(count) verschiedene Mitteilungen. Daten:\n" + String(context.prefix(2000))
            if let r = try? await session.respond(to: prompt, generating: GenMessages.self) {
                return Array(r.content.messages.filter { !$0.isEmpty }.prefix(count))
            }
        }
        #endif
        return nil
    }

    /// Freie Essensbeschreibung in Lebensmittel mit Nährwerten zerlegen
    static func parseMeal(_ text: String, hint: String) async -> [ParsedFood]? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), available {
            let s = LanguageModelSession(instructions: "Du zerlegst Essensbeschreibungen in einzelne Lebensmittel mit realistischen Nährwerten für die genannte oder eine übliche deutsche Portionsgröße. Getränke mit Kalorien gehören dazu. Erkenne die Mahlzeit jedes Lebensmittels aus dem Text, sonst nimm den Hinweis. Eine Beschreibung kann mehrere Mahlzeiten enthalten.")
            if let r = try? await s.respond(to: "Hinweis Mahlzeit: \(hint)\nBeschreibung: \(text)", generating: GenMeal.self) {
                return r.content.items.map {
                    ParsedFood(meal: Meal(rawValue: $0.meal) ?? Meal(rawValue: hint) ?? .snack,
                               name: $0.name, amount: $0.amount, kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat)
                }
            }
        }
        #endif
        return nil
    }

    /// Nächste Trainingseinheit an Rückmeldungen und Verlauf anpassen
    static func nextSession(_ session: PlanDay, history: String, profile: String) async -> Suggestion? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), available {
            let s = LanguageModelSession(instructions:
                "Du bist ein vorsichtiger Trainer. Passe die geplante Einheit an: nach „zu leicht“ moderat steigern, nach „zu schwer“ reduzieren, nach „genau richtig“ minimal steigern. Nutze eingetragene Gewichte und Wiederholungen. Behalte den Charakter der Einheit bei. Antworte auf Deutsch.")
            let prompt = "Profil: \(profile)\nGeplante Einheit: \(session.title): \(session.exercises.joined(separator: "; "))\n\n"
                + String(history.suffix(2500))
            if let r = try? await s.respond(to: prompt, generating: GenSession.self), !r.content.exercises.isEmpty {
                return Suggestion(day: Day.today, session: PlanDay(title: r.content.title, exercises: r.content.exercises), note: r.content.note)
            }
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GenFood {
    @Guide(description: "Mahlzeit: breakfast, lunch, dinner oder snack")
    var meal: String
    @Guide(description: "Kurze Bezeichnung des Lebensmittels")
    var name: String
    @Guide(description: "Menge, z. B. 2 Stück (140 g)")
    var amount: String
    @Guide(description: "Kilokalorien für diese Menge")
    var kcal: Double
    @Guide(description: "Eiweiß in Gramm")
    var protein: Double
    @Guide(description: "Kohlenhydrate in Gramm")
    var carbs: Double
    @Guide(description: "Fett in Gramm")
    var fat: Double
}

@available(iOS 26.0, *)
@Generable
struct GenMeal {
    var items: [GenFood]
}

@available(iOS 26.0, *)
@Generable
struct GenMessages {
    @Guide(description: "Kurze motivierende Mitteilungen, je höchstens 140 Zeichen")
    var messages: [String]
}

@available(iOS 26.0, *)
@Generable
struct GenSession {
    @Guide(description: "Name der Einheit")
    var title: String
    @Guide(description: "Übungen im Format „Übung – Sätze × Wiederholungen (ggf. Gewicht)“")
    var exercises: [String]
    @Guide(description: "Ein kurzer Satz, warum so angepasst")
    var note: String
}

/// Ein Wortwechsel im Sprach-Coach: Antwort plus erkannter Satz und Pause
@available(iOS 26.0, *)
@Generable
struct GenTurn {
    @Guide(description: "Kurze gesprochene Antwort des Trainers, 1–2 Sätze, motivierend, per Du")
    var reply: String
    @Guide(description: "Name der Übung, falls ein Satz gemeldet wurde, sonst leer")
    var exercise: String
    @Guide(description: "Wiederholungen des gemeldeten Satzes, sonst 0")
    var reps: Int
    @Guide(description: "Gewicht in kg des gemeldeten Satzes, sonst 0")
    var weight: Double
    @Guide(description: "Empfohlene Pause in Sekunden vor dem nächsten Satz, sonst 0")
    var restSeconds: Int
    @Guide(description: "Rückmeldung zur Anstrengung: easy, ok, hard oder leer")
    var feedback: String
}
#endif
