import SwiftData
import SwiftUI

/// Ein erkanntes Lebensmittel – vor dem Speichern noch änderbar
struct ParsedFood: Identifiable {
    let id = UUID()
    var meal: Meal
    var name: String
    var amount: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

extension Meal {
    /// Mahlzeit nach Uhrzeit
    static var now: Meal {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 11 ? .breakfast : h < 15 ? .lunch : h < 18 ? .snack : .dinner
    }
}

/// Freie Beschreibung → Lebensmittel mit Nährwerten.
/// Mit Claude (Haiku, mit Zustimmung) über den eigenen Server, sonst mit Apple Intelligence auf dem iPhone.
enum MealParser {
    @MainActor static func parse(_ text: String, state: AppState) async throws -> [ParsedFood] {
        if state.aiAvailable && state.aiConsent {
            let r = try await state.api.object("POST", "/api/ai/meal", json: [
                "text": text, "hint": Meal.now.rawValue, "lang": Locale.current.language.languageCode?.identifier ?? "de",
            ])
            let meal = (r["meal"] as? String).flatMap(Meal.init(rawValue:)) ?? Meal.now
            return (r["items"] as? [[String: Any]] ?? []).map {
                ParsedFood(meal: ($0["meal"] as? String).flatMap(Meal.init(rawValue:)) ?? meal, name: $0["name"] as? String ?? "", amount: $0["amount"] as? String ?? "",
                           kcal: ($0["kcal"] as? NSNumber)?.doubleValue ?? 0, protein: ($0["protein"] as? NSNumber)?.doubleValue ?? 0,
                           carbs: ($0["carbs"] as? NSNumber)?.doubleValue ?? 0, fat: ($0["fat"] as? NSNumber)?.doubleValue ?? 0)
            }
        }
        if let r = await OnDevice.parseMeal(text, hint: Meal.now.rawValue) { return r }
        throw API.Failure(message: String(localized: "Dafür braucht es Claude auf deinem Server (mit Zustimmung) oder Apple Intelligence."))
    }
}

/// Abschnitt in der Ernährung: frei beschreiben (Text oder Sprache) und häufige Lebensmittel mit einem Tipp
struct MealInputSection: View {
    let day: String
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var speech = SpeechInput()
    @State private var busy = false
    @State private var error: String?
    @State private var result: MealResult?
    @State private var askConsent = false

    struct MealResult: Identifiable {
        let id = UUID()
        var items: [ParsedFood]
    }

    /// Häufigste Lebensmittel der letzten 60 Tage
    private var favorites: [Entry] {
        let from = Day.last(60)[0]
        let list = entries.filter { $0.module == "nutrition" && !$0.deleted && $0.date >= from && !($0.text("name") ?? "").isEmpty }
        let groups = Dictionary(grouping: list) { ($0.text("name") ?? "").lowercased() }
        return groups.values.sorted { $0.count > $1.count }.prefix(10).compactMap { $0.max { $0.updated < $1.updated } }
    }

    var body: some View {
        Section {
            HStack(alignment: .top) {
                TextField("z. B. „Zum Frühstück 2 Berliner und ein Kaffee mit Milch“", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                Button {
                    Task {
                        if speech.listening { text = await speech.stop() } else { await speech.start() }
                    }
                } label: {
                    Image(systemName: speech.listening ? "stop.circle.fill" : "mic.circle.fill").font(.title2)
                        .foregroundStyle(speech.listening ? .red : .orange)
                }
                .buttonStyle(.plain)
            }
            .onChange(of: speech.heard) { if speech.listening { text = speech.heard } }
            Button(busy ? LocalizedStringKey("Wird erkannt …") : "Eintragen", systemImage: "sparkles") {
                if state.aiAvailable && !state.aiConsent && !OnDevice.available { askConsent = true } else { parse() }
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            // Fenster und Rückfrage an genau dieser Zeile: an der Section gälten sie für jede Zeile einzeln
            .sheet(item: $result) { r in MealConfirmView(result: r, day: day) { text = "" } }
            .alert("Beschreibung an Claude senden?", isPresented: $askConsent) {
                Button("Zustimmen") { state.aiConsent = true; parse() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Deine Beschreibung wird über deinen Server an die Claude API (Anthropic, Modell Haiku) gesendet, um die Nährwerte zu schätzen.")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if !favorites.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(favorites) { e in
                            Button {
                                var v = e.values
                                v["meal"] = Meal.now.rawValue
                                v.removeValue(forKey: "photo")
                                context.insert(Entry(module: "nutrition", date: day, values: v))
                                state.changed(context)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } label: {
                                Text("+ \(e.text("name") ?? "")").font(.caption).lineLimit(1)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: { Text("Was hast du gegessen?") } footer: {
            Text("Einfach beschreiben oder sprechen – die Nährwerte werden geschätzt und du prüfst sie vor dem Speichern. Häufige Lebensmittel trägst du mit einem Tipp in die aktuelle Mahlzeit ein.")
        }
    }

    private func parse() {
        busy = true
        error = nil
        let input = text
        Task {
            defer { busy = false }
            do {
                let items = try await MealParser.parse(input, state: state)
                guard !items.isEmpty else { throw API.Failure(message: String(localized: "Nichts erkannt – beschreib es etwas genauer.")) }
                AppLog.add("Essen erkannt: \(items.count) Lebensmittel")
                result = MealResult(items: items)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Erkannte Lebensmittel prüfen, anpassen und speichern
private struct MealConfirmView: View {
    @State var result: MealInputSection.MealResult
    let day: String
    let done: () -> Void
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach($result.items) { $item in
                    Section {
                        Picker("Mahlzeit", selection: $item.meal) {
                            ForEach(Meal.allCases) { Text($0.title).tag($0) }
                        }
                        TextField("Bezeichnung", text: $item.name)
                        TextField("Menge", text: $item.amount)
                        row("kcal", $item.kcal)
                        row("Eiweiß (g)", $item.protein)
                        row("Kohlenhydrate (g)", $item.carbs)
                        row("Fett (g)", $item.fat)
                    }
                }
                .onDelete { result.items.remove(atOffsets: $0) }
                Section {
                    Text("Summe: \(result.items.reduce(0) { $0 + $1.kcal }.whole) kcal").bold()
                } footer: {
                    Text("Geschätzte Werte – bitte prüfen. Zum Entfernen nach links wischen.")
                }
            }
            .navigationTitle("Prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(result.items.isEmpty)
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        for f in result.items {
            let name = f.amount.isEmpty ? f.name : "\(f.name) (\(f.amount))"
            context.insert(Entry(module: "nutrition", date: day, values: [
                "meal": f.meal.rawValue, "name": name, "kcal": f.kcal, "protein": f.protein, "carbs": f.carbs, "fat": f.fat,
            ]))
            if state.healthEnabled && day == Day.today {
                Health.saveMeal(name: name, kcal: f.kcal, protein: f.protein, carbs: f.carbs, fat: f.fat)
            }
        }
        state.changed(context)
        done()
        dismiss()
    }
}
