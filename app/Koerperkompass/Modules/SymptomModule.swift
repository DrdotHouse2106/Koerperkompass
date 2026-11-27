import HealthKit
import SwiftUI

/// Beschwerden und Krankheitssymptome (verstopfte Nase, Husten, Kopfschmerzen …) mit Stärke – wie die Symptome in Apple Health.
/// Wird mit Health-Freigabe auch in Apple Health gespeichert und von dort gelesen. Der Coach berücksichtigt sie (z. B. beim Training).
struct SymptomModule: AppModule {
    let id = "symptoms"
    let name: LocalizedStringResource = "Beschwerden"
    let symbol = "cross.case.fill"
    let fields = [Field(key: "severity", name: "Stärke", unit: "(1–3)", agg: .avg)]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(SymptomTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(SymptomDetail(entries: entries)) }
}

enum Symptoms {
    /// Kennung → Name und Apple-Health-Typ
    /// hk nil = gibt es in Apple Health nicht (nur in Körperkompass)
    static let all: [(id: String, name: LocalizedStringResource, hk: HKCategoryTypeIdentifier?)] = [
        ("sinusCongestion", "Verstopfte Nase", .sinusCongestion), ("runnyNose", "Schnupfen", .runnyNose),
        ("soreThroat", "Halsschmerzen", .soreThroat), ("coughing", "Husten", .coughing), ("headache", "Kopfschmerzen", .headache),
        ("fever", "Fieber", .fever), ("chills", "Schüttelfrost", .chills), ("fatigue", "Erschöpfung", .fatigue),
        ("bodyAndMuscleAches", "Gliederschmerzen", .generalizedBodyAche), ("lowerBackPain", "Rückenschmerzen", .lowerBackPain),
        ("nausea", "Übelkeit", .nausea), ("diarrhea", "Durchfall", .diarrhea), ("dizziness", "Schwindel", .dizziness),
        ("shortnessOfBreath", "Kurzatmigkeit", .shortnessOfBreath), ("lossOfSmell", "Geruchsverlust", .lossOfSmell),
        ("sleepChanges", "Schlafprobleme", .sleepChanges), ("kneePain", "Knieschmerzen", nil), ("jointPain", "Gelenkschmerzen", nil),
        ("muscleSoreness", "Muskelkater", nil), ("other", "Sonstiges", nil),
    ]
    static let severities: [LocalizedStringResource] = ["Leicht", "Mittel", "Stark"]

    static func name(_ id: String) -> String { all.first { $0.id == id }.map { String(localized: $0.name) } ?? id }

    /// Kurzform für den Coach: aktive Beschwerden der letzten 7 Tage mit Dauer
    static func summary(_ entries: [Entry]) -> String? {
        let recent = entries.filter { $0.module == "symptoms" && !$0.deleted && Day.last(7).contains($0.date) }
        guard !recent.isEmpty else { return nil }
        let byId = Dictionary(grouping: recent) { $0.text("symptom") ?? $0.text("name") ?? "" }
        return byId.map { id, es in
            let days = Set(es.map(\.date)).count, last = es.max { $0.date < $1.date }
            let sev = Int(last?.num("severity") ?? 1)
            return "\(last?.text("name") ?? name(id)) (\(String(localized: severities[max(0, min(2, sev - 1))])), an \(days) von 7 Tagen, zuletzt \(last?.date ?? ""))"
        }.sorted().joined(separator: "; ")
    }
}

extension Health {
    static var symptomTypes: [HKCategoryType] { Symptoms.all.compactMap { $0.hk.map { HKCategoryType($0) } } }

    /// Beschwerde in Apple Health speichern (Stärke 1–3 → leicht/mittel/stark)
    static func saveSymptom(_ id: String, severity: Int) {
        guard let hk = Symptoms.all.first(where: { $0.id == id })?.hk else { return }
        let value = [HKCategoryValueSeverity.mild, .moderate, .severe][max(0, min(2, severity - 1))].rawValue
        store.save(HKCategorySample(type: HKCategoryType(hk), value: value, start: Date(), end: Date())) { _, _ in }
    }

    /// Beschwerden aus Health (andere Apps, Health-App); eigene werden übersprungen
    static func symptoms(days: Int) async -> [(id: String, date: String, values: [String: Any])] {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))!
        var out: [(id: String, date: String, values: [String: Any])] = []
        for s in Symptoms.all {
            guard let hk = s.hk else { continue }
            let p = HKQuery.predicateForSamples(withStart: start, end: nil)
            let samples = (try? await HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(hk), predicate: p)], sortDescriptors: []).result(for: store)) ?? []
            for x in samples where x.sourceRevision.source != HKSource.default() && x.value != HKCategoryValueSeverity.notPresent.rawValue {
                let sev = x.value == HKCategoryValueSeverity.severe.rawValue ? 3 : x.value == HKCategoryValueSeverity.moderate.rawValue ? 2 : 1
                out.append(("health-" + x.uuid.uuidString, Day.string(x.startDate),
                            ["symptom": s.id, "name": String(localized: s.name), "severity": sev]))
            }
        }
        return out
    }
}

private struct SymptomTile: View {
    let entries: [Entry]
    var body: some View {
        let recent = entries.filter { Day.last(3).contains($0.date) }
        TileCard(module: SymptomModule()) {
            if recent.isEmpty {
                Text("Keine Beschwerden").font(.headline)
            } else {
                Text(Set(recent.compactMap { $0.text("name") }).sorted().joined(separator: ", ")).font(.headline).lineLimit(2)
                Text("letzte 3 Tage").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SymptomDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var picked: String?
    @State private var severity = 2
    @State private var other = ""

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(Symptoms.all, id: \.id) { s in
                        Button { picked = s.id } label: {
                            Text(s.name).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background((picked == s.id ? Theme.orange : Color.white).opacity(picked == s.id ? 0.5 : 0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                if picked == "other" { TextField("Was genau? (z. B. Zahnschmerzen)", text: $other) }
                if picked != nil {
                    Picker("Stärke", selection: $severity) {
                        ForEach(1...3, id: \.self) { Text(Symptoms.severities[$0 - 1]).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Eintragen", systemImage: "checkmark.circle.fill") { save() }.bold()
                }
            } header: { Text("Was hast du?") } footer: {
                if state.healthEnabled { Text("Wird auch in Apple Health unter „Symptome“ gespeichert.") }
            }
            Section("Verlauf") {
                EntryRows(entries: entries.sorted { $0.date > $1.date }) { e in
                    "\(e.text("name") ?? Symptoms.name(e.text("symptom") ?? "")) · \(String(localized: Symptoms.severities[max(0, min(2, Int(e.num("severity") ?? 1) - 1))]))"
                }
            }
            Section {
                Text("Keine ärztliche Beratung. Bei hohem oder anhaltendem Fieber, Atemnot, starken oder länger als ein paar Tage anhaltenden Beschwerden bitte ärztlich abklären lassen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        guard let picked else { return }
        context.insert(Entry(module: "symptoms", values: ["symptom": picked, "name": picked == "other" && !other.isEmpty ? other : Symptoms.name(picked), "severity": severity, "time": Day.now]))
        if state.healthEnabled { Health.saveSymptom(picked, severity: severity) }
        state.changed(context)
        self.picked = nil
        other = ""
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
