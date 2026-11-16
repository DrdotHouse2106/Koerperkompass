import SwiftUI

/// Getränke: Wasser, Kaffee, Tee, Bier, Wein, Softdrinks … mit einem Tipp eintragen.
/// Flüssigkeit zählt fürs Trinkziel (ohne Alkohol), Kalorien zählen zusätzlich in die Ernährung.
/// Die id bleibt „water“, damit ältere Einträge (nur „ml“) weiter zählen.
struct WaterModule: AppModule {
    let id = "water"
    let name: LocalizedStringResource = "Getränke"
    let symbol = "drop.fill"
    let fields = [
        Field(key: "hydration", name: "Flüssigkeit", unit: "ml", agg: .sum),
        Field(key: "kcal", name: "Kalorien aus Getränken", unit: "kcal", agg: .sum),
        Field(key: "caffeine", name: "Koffein", unit: "mg", agg: .sum),
        Field(key: "alcohol", name: "Alkohol", unit: "g", agg: .sum),
    ]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(WaterTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(WaterDetail(entries: entries)) }
}

/// Getränkesorten mit üblicher Menge und Richtwerten
struct Drink: Identifiable {
    let id: String
    let name: LocalizedStringResource
    let emoji: String
    let ml: Double
    var kcal = 0.0
    var carbs = 0.0
    var caffeine = 0.0
    var alcohol = 0.0
    var hydrates = true

    static let all: [Drink] = [
        Drink(id: "water", name: "Wasser", emoji: "💧", ml: 250),
        Drink(id: "water500", name: "Flasche Wasser", emoji: "🚰", ml: 500),
        Drink(id: "coffee", name: "Kaffee", emoji: "☕️", ml: 200, kcal: 5, caffeine: 80),
        Drink(id: "cappuccino", name: "Cappuccino", emoji: "🥛", ml: 200, kcal: 90, carbs: 7, caffeine: 80),
        Drink(id: "espresso", name: "Espresso", emoji: "☕️", ml: 30, kcal: 1, caffeine: 60),
        Drink(id: "tea", name: "Tee", emoji: "🍵", ml: 250, caffeine: 30),
        Drink(id: "juice", name: "Saft", emoji: "🧃", ml: 250, kcal: 110, carbs: 26),
        Drink(id: "soda", name: "Softdrink", emoji: "🥤", ml: 330, kcal: 140, carbs: 35),
        Drink(id: "zero", name: "Light/Zero", emoji: "🥤", ml: 330, caffeine: 30),
        Drink(id: "energy", name: "Energy-Drink", emoji: "⚡️", ml: 250, kcal: 115, carbs: 27, caffeine: 80),
        Drink(id: "beer", name: "Bier", emoji: "🍺", ml: 500, kcal: 210, carbs: 16, alcohol: 20, hydrates: false),
        Drink(id: "beer0", name: "Alkoholfreies Bier", emoji: "🍺", ml: 500, kcal: 110, carbs: 24),
        Drink(id: "wine", name: "Wein", emoji: "🍷", ml: 200, kcal: 170, carbs: 5, alcohol: 19, hydrates: false),
        Drink(id: "spirit", name: "Schnaps", emoji: "🥃", ml: 40, kcal: 90, alcohol: 13, hydrates: false),
    ]

    func entry(date: String = Day.today) -> Entry {
        Entry(module: "water", date: date, values: [
            "drink": id, "name": String(localized: name), "ml": ml, "hydration": hydrates ? ml : 0,
            "kcal": kcal, "carbs": carbs, "caffeine": caffeine, "alcohol": alcohol,
        ])
    }
}

/// Flüssigkeit eines Tages (ältere Einträge haben nur „ml“)
func hydration(_ entries: [Entry], _ day: String = Day.today) -> Double {
    entries.filter { $0.module == "water" && $0.date == day && !$0.deleted }.compactMap { $0.num("hydration") ?? $0.num("ml") }.reduce(0, +)
}

private func todaySum(_ entries: [Entry], _ key: String) -> Double {
    entries.filter { $0.date == Day.today }.compactMap { $0.num(key) }.reduce(0, +)
}

