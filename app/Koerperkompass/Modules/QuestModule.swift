import SwiftData
import SwiftUI

/// Abenteuer: Gamification über alle Module. Tägliche Quests bringen Erfahrungspunkte (XP),
/// daraus ergeben sich Level, Rang, Attribute und Serien. Alles wird aus den vorhandenen Einträgen
/// berechnet – es werden keine eigenen Daten gespeichert.
struct QuestModule: AppModule {
    let id = "quests"
    let name: LocalizedStringResource = "Abenteuer"
    let symbol = "flag.checkered"
    let fields: [Field] = []

    func tile(_ entries: [Entry]) -> AnyView { AnyView(QuestTile()) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(QuestDetail()) }
}

enum Attribute: CaseIterable {
    case strength, endurance, recovery, discipline, balance
    var title: LocalizedStringResource {
        switch self {
        case .strength: "Kraft"
        case .endurance: "Ausdauer"
        case .recovery: "Erholung"
        case .discipline: "Disziplin"
        case .balance: "Balance"
        }
    }
    var symbol: String {
        switch self {
        case .strength: "dumbbell"
        case .endurance: "figure.run"
        case .recovery: "moon.stars"
        case .discipline: "checkmark.seal"
        case .balance: "scale.3d"
        }
    }
}

/// Eine tägliche Quest. `done` prüft die Einträge eines Tages (alle Module).
struct Quest {
    let id: String
    let title: LocalizedStringResource
    let symbol: String
    let module: String  // Quest gilt nur, wenn dieses Modul eingeschaltet ist
    let xp: Int
    let attribute: Attribute
    let done: ([Entry], Profile) -> Bool

    static let bonus = 50  // alle Quests eines Tages geschafft

    static let all: [Quest] = [
        Quest(id: "meals", title: "Drei Hauptmahlzeiten erfassen", symbol: "fork.knife", module: "nutrition", xp: 30, attribute: .discipline) { e, _ in
            Set(e.filter { $0.module == "nutrition" }.compactMap { $0.text("meal") }).isSuperset(of: ["breakfast", "lunch", "dinner"])
        },
        Quest(id: "protein", title: "Eiweißziel erreichen", symbol: "bolt.heart", module: "nutrition", xp: 30, attribute: .strength) { e, p in
            p.protein > 0 && sum(e, "nutrition", "protein") >= p.protein * 0.9
        },
        Quest(id: "kcal", title: "Kalorien im Zielbereich", symbol: "target", module: "nutrition", xp: 40, attribute: .balance) { e, p in
            let k = sum(e, "nutrition", "kcal")
            return k > 0 && abs(k - p.kcal) <= p.kcal * 0.1
        },
        Quest(id: "steps", title: "8.000 Schritte", symbol: "figure.walk", module: "activity", xp: 30, attribute: .endurance) { e, _ in
            sum(e, "activity", "steps") >= 8000
        },
        Quest(id: "sleep", title: "7 Stunden Schlaf", symbol: "bed.double", module: "activity", xp: 30, attribute: .recovery) { e, _ in
            sum(e, "activity", "sleepHours") >= 7
        },
        Quest(id: "water", title: "Wasserziel erreichen", symbol: "drop", module: "water", xp: 20, attribute: .recovery) { e, p in
            sum(e, "water", "ml") >= (p.water ?? 2000)
        },
        Quest(id: "training", title: "Training absolvieren", symbol: "dumbbell", module: "training", xp: 40, attribute: .strength) { e, _ in
            e.contains { $0.module == "training" } || sum(e, "activity", "workoutMinutes") >= 20
        },
        Quest(id: "weigh", title: "Gewicht messen", symbol: "scalemass", module: "body", xp: 10, attribute: .discipline) { e, _ in
            e.contains { $0.module == "body" && $0.num("weight") != nil }
        },
    ]

    private static func sum(_ e: [Entry], _ module: String, _ key: String) -> Double {
        e.filter { $0.module == module }.compactMap { $0.num(key) }.reduce(0, +)
    }
}

/// Stand einer Quest heute
struct QuestState {
    let quest: Quest
    let done: Bool
}

/// Fortschritt aus allen Einträgen
struct QuestProgress {
    var xp = 0
    var streak = 0
    var attributes: [Attribute: Int] = [:]
    var today: [QuestState] = []

    /// Level-Kurve: Level n beginnt bei 50·(n−1)² XP – anfangs schnell, später langsamer
    var level: Int { Int((Double(xp) / 50).squareRoot()) + 1 }
    static func xp(for level: Int) -> Int { 50 * (level - 1) * (level - 1) }
    var levelProgress: Double {
        Double(xp - Self.xp(for: level)) / Double(Self.xp(for: level + 1) - Self.xp(for: level))
    }

