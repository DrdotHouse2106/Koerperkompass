import EventKit

/// Kalender für den Coach (freiwillig, nur lesen): Termine von heute und morgen kommen in den Kontext, damit der Coach
/// Essen, Training und Erholung um feste Termine herum plant. Standardmäßig nur belegte Zeiten, Titel nur auf Wunsch.
/// An Claude geht das wie alle Coach-Daten nur mit Zustimmung (aiConsent).
enum CalendarAccess {
    static let store = EKEventStore()
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "calendarCoach") }
    static var titles: Bool { UserDefaults.standard.bool(forKey: "calendarTitles") }

    static func request() async -> Bool { (try? await store.requestFullAccessToEvents()) ?? false }

    /// „Termine: Heute 09:00–17:00 belegt; Morgen …“ – nil, wenn aus oder keine Freigabe
    static func summary() -> String? {
        guard enabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let cal = Calendar.current, start = cal.startOfDay(for: Date())
        var days: [String] = []
        for (i, label) in [String(localized: "Heute"), String(localized: "Morgen")].enumerated() {
            let from = cal.date(byAdding: .day, value: i, to: start)!, to = cal.date(byAdding: .day, value: 1, to: from)!
            let events = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
                .filter { $0.availability != .free && (!$0.isAllDay || titles) }
                .sorted { $0.startDate < $1.startDate }
            let list = events.map { e in
                let time = e.isAllDay ? String(localized: "ganztägig")
                    : "\(e.startDate.formatted(date: .omitted, time: .shortened))–\(e.endDate.formatted(date: .omitted, time: .shortened))"
                return time + " " + (titles ? (e.title ?? "") : String(localized: "belegt"))
            }
            days.append("\(label): " + (list.isEmpty ? String(localized: "keine Termine") : list.joined(separator: ", ")))
        }
        return "- Kalender (" + days.joined(separator: "; ") + ")"
    }
}
