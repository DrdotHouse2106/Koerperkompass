import SwiftUI

/// Wasser: einfaches Beispielmodul – ein Eintrag pro Getränk. Vorlage für eigene Module.
struct WaterModule: AppModule {
    let id = "water"
    let name: LocalizedStringResource = "Wasser"
    let symbol = "drop"
    let fields = [Field(key: "ml", name: "Menge", unit: "ml", agg: .sum)]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(WaterTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(WaterDetail(entries: entries)) }
}

private func today(_ entries: [Entry]) -> Double {
    entries.filter { $0.date == Day.today }.compactMap { $0.num("ml") }.reduce(0, +)
}

private struct WaterTile: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    var body: some View {
        let goal = state.profile.water ?? 2000
        TileCard(module: WaterModule()) {
            Text("\(today(entries).whole) / \(goal.whole) ml").font(.headline)
            Ring(progress: today(entries) / goal, color: .cyan, size: 34)
        }
    }
}

private struct WaterDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    var body: some View {
        List {
            Section {
                Text("\(today(entries).whole) ml heute").font(.title2.bold())
                HStack {
                    ForEach([250.0, 500.0], id: \.self) { ml in
                        Button("+\(ml.whole) ml") {
                            context.insert(Entry(module: "water", values: ["ml": ml]))
                            state.changed(context)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            Section("Heute") {
                EntryRows(entries: entries.filter { $0.date == Day.today }) { "\(($0.num("ml") ?? 0).whole) ml" }
            }
        }
    }
}
