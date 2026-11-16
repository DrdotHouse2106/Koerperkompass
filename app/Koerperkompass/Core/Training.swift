import SwiftUI

/// Trainingsprogramm: an festen Wochentagen wird reihum der nächste Trainingstag fällig,
/// an den anderen Tagen ist Ruhetag. Gespeichert im Profil (und damit auf dem Server).
struct TrainingPlan: Codable, Equatable {
    var name: String
    var level: String = ""          // z. B. „Einsteiger“
    var weekdays: [Int] = [2, 4, 6] // Calendar-Wochentage: 1 = So, 2 = Mo … 7 = Sa
    var days: [PlanDay]
    var start = Day.today
    var weeks = 4
    var symbol: String?             // Symbol der Programmkarte (optional, ältere Programme haben keins)
    var info: String?               // kurze Beschreibung

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
private func ex(_ list: String...) -> [String] { list.map { NSLocalizedString($0, comment: "") } }

let planTemplates: [TrainingPlan] = [
    TrainingPlan(name: String(localized: "Erste Schritte"), level: String(localized: "Einsteiger"), days: [
        PlanDay(title: String(localized: "Ganzkörper ohne Geräte"), exercises: ex("Kniebeugen – 3 × 12–15", "Liegestütze (auch auf den Knien) – 3 × 8–12", "Unterarmstütz – 3 × 30 s", "Ausfallschritte – 3 × 10 je Seite")),
        PlanDay(title: String(localized: "Zügiger Spaziergang"), exercises: ex("30 Minuten zügig gehen")),
    ], symbol: "figure.walk", info: String(localized: "Sanfter Start ohne Geräte – 3× pro Woche")),
    TrainingPlan(name: String(localized: "100er-Challenge"), level: String(localized: "Einsteiger"), weekdays: [2, 3, 4, 5, 6, 7], days: [
        PlanDay(title: String(localized: "Tagesration"), exercises: ex("Liegestütze – 100 (in Sätzen)", "Sit-ups – 100 (in Sätzen)", "Kniebeugen – 100 (in Sätzen)", "Laufen – 3 km")),
    ], symbol: "flame.fill", info: String(localized: "Jeden Tag 100 Liegestütze, Sit-ups und Kniebeugen plus 3 km – steigere dich langsam")),
    TrainingPlan(name: String(localized: "Kurzhanteln zu Hause"), level: String(localized: "Einsteiger"), days: [
        PlanDay(title: String(localized: "Oberkörper"), exercises: ex("Kurzhantel-Bankdrücken (Boden) – 3 × 10", "Einarmiges Rudern – 3 × 10 je Seite", "Schulterdrücken – 3 × 10", "Bizeps-Curls – 3 × 12")),
        PlanDay(title: String(localized: "Unterkörper & Rumpf"), exercises: ex("Goblet Squats – 3 × 12", "Rumänisches Kreuzheben – 3 × 10", "Ausfallschritte – 3 × 10 je Seite", "Unterarmstütz – 3 × 40 s")),
    ], symbol: "dumbbell.fill", info: String(localized: "Zwei Kurzhanteln reichen – 3× pro Woche")),
    TrainingPlan(name: String(localized: "Kraft-Basis"), level: String(localized: "Fortgeschritten"), days: [
        PlanDay(title: String(localized: "Tag A – Beine & Drücken"), exercises: ex("Kniebeugen – 4 × 6–8", "Bankdrücken – 4 × 6–8", "Ausfallschritte – 3 × 10 je Seite")),
        PlanDay(title: String(localized: "Tag B – Rücken & Ziehen"), exercises: ex("Kreuzheben – 3 × 5", "Klimmzüge oder Latziehen – 3 × 6–10", "Rudern – 3 × 8–10")),
    ], symbol: "figure.strengthtraining.traditional", info: String(localized: "Langhantel-Grundübungen im Wechsel")),
    TrainingPlan(name: String(localized: "Push / Pull / Beine"), level: String(localized: "Fortgeschritten"), weekdays: [2, 4, 6], days: [
        PlanDay(title: String(localized: "Push – Drücken"), exercises: ex("Bankdrücken – 4 × 6–8", "Schrägbankdrücken Kurzhantel – 3 × 10", "Schulterdrücken – 3 × 8–10", "Seitheben – 3 × 12–15", "Trizepsdrücken – 3 × 12")),
        PlanDay(title: String(localized: "Pull – Ziehen"), exercises: ex("Klimmzüge oder Latziehen – 4 × 6–10", "Langhantelrudern – 3 × 8", "Face Pulls – 3 × 15", "Bizeps-Curls – 3 × 10–12")),
        PlanDay(title: String(localized: "Beine"), exercises: ex("Kniebeugen – 4 × 6–8", "Rumänisches Kreuzheben – 3 × 8", "Beinpresse – 3 × 10–12", "Wadenheben – 4 × 15")),
    ], symbol: "bolt.fill", info: String(localized: "Klassischer Split fürs Studio")),
    TrainingPlan(name: String(localized: "Oberkörper / Unterkörper"), level: String(localized: "Fortgeschritten"), weekdays: [2, 3, 5, 6], days: [
        PlanDay(title: String(localized: "Oberkörper"), exercises: ex("Bankdrücken – 4 × 6–8", "Rudern – 4 × 8", "Schulterdrücken – 3 × 8–10", "Latziehen – 3 × 10")),
        PlanDay(title: String(localized: "Unterkörper"), exercises: ex("Kniebeugen – 4 × 6–8", "Kreuzheben – 3 × 5", "Ausfallschritte – 3 × 10 je Seite", "Unterarmstütz – 3 × 45 s")),
    ], symbol: "arrow.up.arrow.down", info: String(localized: "4× pro Woche, ausgewogen")),
    TrainingPlan(name: String(localized: "HIIT 20 Minuten"), level: String(localized: "Alle"), days: [
        PlanDay(title: String(localized: "Intervall-Zirkel"), exercises: ex("4 Runden: 40 s Belastung / 20 s Pause", "Hampelmänner", "Burpees", "Mountain Climbers", "Kniebeugen-Sprünge", "Unterarmstütz")),
    ], symbol: "timer", info: String(localized: "Kurz und intensiv, ohne Geräte")),
    TrainingPlan(name: String(localized: "Ausdauer aufbauen"), level: String(localized: "Einsteiger"), days: [
        PlanDay(title: String(localized: "Locker laufen"), exercises: ex("25–30 Minuten in ruhigem Tempo")),
        PlanDay(title: String(localized: "Intervalle"), exercises: ex("10 min einlaufen, 6 × 1 min zügig / 2 min locker")),
        PlanDay(title: String(localized: "Langer Lauf"), exercises: ex("40–45 Minuten ruhig")),
    ], symbol: "figure.run", info: String(localized: "Laufen in drei Varianten")),
    TrainingPlan(name: String(localized: "Rumpf & Beweglichkeit"), level: String(localized: "Alle"), weekdays: [3, 6], days: [
        PlanDay(title: String(localized: "Rumpf"), exercises: ex("Unterarmstütz – 3 × 45 s", "Seitstütz – 3 × 30 s je Seite", "Sit-ups – 3 × 15")),
        PlanDay(title: String(localized: "Mobilität"), exercises: ex("20 Minuten Dehnen und Mobilisieren")),
    ], symbol: "figure.flexibility", info: String(localized: "Ergänzung für Rücken und Haltung – 2× pro Woche")),
]

/// Farbe nach Niveau
func levelColor(_ level: String) -> Color {
    level == String(localized: "Fortgeschritten") ? .orange : level == String(localized: "Einsteiger") ? .green : Theme.petrol
}

/// Programme passend zu Ziel und Aktivität (Indizes in planTemplates)
func recommendedPlans(_ p: Profile) -> [TrainingPlan] {
    var idx: [Int]
    switch p.goal {
    case .lose: idx = p.activity >= 2 ? [6, 7, 2] : [0, 7, 2]
    case .gain: idx = p.activity >= 2 ? [3, 4, 5] : [2, 3]
    case .maintain: idx = p.activity >= 3 ? [5, 4, 8] : [2, 0, 8]
    }
    if p.activity == 0 && !idx.contains(0) { idx.insert(0, at: 0) }
    return idx.filter { planTemplates.indices.contains($0) }.map { planTemplates[$0] }
}
