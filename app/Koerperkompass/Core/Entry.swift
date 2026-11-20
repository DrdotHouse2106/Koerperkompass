import Foundation
import SwiftData

/// Ein Datensatz eines Moduls – lokaler Zwischenspeicher der Server-Tabelle `entries`.
/// Die Modulfelder liegen als JSON in `data`, damit neue Module kein neues Datenmodell brauchen.
@Model final class Entry {
    @Attribute(.unique) var id: String
    var module: String
    var date: String        // JJJJ-MM-TT
    var data: Data          // JSON-Objekt mit den Feldern
    // Gespeichert als „stamp“/„removed“: „updated“ und „deleted“ sind in Core Data (unter SwiftData) reserviert
    // und lieferten beim Lesen immer 0/false – Löschungen und Zeitstempel gingen so verloren.
    var stamp: Int64 = 0    // Änderungszeit in ms – neuere gewinnt beim Abgleich
    var removed: Bool = false
    var dirty: Bool         // noch nicht zum Server übertragen

    var updated: Int64 { get { stamp } set { stamp = newValue } }
    var deleted: Bool { get { removed } set { removed = newValue } }

    init(id: String = UUID().uuidString, module: String, date: String = Day.today, values: [String: Any], dirty: Bool = true) {
        self.id = id
        self.module = module
        self.date = date
        self.data = (try? JSONSerialization.data(withJSONObject: values)) ?? Data("{}".utf8)
        self.stamp = Int64(Date().timeIntervalSince1970 * 1000)
        self.removed = false
        self.dirty = dirty
    }

    var values: [String: Any] {
        get { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
        set { data = (try? JSONSerialization.data(withJSONObject: newValue)) ?? data }
    }

    func num(_ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
    func text(_ key: String) -> String? { values[key] as? String }

    /// Darstellung für Server und Export
    var json: [String: Any] {
        ["id": id, "module": module, "date": date, "data": values, "updated": updated, "deleted": deleted]
    }

    func touch() {
        updated = Int64(Date().timeIntervalSince1970 * 1000)
        dirty = true
    }
}

extension ModelContext {
    func entry(_ id: String) -> Entry? {
        try? fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first
    }

    /// Legt einen Eintrag an oder aktualisiert ihn, wenn sich die Werte geändert haben.
    func upsert(id: String, module: String, date: String, values: [String: Any], dirty: Bool) {
        if let e = entry(id) {
            if NSDictionary(dictionary: e.values).isEqual(to: values) && !e.deleted { return }
            e.values = values
            e.date = date
            e.deleted = false
            e.touch()
            e.dirty = dirty
        } else {
            insert(Entry(id: id, module: module, date: date, values: values, dirty: dirty))
        }
    }

    func allEntries() -> [Entry] {
        (try? fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.date)]))) ?? []
    }
}

/// Tage als Text „JJJJ-MM-TT“ – so vergleicht und sortiert man ohne Zeitzonen-Ärger.
enum Day {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ d: Date) -> String { formatter.string(from: d) }
    static func date(_ s: String) -> Date { formatter.date(from: s) ?? Date() }
    static var today: String { string(Date()) }
    /// Aktuelle Uhrzeit „HH:mm“ (für Getränke und Mahlzeiten)
    static var now: String { Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }

    /// Montag der aktuellen Woche
    static var weekStart: String {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return string(cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
    }

    /// Die letzten n Tage inklusive heute, ältester zuerst
    static func last(_ n: Int) -> [String] {
        (0..<n).reversed().map { string(Calendar.current.date(byAdding: .day, value: -$0, to: Date())!) }
    }
}

extension Double {
    /// Zahl ohne unnötige Nachkommastellen, lokalisiert
    var short: String { formatted(.number.precision(.fractionLength(0...1))) }
    var whole: String { formatted(.number.precision(.fractionLength(0))) }
}