    /// Ränge nach Level
    static let ranks: [(level: Int, title: LocalizedStringResource)] = [
        (1, "Wanderer"), (5, "Pfadfinder"), (10, "Fährtenleser"), (20, "Kartograph"),
        (30, "Navigator"), (45, "Entdecker"), (60, "Legende"),
    ]
    var rank: LocalizedStringResource { Self.ranks.last { $0.level <= level }!.title }
    var nextRank: (level: Int, title: LocalizedStringResource)? { Self.ranks.first { $0.level > level } }

    init() {}

    init(_ entries: [Entry], _ profile: Profile) {
        let quests = Quest.all.filter { profile.modules.contains($0.module) }
        let days = Dictionary(grouping: entries.filter { !$0.deleted }, by: \.date)
        var active = Set<String>()
        for (day, es) in days {
            let done = quests.filter { $0.done(es, profile) }
            for q in done {
                xp += q.xp
                attributes[q.attribute, default: 0] += q.xp
            }
            if !done.isEmpty { active.insert(day) }
            if !quests.isEmpty && done.count == quests.count {
                xp += Quest.bonus
                attributes[.discipline, default: 0] += Quest.bonus
            }
        }
        // Serie: aufeinanderfolgende Tage mit mindestens einer Quest (heute darf noch offen sein)
        var date = Date()
        var first = true
        while true {
            if active.contains(Day.string(date)) { streak += 1 } else if !first { break }
            first = false
            date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        }
        let todays = days[Day.today] ?? []
        today = quests.map { QuestState(quest: $0, done: $0.done(todays, profile)) }
    }

    /// Attributwert: startet bei 1, +1 je 100 XP
    func value(_ a: Attribute) -> Int { 1 + (attributes[a] ?? 0) / 100 }
}

private struct QuestTile: View {
    @Environment(AppState.self) private var state
    @Query private var entries: [Entry]
    var body: some View {
        let p = QuestProgress(entries, state.profile)
        TileCard(module: QuestModule()) {
            Text("Level \(p.level)").font(.title2.bold())
            Text(p.rank).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: p.levelProgress).tint(.orange)
            Text("\(p.today.filter { $0.done }.count)/\(p.today.count) Quests · 🔥 \(p.streak)").font(.caption)
        }
    }
}

private struct QuestDetail: View {
    @Environment(AppState.self) private var state
    @Query private var entries: [Entry]
    @AppStorage("seenLevel") private var seenLevel = 0
    @State private var levelUp = false

    var body: some View {
        let p = QuestProgress(entries, state.profile)
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "safari.fill").font(.system(size: 56)).foregroundStyle(.orange.gradient)
                        .symbolEffect(.bounce, value: p.level)
                    Text("Level \(p.level)").font(.largeTitle.bold())
                    Text(p.rank).font(.headline).foregroundStyle(.secondary)
                    ProgressView(value: p.levelProgress).tint(.orange)
                    Text("\(p.xp) XP · noch \(QuestProgress.xp(for: p.level + 1) - p.xp) XP bis Level \(p.level + 1)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let next = p.nextRank {
                        Text("Nächster Rang ab Level \(next.level): \(String(localized: next.title))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                ForEach(p.today, id: \.quest.id) { item in
                    HStack {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? .green : .secondary)
                        Label { Text(item.quest.title) } icon: { Image(systemName: item.quest.symbol) }
                        Spacer()
                        Text("+\(item.quest.xp) XP").font(.caption.bold()).foregroundStyle(.orange)
                    }
                    .opacity(item.done ? 0.6 : 1)
                }
            } header: { Text("Heutige Quests") } footer: {
                Text("Alle Quests eines Tages geschafft: +\(Quest.bonus) XP Bonus. Serie: \(p.streak) Tage in Folge.")
            }
            Section("Attribute") {
                ForEach(Attribute.allCases, id: \.self) { a in
                    HStack {
                        Label { Text(a.title) } icon: { Image(systemName: a.symbol) }
                        Spacer()
                        Text("\(p.value(a))").font(.headline.monospacedDigit())
                    }
                }
            }
            Section {
                Text("Quests richten sich nach deinen eingeschalteten Modulen und Tageszielen. Es geht um kleine, gesunde Gewohnheiten – nicht um Rekorde.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if seenLevel > 0 && p.level > seenLevel { levelUp = true }
            seenLevel = p.level
        }
        .alert("Level aufgestiegen!", isPresented: $levelUp) {
            Button("Weiter") {}
        } message: {
            Text("Du hast Level \(p.level) erreicht – \(String(localized: p.rank)).")
        }
    }
}