private struct WaterTile: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    var body: some View {
        let goal = state.profile.waterGoal, ml = hydration(entries)
        TileCard(module: WaterModule()) {
            HStack {
                Ring(progress: ml / goal, color: .cyan, size: 44)
                VStack(alignment: .leading) {
                    Text("\(ml.whole) ml").font(.title3.bold())
                    Text("von \(goal.whole) ml").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Schnell-Buttons für die häufigsten Getränke (Übersicht und Getränke-Ansicht)
struct QuickDrinks: View {
    var ids = ["water", "coffee", "tea", "beer"]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var last: String?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Drink.all.filter { ids.contains($0.id) }) { d in
                Button {
                    context.insert(d.entry())
                    state.changed(context)
                    last = d.id
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    VStack(spacing: 2) {
                        Text(d.emoji).font(.title2)
                        Text("+\(d.ml.whole)").font(.caption2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.cyan.opacity(last == d.id ? 0.35 : 0.15), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WaterDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @AppStorage("reminderOn") private var reminderOn = false
    @AppStorage("reminderEvery") private var every = 2
    @AppStorage("reminderFrom") private var from = 9
    @AppStorage("reminderTo") private var to = 21
    @State private var denied = false

    var body: some View {
        let goal = state.profile.waterGoal, ml = hydration(entries)
        List {
            Section {
                HStack(spacing: 18) {
                    ZStack {
                        Ring(progress: ml / goal, color: .cyan, size: 96)
                        Text("\(Int(min(ml / goal, 9.99) * 100)) %").font(.headline)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(ml.whole) ml").font(.title.bold())
                        Text("von \(goal.whole) ml Trinkziel").foregroundStyle(.secondary)
                        HStack {
                            if todaySum(entries, "kcal") > 0 { Text("🔥 \(todaySum(entries, "kcal").whole) kcal") }
                            if todaySum(entries, "caffeine") > 0 { Text("☕️ \(todaySum(entries, "caffeine").whole) mg") }
                            if todaySum(entries, "alcohol") > 0 { Text("🍺 \(todaySum(entries, "alcohol").whole) g") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section("Eintragen") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(Drink.all) { d in
                        Button {
                            context.insert(d.entry())
                            state.changed(context)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            VStack(spacing: 4) {
                                Text(d.emoji).font(.largeTitle)
                                Text(d.name).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                                Text("\(d.ml.whole) ml").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background((d.hydrates ? Color.cyan : Color.orange).opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Heute") {
                EntryRows(entries: entries.filter { $0.date == Day.today }.sorted { $0.updated > $1.updated }) {
                    "\($0.text("name") ?? String(localized: "Wasser")) · \(($0.num("ml") ?? 0).whole) ml"
                }
            }
            Section {
                Toggle("Trinkerinnerung", isOn: $reminderOn)
                if reminderOn {
                    Picker("Alle", selection: $every) {
                        Text("1 Stunde").tag(1)
                        Text("2 Stunden").tag(2)
                        Text("3 Stunden").tag(3)
                    }
                    Stepper("Ab \(from):00 Uhr", value: $from, in: 5...(to - 1))
                    Stepper("Bis \(to):00 Uhr", value: $to, in: (from + 1)...23)
                }
                Stepper("Trinkziel: \(state.profile.waterGoal.whole) ml", value: Binding(
                    get: { state.profile.waterGoal }, set: { state.profile.water = $0; state.profile.waterCustom = true }), in: 1000...5000, step: 250)
                if state.profile.waterCustom == true {
                    Button("Automatisch aus Körpergewicht (\(state.profile.autoWater.whole) ml)") { state.profile.waterCustom = nil }
                }
                if denied { Text("Mitteilungen sind für Körperkompass ausgeschaltet – bitte in den iOS-Einstellungen erlauben.").foregroundStyle(.red) }
            } header: { Text("Erinnerung & Ziel") } footer: {
                Text("Das Trinkziel berechnet sich aus deinem Körpergewicht (rund 35 ml je kg, mehr bei viel Bewegung). Die Erinnerung kannst du direkt in der Mitteilung abhaken (gedrückt halten): Wasser, Kaffee oder Tee. Alkohol zählt nicht zum Trinkziel.")
            }
        }
        .onChange(of: [reminderOn ? 1 : 0, every, from, to]) { update() }
    }

    private func update() {
        Task {
            if reminderOn {
                denied = !(await Reminders.schedule(every: every, from: from, to: to))
                if denied { reminderOn = false }
            } else {
                Reminders.cancel()
            }
        }
    }
}
