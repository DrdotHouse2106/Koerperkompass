import Charts
import HealthKit
import SwiftUI

/// Stimmung (seelisches Wohlbefinden): Stufe 1–7 wie in Apple Health („Gemütszustand“), dazu Gefühle und Lebensbereiche.
/// Wird – mit Health-Freigabe, ab iOS 18 – auch in Apple Health gespeichert und von dort gelesen (Health-App, Watch, andere Apps).
struct MoodModule: AppModule {
    let id = "mood"
    let name: LocalizedStringResource = "Stimmung"
    let symbol = "face.smiling"
    let fields = [Field(key: "mood", name: "Stimmung", unit: "(1–7)", agg: .avg)]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(MoodTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(MoodDetail(entries: entries)) }
}

enum Mood {
    struct Level { let emoji: String; let title: LocalizedStringResource; let color: Color }
    /// 1 = sehr unangenehm … 7 = sehr angenehm (wie Apple Health)
    static let levels: [Level] = [
        .init(emoji: "😣", title: "Sehr unangenehm", color: Color(red: 0.45, green: 0.35, blue: 0.85)),
        .init(emoji: "😟", title: "Unangenehm", color: Color(red: 0.4, green: 0.45, blue: 0.9)),
        .init(emoji: "🙁", title: "Eher unangenehm", color: Color(red: 0.35, green: 0.6, blue: 0.9)),
        .init(emoji: "😐", title: "Neutral", color: Color(red: 0.45, green: 0.75, blue: 0.85)),
        .init(emoji: "🙂", title: "Eher angenehm", color: Color(red: 0.55, green: 0.8, blue: 0.5)),
        .init(emoji: "😊", title: "Angenehm", color: Color(red: 0.95, green: 0.75, blue: 0.3)),
        .init(emoji: "😄", title: "Sehr angenehm", color: Color(red: 1, green: 0.6, blue: 0.2)),
    ]
    static func level(_ valence: Double) -> Int { min(7, max(1, Int(((valence + 1) * 3).rounded()) + 1)) }
    static func valence(_ level: Int) -> Double { Double(min(7, max(1, level)) - 1) / 3 - 1 }

    /// Gefühle (Auswahl) → Health-Label
    static let feelings: [(id: String, name: LocalizedStringResource)] = [
        ("happy", "Glücklich"), ("content", "Zufrieden"), ("calm", "Ruhig"), ("grateful", "Dankbar"), ("proud", "Stolz"),
        ("confident", "Selbstsicher"), ("excited", "Begeistert"), ("hopeful", "Hoffnungsvoll"), ("relieved", "Erleichtert"),
        ("drained", "Erschöpft"), ("stressed", "Gestresst"), ("overwhelmed", "Überfordert"), ("anxious", "Ängstlich"),
        ("worried", "Besorgt"), ("irritated", "Gereizt"), ("frustrated", "Frustriert"), ("sad", "Traurig"), ("lonely", "Einsam"),
        ("indifferent", "Gleichgültig"),
    ]
    /// Lebensbereiche → Health-Zuordnung
    static let areas: [(id: String, name: LocalizedStringResource)] = [
        ("work", "Arbeit"), ("family", "Familie"), ("partner", "Partnerschaft"), ("friends", "Freunde"), ("health", "Gesundheit"),
        ("fitness", "Fitness"), ("selfCare", "Selbstfürsorge"), ("hobbies", "Hobbys"), ("money", "Geld"), ("tasks", "Aufgaben"),
        ("weather", "Wetter"), ("travel", "Reisen"),
    ]

    @available(iOS 18.0, *)
    static let hkLabels: [String: HKStateOfMind.Label] = [
        "happy": .happy, "content": .content, "calm": .calm, "grateful": .grateful, "proud": .proud, "confident": .confident,
        "excited": .excited, "hopeful": .hopeful, "relieved": .relieved, "drained": .drained, "stressed": .stressed,
        "overwhelmed": .overwhelmed, "anxious": .anxious, "worried": .worried, "irritated": .irritated, "frustrated": .frustrated,
        "sad": .sad, "lonely": .lonely, "indifferent": .indifferent,
    ]
    @available(iOS 18.0, *)
    static let hkAreas: [String: HKStateOfMind.Association] = [
        "work": .work, "family": .family, "partner": .partner, "friends": .friends, "health": .health, "fitness": .fitness,
        "selfCare": .selfCare, "hobbies": .hobbies, "money": .money, "tasks": .tasks, "weather": .weather, "travel": .travel,
    ]

    static func name(_ id: String, in list: [(id: String, name: LocalizedStringResource)]) -> String {
        list.first { $0.id == id }.map { String(localized: $0.name) } ?? id
    }
}

