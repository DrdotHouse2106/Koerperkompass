import Charts
import SwiftUI

/// Übungen: Sätze mit Wiederholungen und Gewicht pro Übung, Verlauf und Stufe je Übung.
/// Ein Eintrag = ein Satz (Feld „exercise“ = Name der Übung).
struct ExerciseModule: AppModule {
    let id = "exercises"
    let name: LocalizedStringResource = "Übungen"
    let symbol = "chart.line.uptrend.xyaxis"
    let fields = [
        Field(key: "reps", name: "Wiederholungen", unit: "", agg: .avg),
        Field(key: "weight", name: "Zusatzgewicht", unit: "kg", agg: .avg),
    ]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(ExerciseTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(ExerciseDetail(entries: entries)) }
}

/// Stufe einer Übung nach Verbesserung gegenüber dem ersten Eintrag
enum Tier: Int, CaseIterable {
    case bronze, silver, gold, platinum
    var title: LocalizedStringResource {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silber"
        case .gold: "Gold"
        case .platinum: "Platin"
        }
    }
    var color: Color { [Color.brown, .gray, .yellow, .cyan][rawValue] }
    /// nötige Steigerung gegenüber dem Start
    var threshold: Double { [1, 1.1, 1.25, 1.5][rawValue] }

    static func of(_ series: [Double]) -> Tier {
        guard let first = series.first, first > 0, let best = series.max() else { return .bronze }
        return allCases.last { best / first >= $0.threshold } ?? .bronze
    }
}

/// Tagesbestwert einer Übung für Wiederholungen oder Gewicht
private func best(_ entries: [Entry], _ exercise: String, _ key: String) -> [(day: String, value: Double)] {
    let byDay = Dictionary(grouping: entries.filter { $0.text("exercise") == exercise }, by: \.date)
    return byDay.compactMap { day, es -> (day: String, value: Double)? in es.compactMap { $0.num(key) }.max().map { (day, $0) } }.sorted { $0.day < $1.day }
}

private func names(_ entries: [Entry]) -> [String] {
    Array(Set(entries.compactMap { $0.text("exercise") })).sorted()
}

private struct ExerciseTile: View {
    let entries: [Entry]
    var body: some View {
        TileCard(module: ExerciseModule()) {
            Text("\(names(entries).count) Übungen").font(.headline)
            if let last = entries.max(by: { ($0.date, $0.updated) < ($1.date, $1.updated) }) {
                Text("\(last.text("exercise") ?? "") · \((last.num("reps") ?? 0).whole) Wdh.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExerciseDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var exercise = ""
    @State private var reps: Double?
    @State private var weight: Double?

    /// Vorschläge: Übungen aus dem Trainingsprogramm (Text vor „–“) und bisher eingetragene
    private var suggestions: [String] {
        let fromPlan = (state.profile.plan?.days ?? []).flatMap(\.exercises).map {
            $0.components(separatedBy: " – ").first?.trimmingCharacters(in: .whitespaces) ?? $0
        }
        return Array(Set(fromPlan + names(entries))).sorted()
    }

    var body: some View {
        List {
            Section("Satz eintragen") {
                TextField("Übung", text: $exercise)
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestions, id: \.self) { s in
                                Button(s) { exercise = s }.buttonStyle(.bordered).font(.caption)
                            }
                        }
                    }
                }
                TextField("Wiederholungen", value: $reps, format: .number).keyboardType(.numberPad)
                TextField("Zusatzgewicht (kg, optional)", value: $weight, format: .number).keyboardType(.decimalPad)
                Button("Sichern") {
                    var v: [String: Any] = ["exercise": exercise.trimmingCharacters(in: .whitespaces), "reps": reps ?? 0]
                    if let weight { v["weight"] = weight }
                    context.insert(Entry(module: "exercises", values: v))
                    reps = nil
                    state.changed(context)
                }
                .disabled(exercise.trimmingCharacters(in: .whitespaces).isEmpty || reps == nil)
            }
            Section("Meine Übungen") {
                if names(entries).isEmpty { Text("Noch keine Übung eingetragen").foregroundStyle(.secondary) }
                ForEach(names(entries), id: \.self) { n in
                    NavigationLink { ExerciseChart(entries: entries, exercise: n) } label: {
                        HStack {
                            Text(n)
                            Spacer()
                            let tier = Tier.of(best(entries, n, "reps").map { $0.value })
                            Text(tier.title).font(.caption.bold()).foregroundStyle(tier.color)
                        }
                    }
                }
            }
        }
    }
}

/// Verlauf einer Übung mit Stufe
private struct ExerciseChart: View {
    let entries: [Entry]
    let exercise: String
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var key = "reps"

    var body: some View {
        let series = best(entries, exercise, key)
        let tier = Tier.of(series.map { $0.value })
        let list = entries.filter { $0.text("exercise") == exercise }.sorted { ($0.date, $0.updated) > ($1.date, $1.updated) }
        List {
            Section {
                Picker("Wert", selection: $key) {
                    Text("Max. Wiederholungen").tag("reps")
                    Text("Max. Gewicht").tag("weight")
                }
                .pickerStyle(.segmented)
                if series.isEmpty {
                    Text("Keine Werte").foregroundStyle(.secondary)
                } else {
                    Chart(series.indices, id: \.self) { i in
                        LineMark(x: .value("Tag", Day.date(series[i].day)), y: .value("Wert", series[i].value))
                            .foregroundStyle(.orange)
                        PointMark(x: .value("Tag", Day.date(series[i].day)), y: .value("Wert", series[i].value))
                            .foregroundStyle(.orange)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                }
            } footer: { Text("\(list.count) Sätze eingetragen") }
            Section {
                HStack {
                    ForEach(Tier.allCases, id: \.self) { t in
                        VStack(spacing: 4) {
                            Image(systemName: "hexagon.fill").font(.largeTitle)
                                .foregroundStyle(t.rawValue <= tier.rawValue ? t.color : Color.gray.opacity(0.25))
                            Text(t.title).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } header: { Text("Stufe") } footer: {
                Text("Silber ab 10 Prozent, Gold ab 25 Prozent, Platin ab 50 Prozent Steigerung gegenüber deinem ersten Eintrag.")
            }
            Section("Sätze") {
                EntryRows(entries: list) { e in
                    "\((e.num("reps") ?? 0).whole) Wdh." + (e.num("weight").map { " · \($0.short) kg" } ?? "")
                }
            }
        }
        .navigationTitle(exercise)
    }
}
