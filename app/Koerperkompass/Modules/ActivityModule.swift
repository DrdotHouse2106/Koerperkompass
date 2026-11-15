import Charts
import SwiftUI

/// Aktivität und Schlaf aus Apple Health – ein Eintrag pro Tag (id „activity-JJJJ-MM-TT“), nur lesend.
struct ActivityModule: AppModule {
    let id = "activity"
    let name: LocalizedStringResource = "Aktivität & Schlaf"
    let symbol = "figure.walk"
    let fields = [
        Field(key: "steps", name: "Schritte", unit: "", agg: .avg),
        Field(key: "activeEnergy", name: "Aktive Energie", unit: "kcal", agg: .avg),
        Field(key: "sleepHours", name: "Schlaf", unit: "h", agg: .avg),
        Field(key: "restingHR", name: "Ruhepuls", unit: "bpm", agg: .avg),
        Field(key: "workoutMinutes", name: "Training", unit: "min", agg: .avg),
    ]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(ActivityTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(ActivityDetail(entries: entries)) }
}

private struct ActivityTile: View {
    let entries: [Entry]
    var body: some View {
        let today = entries.first { $0.date == Day.today }
        TileCard(module: ActivityModule()) {
            if let today, let steps = today.num("steps") {
                Text("\(steps.whole) Schritte").font(.headline)
                if let s = today.num("sleepHours") { Text("\(s.short) h Schlaf").font(.caption).foregroundStyle(.secondary) }
                if let a = today.num("activeEnergy") { Text("\(a.whole) kcal aktiv").font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("Keine Daten aus Apple Health").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ActivityDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            if !state.healthEnabled {
                Section {
                    Text("Verbinde Apple Health, um Schritte, Schlaf, Ruhepuls und Trainings zu sehen.")
                    Button("Apple Health verbinden") { Task { await state.connectHealth(); await state.importHealth(context) } }
                }
            }
            Section("Schritte – letzte 7 Tage") {
                Chart(Day.last(7), id: \.self) { d in
                    BarMark(x: .value("Tag", Day.date(d), unit: .day), y: .value("Schritte", entries.first { $0.date == d }?.num("steps") ?? 0))
                }
                .frame(height: 160)
            }
            Section("Schlaf – letzte 7 Tage") {
                Chart(Day.last(7), id: \.self) { d in
                    BarMark(x: .value("Tag", Day.date(d), unit: .day), y: .value("h", entries.first { $0.date == d }?.num("sleepHours") ?? 0))
                        .foregroundStyle(.indigo)
                }
                .frame(height: 160)
            }
            Section("Tage") {
                ForEach(entries.sorted { $0.date > $1.date }.prefix(30)) { e in
                    VStack(alignment: .leading) {
                        Text(Day.date(e.date), format: .dateTime.weekday().day().month()).font(.subheadline.bold())
                        Text(ActivityModule().fields.compactMap { f in e.num(f.key).map { "\(String(localized: f.name)) \($0.short) \(f.unit)" } }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .refreshable { await state.importHealth(context) }
    }
}
