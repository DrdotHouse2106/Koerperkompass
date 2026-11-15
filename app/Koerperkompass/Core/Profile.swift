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
    var water: Double? = 2000
    var plan: TrainingPlan?           // aktives Trainingsprogramm
    var habits: [String]? = nil       // eigene tägliche Quests (z. B. „Ein Buch lesen“)
    var penalties: Bool? = nil        // XP-Abzug für verpasste Trainingstage

    static let defaultHabits = [String(localized: "Gesund essen"), String(localized: "Lesen"), String(localized: "Meditieren")]
    var habitList: [String] { habits ?? Self.defaultHabits }

    var isSetUp: Bool { kcal > 0 }

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
        "Tagesziel: \(kcal.whole) kcal, Eiweiß \(protein.whole) g, Kohlenhydrate \(carbs.whole) g, Fett \(fat.whole) g"
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
