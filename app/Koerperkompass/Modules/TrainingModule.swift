import SwiftUI

/// Training: einfaches Beispielmodul – ein Eintrag pro Einheit mit Name und Dauer.
struct TrainingModule: AppModule {
    let id = "training"
    let name: LocalizedStringResource = "Training"
    let symbol = "dumbbell"
    let fields = [Field(key: "minutes", name: "Dauer", unit: "min", agg: .sum)]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(TrainingTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(TrainingDetail(entries: entries)) }
}

private struct TrainingTile: View {
    let entries: [Entry]
    var body: some View {
        let week = Set(Day.last(7))
        TileCard(module: TrainingModule()) {
            Text("\(entries.filter { week.contains($0.date) }.count) Einheiten").font(.headline)
            Text("in den letzten 7 Tagen").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct TrainingDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var minutes: Double?

    var body: some View {
        List {
            Section("Neue Einheit") {
                TextField("Was hast du trainiert?", text: $name)
                TextField("Dauer (min)", value: $minutes, format: .number).keyboardType(.numberPad)
                Button("Sichern") {
                    context.insert(Entry(module: "training", values: ["name": name, "minutes": minutes ?? 0]))
                    Health.saveWorkout(name: name, minutes: minutes ?? 0)
                    name = ""
                    minutes = nil
                    state.changed(context)
                }
                .disabled(name.isEmpty)
            }
            Section("Verlauf") {
                EntryRows(entries: entries.sorted { $0.date > $1.date }) { "\($0.text("name") ?? "") · \(($0.num("minutes") ?? 0).whole) min" }
            }
        }
    }
}
