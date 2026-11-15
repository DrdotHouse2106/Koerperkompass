import Foundation
import SwiftData

/// Demo-Modus: realistische Beispieldaten der letzten 30 Tage, ganz ohne Server.
/// Gedacht zum Ausprobieren und für die App-Store-Prüfung.
enum Demo {
    @MainActor static func fill(_ context: ModelContext, state: AppState) {
        var p = Profile()
        p.goal = .lose
        p.weight = 82
        p.targetWeight = 76
        p.height = 178
        p.age = 38
        p.sex = .male
        p.activity = 2
        p.computeGoals(activeEnergy: nil)
        state.profile = p

        var rng = SystemRandomNumberGenerator()
        func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng).rounded() }
        let meals: [(Meal, String, ClosedRange<Double>)] = [
            (.breakfast, String(localized: "Haferflocken mit Beeren"), 350...480),
            (.lunch, String(localized: "Hähnchen mit Reis und Gemüse"), 550...750),
            (.dinner, String(localized: "Vollkornbrot mit Käse"), 450...700),
            (.snack, String(localized: "Apfel und Nüsse"), 150...300),
        ]
        for (i, day) in Day.last(30).enumerated() {
            for (meal, name, range) in meals where meal != .snack || i % 2 == 0 {
                let kcal = r(range)
                context.insert(Entry(module: "nutrition", date: day, values: [
                    "meal": meal.rawValue, "name": name, "kcal": kcal,
                    "protein": (kcal * 0.25 / 4).rounded(), "carbs": (kcal * 0.45 / 4).rounded(), "fat": (kcal * 0.3 / 9).rounded(),
                ], dirty: false))
            }
            let sleep = (Double.random(in: 5.5...8.5, using: &rng) * 10).rounded() / 10
            context.insert(Entry(id: "activity-" + day, module: "activity", date: day, values: [
                "steps": r(4000...12000) + (sleep - 7) * 1500, "activeEnergy": r(250...650), "sleepHours": sleep,
                "restingHR": r(56...64), "workoutMinutes": i % 3 == 0 ? r(30...60) : 0,
            ], dirty: false))
            if i % 3 == 0 {
                context.insert(Entry(module: "body", date: day, values: ["weight": ((82 - Double(i) * 0.08 + Double.random(in: -0.3...0.3, using: &rng)) * 10).rounded() / 10, "waist": (95 - Double(i) * 0.1).rounded()], dirty: false))
            }
            context.insert(Entry(module: "water", date: day, values: ["ml": r(4...8) * 250], dirty: false))
            if i % 3 == 0 {
                context.insert(Entry(module: "training", date: day, values: ["name": String(localized: "Laufen"), "minutes": r(30...50)], dirty: false))
            }
        }
        try? context.save()
    }
}
