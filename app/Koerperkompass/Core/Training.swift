import Foundation

/// Trainingsprogramm: an festen Wochentagen wird reihum der nächste Trainingstag fällig,
/// an den anderen Tagen ist Ruhetag. Gespeichert im Profil (und damit auf dem Server).
struct TrainingPlan: Codable, Equatable {
    var name: String
    var level: String = ""          // z. B. „Einsteiger“
    var weekdays: [Int] = [2, 4, 6] // Calendar-Wochentage: 1 = So, 2 = Mo … 7 = Sa
    var days: [PlanDay]
    var start = Day.today
    var weeks = 4

    var end: String { Day.string(Calendar.current.date(byAdding: .day, value: weeks * 7 - 1, to: Day.date(start))!) }
    var finished: Bool { Day.today > end }

    /// Ist an diesem Tag Training geplant?
    func isTrainingDay(_ day: String) -> Bool {
        day >= start && day <= end && weekdays.contains(Calendar.current.component(.weekday, from: Day.date(day)))
    }

    /// Fälliger Trainingstag: reihum nach Anzahl der bereits absolvierten Einheiten
    func next(done: Int) -> PlanDay? { days.isEmpty ? nil : days[done % days.count] }
}

struct PlanDay: Codable, Equatable {
    var title: String
    var exercises: [String]
}

/// XP je Trainingseinheit eines Programms bzw. Abzug je verpasster Einheit (falls eingeschaltet)
let planXP = 75
let missedXP = 30

/// Mitgelieferte Programme – eigene Ideen, frei anpassbar
let planTemplates: [TrainingPlan] = [
    TrainingPlan(name: String(localized: "Erste Schritte"), level: String(localized: "Einsteiger"), days: [
        PlanDay(title: String(localized: "Ganzkörper ohne Geräte"), exercises: [
            String(localized: "Kniebeugen – 3 × 12–15"), String(localized: "Liegestütze (auch auf den Knien) – 3 × 8–12"),
            String(localized: "Unterarmstütz – 3 × 30 s"), String(localized: "Ausfallschritte – 3 × 10 je Seite"),
        ]),
        PlanDay(title: String(localized: "Zügiger Spaziergang"), exercises: [String(localized: "30 Minuten zügig gehen")]),
    ]),
    TrainingPlan(name: String(localized: "Kraft-Basis"), level: String(localized: "Fortgeschritten"), days: [
        PlanDay(title: String(localized: "Tag A – Beine & Drücken"), exercises: [
            String(localized: "Kniebeugen – 4 × 6–8"), String(localized: "Bankdrücken – 4 × 6–8"), String(localized: "Ausfallschritte – 3 × 10 je Seite"),
        ]),
        PlanDay(title: String(localized: "Tag B – Rücken & Ziehen"), exercises: [
            String(localized: "Kreuzheben – 3 × 5"), String(localized: "Klimmzüge oder Latziehen – 3 × 6–10"), String(localized: "Rudern – 3 × 8–10"),
        ]),
    ]),
    TrainingPlan(name: String(localized: "Ausdauer aufbauen"), level: String(localized: "Einsteiger"), days: [
        PlanDay(title: String(localized: "Locker laufen"), exercises: [String(localized: "25–30 Minuten in ruhigem Tempo")]),
        PlanDay(title: String(localized: "Intervalle"), exercises: [String(localized: "10 min einlaufen, 6 × 1 min zügig / 2 min locker")]),
        PlanDay(title: String(localized: "Langer Lauf"), exercises: [String(localized: "40–45 Minuten ruhig")]),
    ]),
    TrainingPlan(name: String(localized: "Rumpf & Beweglichkeit"), level: String(localized: "Alle"), weekdays: [3, 6], days: [
        PlanDay(title: String(localized: "Rumpf"), exercises: [
            String(localized: "Unterarmstütz – 3 × 45 s"), String(localized: "Seitstütz – 3 × 30 s je Seite"), String(localized: "Sit-ups – 3 × 15"),
        ]),
        PlanDay(title: String(localized: "Mobilität"), exercises: [String(localized: "20 Minuten Dehnen und Mobilisieren")]),
    ]),
]
