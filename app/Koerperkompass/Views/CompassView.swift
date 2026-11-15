import SwiftData
import SwiftUI

/// Analyse „Kompass“: Durchschnitte, Trends, Zielerreichung und Zusammenhänge über alle aktiven Module.
/// Mit Claude-API-Key auf dem Server zusätzlich eine verständliche Auswertung mit Vorschlägen.
struct CompassView: View {
    @Environment(AppState.self) private var state
    @Query(sort: \Entry.date) private var all: [Entry]
    @State private var period = 30
    @State private var aiText: String?
    @State private var busy = false
    @State private var error: String?
    @State private var askConsent = false

    private var days: [String] { Day.last(period) }
    private func entries(_ module: String) -> [Entry] { all.filter { $0.module == module && !$0.deleted } }

    var body: some View {
        NavigationStack {
            List {
                Picker("Zeitraum", selection: $period) {
                    Text("7 Tage").tag(7)
                    Text("30 Tage").tag(30)
                    Text("90 Tage").tag(90)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                ForEach(state.activeModules.filter { !$0.fields.isEmpty }, id: \.id) { m in
                    let stats = m.summary(entries(m.id), days: days)
                    Section {
                        if stats.isEmpty { Text("Keine Daten im Zeitraum").foregroundStyle(.secondary) }
                        ForEach(stats) { s in
                            HStack {
                                Text(s.field.name)
                                Spacer()
                                Text("\(s.value.short) \(s.field.unit)").monospacedDigit()
                                if let t = s.trend, abs(t) > 0.01 {
                                    Image(systemName: t > 0 ? "arrow.up.right" : "arrow.down.right").foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Label { Text(m.name) } icon: { Image(systemName: m.symbol) } }
                }

                let goals = goalLines
                if !goals.isEmpty {
                    Section("Zielerreichung") { ForEach(goals, id: \.self) { Text($0) } }
                }
                let links = correlations
                if !links.isEmpty {
                    Section("Zusammenhänge") { ForEach(links, id: \.self) { Text($0) } }
                }

                Section {
                    if state.aiAvailable {
                        Button(busy ? LocalizedStringKey("Auswertung läuft …") : "Ausführliche Auswertung mit Claude", systemImage: "sparkles") {
                            if state.aiConsent { analyse() } else { askConsent = true }
                        }
                        .disabled(busy)
                        if let error { Text(error).foregroundStyle(.red) }
                        if let aiText {
                            Text((try? AttributedString(markdown: aiText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(aiText))
                        }
                    } else {
                        Text("Für eine ausführliche Auswertung mit Mustern und Vorschlägen kann auf deinem Server ein Claude-API-Key hinterlegt werden.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Alle Werte sind Schätzungen. Der Körperkompass ersetzt keine ärztliche Beratung.")
                }
            }
            .navigationTitle("Kompass")
            .alert("Daten an Claude senden?", isPresented: $askConsent) {
                Button("Zustimmen") { state.aiConsent = true; analyse() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Für die Auswertung werden Profil und zusammengefasste Werte der aktiven Module über deinen Server an die Claude API (Anthropic) gesendet. Health-Daten nur, wenn du ihrem Hochladen zugestimmt hast. Du kannst die Zustimmung in den Einstellungen widerrufen.")
            }
        }
    }

    // MARK: Lokale Auswertung

    /// Zielerreichung bei Kalorien, Eiweiß und Gewicht
    private var goalLines: [String] {
        var out: [String] = []
        let p = state.profile
        if p.modules.contains("nutrition") {
            let kcal = NutritionModule().daily(entries("nutrition"), NutritionModule().fields[0]).filter { days.contains($0.key) }
            let protein = NutritionModule().daily(entries("nutrition"), NutritionModule().fields[1]).filter { days.contains($0.key) }
            if !kcal.isEmpty {
                let hit = kcal.values.filter { abs($0 - p.kcal) <= p.kcal * 0.1 }.count
                out.append(String(localized: "Kalorienziel (±10 Prozent) an \(hit) von \(kcal.count) erfassten Tagen erreicht"))
                let ok = protein.values.filter { $0 >= p.protein * 0.9 }.count
                out.append(String(localized: "Eiweißziel an \(ok) von \(kcal.count) Tagen erreicht"))
            }
        }
        if p.modules.contains("body"), let last = entries("body").filter({ $0.num("weight") != nil }).max(by: { $0.date < $1.date })?.num("weight") {
            let rest = last - p.targetWeight
            out.append(abs(rest) < 0.5
                ? String(localized: "Wunschgewicht erreicht 🎉")
                : String(localized: "Noch \(abs(rest).short) kg bis zum Wunschgewicht"))
        }
        return out
    }

    /// Zusammenhänge zwischen Tageswerten verschiedener Module (Korrelation nach Pearson)
    private var correlations: [String] {
        let pairs: [(String, String, String, String, LocalizedStringResource)] = [
            ("activity", "sleepHours", "nutrition", "kcal", "Schlaf und Kalorien"),
            ("activity", "steps", "nutrition", "kcal", "Schritte und Kalorien"),
            ("activity", "sleepHours", "activity", "steps", "Schlaf und Schritte"),
        ]
        return pairs.compactMap { (m1, f1, m2, f2, title) -> String? in
            guard state.profile.modules.contains(m1), state.profile.modules.contains(m2),
                  let a = series(m1, f1), let b = series(m2, f2) else { return nil }
            let common = days.filter { a[$0] != nil && b[$0] != nil }
            guard common.count >= 5 else { return nil }
            let r = pearson(common.map { a[$0]! }, common.map { b[$0]! })
            let strength: String
            if abs(r) < 0.3 {
                strength = String(localized: "kaum ein Zusammenhang")
            } else if abs(r) < 0.6 {
                strength = r > 0 ? String(localized: "ein mittlerer positiver Zusammenhang") : String(localized: "ein mittlerer negativer Zusammenhang")
            } else {
                strength = r > 0 ? String(localized: "ein deutlicher positiver Zusammenhang") : String(localized: "ein deutlicher negativer Zusammenhang")
            }
            return String(localized: "\(String(localized: title)): \(strength) (r = \(r.formatted(.number.precision(.fractionLength(2)))), \(common.count) Tage)")
        }
    }

    private func series(_ moduleID: String, _ key: String) -> [String: Double]? {
        guard let m = module(moduleID), let f = m.fields.first(where: { $0.key == key }) else { return nil }
        return m.daily(entries(moduleID), f)
    }

    private func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count), mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        let cov = zip(x, y).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let sx = sqrt(x.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)), sy = sqrt(y.map { ($0 - my) * ($0 - my) }.reduce(0, +))
        return sx * sy == 0 ? 0 : cov / (sx * sy)
    }

    // MARK: Auswertung mit Claude

    private func analyse() {
        // Health-Daten nur mitschicken, wenn ihrem Hochladen zugestimmt wurde
        let allowed = { (e: Entry) in state.healthUpload || !(e.id.hasPrefix("activity-") || e.id.hasPrefix("health-")) }
        var local = state.activeModules.map { m -> String in
            let stats = m.summary(entries(m.id).filter(allowed), days: days)
            return stats.isEmpty ? "" : "\(String(localized: m.name)):\n" + stats.map(\.text).joined(separator: "\n")
        }.filter { !$0.isEmpty }
        local += goalLines
        if state.healthUpload { local += correlations }
        let modules = state.activeModules.map(\.id).filter { state.healthUpload || $0 != "activity" }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let r = try await state.api.object("POST", "/api/ai/analysis", json: [
                    "days": period, "modules": modules, "profile": state.profile.aiText,
                    "local": local.joined(separator: "\n\n"), "lang": Locale.current.language.languageCode?.identifier ?? "de",
                ])
                aiText = r["text"] as? String
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