private struct MoodTile: View {
    let entries: [Entry]
    var body: some View {
        let today = entries.filter { $0.date == Day.today }.max { ($0.text("time") ?? "") < ($1.text("time") ?? "") }
        let week = entries.filter { Day.last(7).contains($0.date) }.compactMap { $0.num("mood") }
        TileCard(module: MoodModule()) {
            if let l = today?.num("mood").map({ Mood.levels[min(6, max(0, Int($0) - 1))] }) {
                Text("\(l.emoji) \(String(localized: l.title))").font(.headline)
            } else {
                Text("Wie geht’s dir?").font(.headline)
            }
            if !week.isEmpty {
                Text("Ø 7 Tage: \(Mood.levels[min(6, max(0, Int((week.reduce(0, +) / Double(week.count)).rounded()) - 1))].emoji)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MoodDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var level: Int?
    @State private var feelings: Set<String> = []
    @State private var areas: Set<String> = []
    @State private var daily = false
    @State private var saved = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { i in
                        let l = Mood.levels[i - 1]
                        Button { level = i } label: {
                            Text(l.emoji).font(.system(size: level == i ? 36 : 28))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(l.color.opacity(level == i ? 0.45 : 0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let level { Text(Mood.levels[level - 1].title).font(.headline).frame(maxWidth: .infinity) }
                Toggle("Gefühl für den ganzen Tag", isOn: $daily)
            } header: { Text("Wie fühlst du dich gerade?") }
            if level != nil {
                Section("Was beschreibt es am besten?") { chips(Mood.feelings, $feelings) }
                Section("Was beeinflusst dich?") { chips(Mood.areas, $areas) }
                Section {
                    Button(saved ? LocalizedStringKey("Eingetragen ✓") : "Eintragen", systemImage: "checkmark.circle.fill") { save() }.bold()
                } footer: {
                    if state.healthEnabled { Text("Wird auch in Apple Health unter „Gemütszustand“ gespeichert (ab iOS 18).") }
                }
            }
            let days = Day.last(14)
            let byDay = Dictionary(grouping: entries.filter { days.contains($0.date) }, by: \.date)
                .compactMapValues { es -> Double? in let v = es.compactMap { $0.num("mood") }; return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
            if !byDay.isEmpty {
                Section("Letzte 14 Tage") {
                    Chart(byDay.sorted { $0.key < $1.key }, id: \.key) { d in
                        LineMark(x: .value("Tag", Day.date(d.key), unit: .day), y: .value("Stimmung", d.value)).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Tag", Day.date(d.key), unit: .day), y: .value("Stimmung", d.value))
                    }
                    .chartYScale(domain: 1...7)
                    .frame(height: 160)
                }
            }
            Section("Verlauf") {
                EntryRows(entries: entries.sorted { ($0.date, $0.text("time") ?? "") > ($1.date, $1.text("time") ?? "") }) { e in
                    let l = Mood.levels[max(0, min(6, Int(e.num("mood") ?? 4) - 1))]
                    let f = ((e.values["feelings"] as? [String]) ?? []).map { Mood.name($0, in: Mood.feelings) }
                    return "\(e.text("time").map { $0 + " · " } ?? "")\(l.emoji) \(String(localized: l.title))" + (f.isEmpty ? "" : " · " + f.joined(separator: ", "))
                }
            }
            Section {
                Text("Keine ärztliche Beratung. Fühlst du dich über längere Zeit niedergeschlagen oder überfordert, sprich mit einer Ärztin, einem Arzt oder der Telefonseelsorge (0800 111 0 111, rund um die Uhr, kostenlos).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: level) { saved = false }
    }

    private func chips(_ list: [(id: String, name: LocalizedStringResource)], _ sel: Binding<Set<String>>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
            ForEach(list, id: \.id) { item in
                let on = sel.wrappedValue.contains(item.id)
                Button { if on { sel.wrappedValue.remove(item.id) } else { sel.wrappedValue.insert(item.id) } } label: {
                    Text(item.name).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background((on ? Theme.orange : Color.white).opacity(on ? 0.5 : 0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        guard let level else { return }
        context.insert(Entry(module: "mood", values: [
            "mood": level, "valence": Mood.valence(level), "feelings": Array(feelings), "areas": Array(areas),
            "kind": daily ? "daily" : "moment", "time": Day.now,
        ]))
        if state.healthEnabled { Health.saveMood(level: level, daily: daily, feelings: Array(feelings), areas: Array(areas)) }
        state.changed(context)
        saved = true
        feelings = []
        areas = []
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
