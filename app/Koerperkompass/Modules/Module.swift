import SwiftUI

/// Gemeinsames Modul-Schema (gleich wie server/modules.go):
/// id, Name, SF-Symbol, Datenfelder, Kachel, Eingabe-/Detailansicht, Zusammenfassung für die Analyse.
/// Neues Modul: Datei in Modules/ anlegen und unten in `allModules` eintragen.
protocol AppModule {
    var id: String { get }
    var name: LocalizedStringResource { get }
    var symbol: String { get }
    var fields: [Field] { get }
    /// Kachel auf der Übersicht
    @MainActor func tile(_ entries: [Entry]) -> AnyView
    /// Eingabe- und Detailansicht
    @MainActor func detail(_ entries: [Entry]) -> AnyView
}

/// Liste aller Module – Reihenfolge = Reihenfolge auf der Übersicht.
let allModules: [any AppModule] = [QuestModule(), NutritionModule(), BodyModule(), ActivityModule(), WaterModule(), TrainingModule(), ExerciseModule(), RecipeModule()]

func module(_ id: String) -> (any AppModule)? { allModules.first { $0.id == id } }

/// Zahlenfeld eines Moduls. `agg`: sum = pro Tag addieren, avg = Durchschnitt, last = Verlauf erster → letzter Wert.
struct Field {
    enum Agg { case sum, avg, last }
    let key: String
    let name: LocalizedStringResource
    let unit: String
    let agg: Agg
}

extension AppModule {
    /// Tageswerte eines Feldes: Tag → Wert (je nach Aggregation)
    func daily(_ entries: [Entry], _ field: Field) -> [String: Double] {
        var sum: [String: Double] = [:], count: [String: Double] = [:]
        for e in entries.sorted(by: { ($0.date, $0.updated) < ($1.date, $1.updated) }) {
            guard let v = e.num(field.key) else { continue }
            switch field.agg {
            case .sum: sum[e.date, default: 0] += v; count[e.date] = 1
            case .avg: sum[e.date, default: 0] += v; count[e.date, default: 0] += 1
            case .last: sum[e.date] = v; count[e.date] = 1
            }
        }
        return sum.reduce(into: [String: Double]()) { $0[$1.key] = $1.value / (count[$1.key] ?? 1) }
    }

    /// Zusammenfassung für die Analyse: pro Feld Durchschnitt, Trend und Anzahl Tage
    func summary(_ entries: [Entry], days: [String]) -> [Stat] {
        let set = Set(days)
        let inRange = entries.filter { set.contains($0.date) && !$0.deleted }
        return fields.compactMap { f in
            let d = daily(inRange, f)
            guard !d.isEmpty else { return nil }
            let series = days.compactMap { d[$0] }
            let half = series.count / 2
            let avg = series.reduce(0, +) / Double(series.count)
            var trend: Double? = nil
            if f.agg == .last {
                trend = series.count > 1 ? series.last! - series.first! : nil
            } else if half > 0 {
                trend = series.suffix(half).reduce(0, +) / Double(half) - series.prefix(half).reduce(0, +) / Double(half)
            }
            return Stat(field: f, value: f.agg == .last ? series.last! : avg, trend: trend, days: series.count)
        }
    }
}

struct Stat: Identifiable {
    let field: Field
    let value: Double
    let trend: Double?
    let days: Int
    var id: String { field.key }

    /// Textform für die KI-Auswertung
    var text: String {
        let t = trend.map { " (Trend \($0 >= 0 ? "+" : "")\($0.short))" } ?? ""
        return "- \(String(localized: field.name)): \(field.agg == .last ? "aktuell" : "Ø") \(value.short) \(field.unit)\(t), \(days) Tage"
    }
}

/// Kachel-Rahmen für die Übersicht
struct TileCard<Content: View>: View {
    let module: any AppModule
    @ViewBuilder let content: Content
    var body: some View {
        let tint = Theme.color(module.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(symbol: module.symbol, module: module.id, size: 34)
                Text(module.name).font(.subheadline.bold()).foregroundStyle(.secondary)
            }
            content
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(
            LinearGradient(colors: [tint.opacity(0.22), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(tint.opacity(0.4), lineWidth: 1))
    }
}

/// Fortschrittsring (z. B. Eiweiß/Kohlenhydrate/Fett)
struct Ring: View {
    let progress: Double
    let color: Color
    var label: LocalizedStringResource? = nil
    var size: CGFloat = 44
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: size / 6)
                Circle().trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: size / 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
            if let label { Text(label).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

/// Liste von Einträgen mit Löschen per Wischen
struct EntryRows: View {
    let entries: [Entry]
    let row: (Entry) -> String
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    var body: some View {
        // Gelöschte Einträge selbst ausblenden – die Liste aktualisiert sich so sofort nach dem Wischen
        let visible = entries.filter { !$0.deleted }
        ForEach(visible) { e in
            HStack {
                Text(row(e))
                Spacer()
                Text(Day.date(e.date), format: .dateTime.day().month()).foregroundStyle(.secondary)
            }
        }
        .onDelete { idx in idx.map { visible[$0] }.forEach { state.delete($0, context) } }
    }
}
