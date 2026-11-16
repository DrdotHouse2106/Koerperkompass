import Foundation

/// Profil und Tagesziele. Wird lokal und auf dem Server (users.profile) gespeichert.
/// Neue Felder bitte optional anlegen, damit ältere gespeicherte Profile lesbar bleiben.
struct Profile: Codable, Equatable {
    enum Goal: String, Codable, CaseIterable { case lose, maintain, gain }
    enum Sex: String, Codable, CaseIterable { case female, male }

    var goal = Goal.maintain
    var weight = 75.0
    var targetWeight = 72.0
    var height = 175.0
    var age = 35
    var sex = Sex.female
    var activity = 1                    // Index in activityFactors
    var modules = allModules.map(\.id)  // eingeschaltete Module
    var kcal = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var water: Double? = 2000         // nur genutzt, wenn waterCustom = true
    var waterCustom: Bool? = nil      // Trinkziel von Hand festgelegt
    var suggestion: Suggestion? = nil // von Claude angepasste nächste Einheit
    var name: String?                 // Anzeigename (Spielerkarte)
    var plan: TrainingPlan?           // aktives Trainingsprogramm
    var habits: [String]? = nil       // eigene tägliche Quests (z. B. „Ein Buch lesen“)
    var penalties: Bool? = nil        // XP-Abzug für verpasste Trainingstage
    var showFriends: Bool? = nil      // meine Freunde meinen Freunden zeigen
    var visible: Bool? = nil          // für Freunde meiner Freunde sichtbar sein
    var equipment: [String]? = nil    // vorhandene Trainingsgeräte (nil = unbekannt, leer = keine)
    var facts: [String]? = nil        // was der Coach im Gespräch über die Person erfahren hat

    struct Equipment: Identifiable { let id: String; let name: LocalizedStringResource }
    static let equipmentOptions: [Equipment] = [
        .init(id: "dumbbells", name: "Kurzhanteln"), .init(id: "barbell", name: "Langhantel"), .init(id: "kettlebell", name: "Kettlebell"),
        .init(id: "bands", name: "Widerstandsbänder"), .init(id: "pullupbar", name: "Klimmzugstange"), .init(id: "bench", name: "Hantelbank"),
        .init(id: "bike", name: "Fahrrad / Ergometer"), .init(id: "treadmill", name: "Laufband"), .init(id: "rope", name: "Springseil"),
        .init(id: "gym", name: "Fitnessstudio"),
    ]

    static let defaultHabits = [String(localized: "Gesund essen"), String(localized: "Lesen"), String(localized: "Meditieren")]
    var habitList: [String] { habits ?? Self.defaultHabits }

    var isSetUp: Bool { kcal > 0 }

    /// Trinkziel: rund 35 ml je kg Körpergewicht, mehr bei viel Bewegung (auf 250 ml gerundet, 1,5–4 l)
    var autoWater: Double {
        let ml = weight * 35 + (activity >= 3 ? 500 : activity == 2 ? 250 : 0)
        return min(max((ml / 250).rounded() * 250, 1500), 4000)
    }
    var waterGoal: Double { waterCustom == true ? (water ?? autoWater) : autoWater }

    static let activityFactors = [1.2, 1.375, 1.55, 1.725, 1.9]
    static let activityNames: [LocalizedStringResource] = ["Kaum Bewegung", "Leicht aktiv", "Mäßig aktiv", "Sehr aktiv", "Extrem aktiv"]

    /// Grundumsatz nach Mifflin-St-Jeor
    var bmr: Double {
        10 * weight + 6.25 * height - 5 * Double(age) + (sex == .male ? 5 : -161)
    }

    /// Tagesziele berechnen. Liegt die durchschnittliche aktive Energie aus Apple Health vor,
    /// ersetzt sie den geschätzten Aktivitätsfaktor. Untergrenzen verhindern zu niedrige Ziele.
    mutating func computeGoals(activeEnergy: Double?) {
        let total = activeEnergy.map { bmr * 1.2 + $0 } ?? bmr * Self.activityFactors[min(max(activity, 0), 4)]
        let delta: Double = goal == .lose ? -500 : goal == .gain ? 300 : 0
        kcal = max(total + delta, sex == .male ? 1500 : 1200, bmr).rounded()
        protein = (weight * (goal == .maintain ? 1.6 : 1.8)).rounded()
        fat = max(kcal * 0.3 / 9, weight * 0.8).rounded()
        carbs = max((kcal - protein * 4 - fat * 9) / 4, 100).rounded()
    }

    /// Kurzer Text für die KI-Auswertung (ohne Namen o. Ä.)
    var aiText: String {
        "Ziel: \(goal.rawValue), Geschlecht: \(sex.rawValue), Alter: \(age), Größe: \(height.whole) cm, " +
        "Startgewicht: \(weight.short) kg, Wunschgewicht: \(targetWeight.short) kg, " +
        "Tagesziel: \(kcal.whole) kcal, Eiweiß \(protein.whole) g, Kohlenhydrate \(carbs.whole) g, Fett \(fat.whole) g, " +
        "Trainingsgeräte: \(equipmentText)" +
        ((facts ?? []).isEmpty ? "" : "\nBekannt über die Person: " + (facts ?? []).joined(separator: "; "))
    }

    /// Geräte als Text für die KI (deutsche Namen)
    var equipmentText: String {
        guard let equipment else { return "unbekannt" }
        if equipment.isEmpty { return "keine (nur Körpergewicht)" }
        return Self.equipmentOptions.filter { equipment.contains($0.id) }.map { String(localized: $0.name) }.joined(separator: ", ")
    }

    /// Neue Tatsachen aus dem Coach-Gespräch übernehmen (ohne Doppelte, höchstens 40)
    mutating func learn(_ new: [String]) {
        var list = facts ?? []
        for f in new where !list.contains(where: { $0.caseInsensitiveCompare(f) == .orderedSame }) { list.append(f) }
        facts = Array(list.suffix(40))
    }
}

extension Profile.Goal {
    var title: LocalizedStringResource {
        switch self {
        case .lose: "Abnehmen"
        case .maintain: "Halten"
        case .gain: "Zunehmen"
        }
    }
}

extension Profile.Sex {
    var title: LocalizedStringResource { self == .female ? "Weiblich" : "Männlich" }
}

/// Vorschlag für die nächste Trainingseinheit (z. B. von Claude angepasst)
struct Suggestion: Codable, Equatable {
    var day: String       // gilt für diesen Tag
    var session: PlanDay
    var note: String
}
