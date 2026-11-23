import Charts
import SwiftUI

/// Gewicht und Körpermaße: ein Eintrag pro Messung; Gewicht wird auch in Apple Health geschrieben.
struct BodyModule: AppModule {
    let id = "body"
    let name: LocalizedStringResource = "Gewicht & Maße"
    let symbol = "scalemass"
    let fields = [
        Field(key: "weight", name: "Gewicht", unit: "kg", agg: .last),
        Field(key: "bodyFat", name: "Körperfett", unit: "%", agg: .last),
        Field(key: "leanMass", name: "Fettfreie Masse", unit: "kg", agg: .last),
        Field(key: "waist", name: "Taille", unit: "cm", agg: .last),
        Field(key: "hip", name: "Hüfte", unit: "cm", agg: .last),
        Field(key: "chest", name: "Brust", unit: "cm", agg: .last),
    ]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(BodyTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(BodyDetail(entries: entries)) }
}

private func weights(_ entries: [Entry]) -> [(date: String, kg: Double)] {
    entries.compactMap { e in e.num("weight").map { (e.date, $0) } }.sorted { $0.date < $1.date }
}

private struct BodyTile: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    var body: some View {
        TileCard(module: BodyModule()) {
            if let last = weights(entries).last {
                Text("\(last.kg.short) kg").font(.title2.bold())
                Text("Ziel: \(state.profile.targetWeight.short) kg").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Noch keine Messung").foregroundStyle(.secondary)
            }
        }
    }
}

private struct BodyDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var values: [String: Double] = [:]

    var body: some View {
        List {
            let w = Array(weights(entries).suffix(90))
            if w.count > 1 {
                Section("Gewichtsverlauf") {
                    Chart {
                        ForEach(w.indices, id: \.self) { i in
                            LineMark(x: .value("Tag", Day.date(w[i].date)), y: .value("kg", w[i].kg))
                        }
                        RuleMark(y: .value("Ziel", state.profile.targetWeight))
                            .lineStyle(StrokeStyle(dash: [4]))
                            .foregroundStyle(.secondary)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                }
            }
            Section("Neue Messung") {
                ForEach(BodyModule().fields, id: \.key) { f in
                    HStack {
                        Text(f.name)
                        TextField(f.unit, value: Binding(get: { values[f.key] }, set: { values[f.key] = $0 }), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Button("Sichern", action: save).disabled(values.isEmpty)
            }
            Section("Verlauf") {
                EntryRows(entries: entries.sorted { $0.date > $1.date }) { e in
                    BodyModule().fields.compactMap { f in e.num(f.key).map { "\($0.short) \(f.unit)" } }.joined(separator: " · ")
                }
            }
        }
    }

    private func save() {
        context.insert(Entry(module: "body", values: values))
        if let kg = values["weight"] {
            if state.healthEnabled { Health.saveWeight(kg) }
            state.profile.weight = kg  // aktuelles Gewicht für Trinkziel und Neuberechnung der Ziele
        }
        values = [:]
        state.changed(context)
    }
}
