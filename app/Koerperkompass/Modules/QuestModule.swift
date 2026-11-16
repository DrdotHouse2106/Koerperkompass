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
            hydration(e, e.first?.date ?? Day.today) >= p.waterGoal
        },
        Quest(id: "training", title: "Training absolvieren", symbol: "dumbbell", module: "training", xp: 40, attribute: .strength) { e, _ in
            e.contains { $0.module == "training" } || sum(e, "activity", "workoutMinutes") >= 20
        },
        Quest(id: "weigh", title: "Gewicht messen", symbol: "scalemass", module: "body", xp: 10, attribute: .discipline) { e, _ in
            e.contains { $0.module == "body" && $0.num("weight") != nil }
        },
    ]

    /// Quests eines Tages: Standard-Quests der aktiven Module, Trainingseinheit (an Trainingstagen) und eigene Quests
    static func list(_ day: String, _ p: Profile) -> [Quest] {
        var list = all.filter { p.modules.contains($0.module) && !($0.id == "training" && p.plan != nil) }
        if let plan = p.plan, plan.isTrainingDay(day) {
            list.append(Quest(id: "plan", title: "Trainingseinheit absolvieren", symbol: "figure.strengthtraining.traditional",
                              module: "quests", xp: planXP, attribute: .strength) { e, _ in e.contains { $0.module == "training" } })
        }
        for h in p.habitList {
            list.append(Quest(id: "habit-" + h, title: LocalizedStringResource(stringLiteral: h), symbol: "star", module: "quests", xp: 15, attribute: .discipline) { e, _ in
                e.contains { $0.module == "quests" && $0.text("habit") == h }
            })
        }
        return list
    }

    private static func sum(_ e: [Entry], _ module: String, _ key: String) -> Double {
        e.filter { $0.module == module }.compactMap { $0.num(key) }.reduce(0, +)
    }
}

struct Badge {
    let title: LocalizedStringResource
    let symbol: String
    let unlocked: Bool
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
    var activeDays = Set<String>()
    var planDone = 0
    var missed = 0
    var bestStreak = 0
    var workouts = 0
    var meals = 0
    var exerciseSets = 0
    var weekQuests = 0      // Wochen-Challenge: geschaffte Quests seit Montag
    var weekXP = 0

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
        let days = Dictionary(grouping: entries.filter { !$0.deleted }, by: \.date)
        var active = Set<String>()
        for (day, es) in days {
            let quests = Quest.list(day, profile)
            let done = quests.filter { $0.done(es, profile) }
            if day >= Day.weekStart {
                weekQuests += done.count
                weekXP += done.reduce(0) { $0 + $1.xp }
            }
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
        today = Quest.list(Day.today, profile).map { QuestState(quest: $0, done: $0.done(todays, profile)) }
        activeDays = active
        var run = 0, prev: Date?
        for d in active.map(Day.date).sorted() {
            run = prev.map { Calendar.current.dateComponents([.day], from: $0, to: d).day == 1 } == true ? run + 1 : 1
            bestStreak = max(bestStreak, run)
            prev = d
        }
        let live = entries.filter { !$0.deleted }
        workouts = live.filter { $0.module == "training" }.count
        meals = live.filter { $0.module == "nutrition" }.count
        exerciseSets = live.filter { $0.module == "exercises" }.count

        // Trainingsprogramm: absolvierte Einheiten zählen, verpasste Trainingstage ggf. abziehen
        if let plan = profile.plan {
            planDone = entries.filter { $0.id.hasPrefix("plan-") && !$0.deleted && $0.date >= plan.start }.count
            var date = Day.date(plan.start)
            while Day.string(date) < min(Day.today, plan.end) {
                let day = Day.string(date)
                if plan.isTrainingDay(day) && !(days[day] ?? []).contains(where: { $0.module == "training" }) { missed += 1 }
                date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
            }
            if profile.penalties == true { xp = max(0, xp - missed * missedXP) }
        }
    }

    /// Attributwert: startet bei 1, +1 je 100 XP
    func value(_ a: Attribute) -> Int { 1 + (attributes[a] ?? 0) / 100 }

    /// Klasse nach dem stärksten Attribut
    var characterClass: LocalizedStringResource {
        guard let top = attributes.max(by: { $0.value < $1.value })?.key else { return "Neuling" }
        switch top {
        case .strength: return "Kraftpaket"
        case .endurance: return "Ausdauerläufer"
        case .recovery: return "Ruhepol"
        case .discipline: return "Stratege"
        case .balance: return "Allrounder"
        }
    }

    /// Abzeichen – werden aus dem Fortschritt berechnet
    func badges(_ profile: Profile) -> [Badge] {
        [
            Badge(title: "Erster Schritt", symbol: "shoeprints.fill", unlocked: xp > 0),
            Badge(title: "7 Tage am Stück", symbol: "flame", unlocked: bestStreak >= 7),
            Badge(title: "30 Tage am Stück", symbol: "flame.fill", unlocked: bestStreak >= 30),
            Badge(title: "10 Workouts", symbol: "dumbbell", unlocked: workouts >= 10),
            Badge(title: "50 Workouts", symbol: "dumbbell.fill", unlocked: workouts >= 50),
            Badge(title: "100 Mahlzeiten", symbol: "fork.knife", unlocked: meals >= 100),
            Badge(title: "100 Sätze", symbol: "chart.line.uptrend.xyaxis", unlocked: exerciseSets >= 100),
            Badge(title: "Level 5", symbol: "star", unlocked: level >= 5),
            Badge(title: "Level 10", symbol: "star.fill", unlocked: level >= 10),
            Badge(title: "Level 25", symbol: "crown", unlocked: level >= 25),
            Badge(title: "Programm beendet", symbol: "trophy", unlocked: profile.plan?.finished == true && planDone > 0),
            Badge(title: "Ohne Fehltag", symbol: "checkmark.seal", unlocked: profile.plan != nil && planDone >= 6 && missed == 0),
        ]
    }
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
    @Environment(\.modelContext) private var context
    @Query private var entries: [Entry]
    @AppStorage("seenLevel") private var seenLevel = 0
    @State private var levelUp = false
    @State private var newHabit = ""

    var body: some View {
        let p = QuestProgress(entries, state.profile)
        List {
            Section {
                WeekStrip(active: p.activeDays)
                CharacterCard(progress: p)
            }

            TodayCard(progress: p)

            Section {
                NavigationLink { FriendsView() } label: {
                    Label("Freunde & Wochen-Challenge", systemImage: "person.2.fill")
                }
            }

            Section {
                ForEach(p.today, id: \.quest.id) { item in
                    Button {
                        if item.quest.id.hasPrefix("habit-") { toggle(String(item.quest.id.dropFirst(6))) }
                    } label: {
                        HStack {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? .green : .secondary)
                            Label { Text(item.quest.title) } icon: { Image(systemName: item.quest.symbol) }
                            Spacer()
                            Text("+\(item.quest.xp) XP").font(.caption.bold()).foregroundStyle(.orange)
                        }
                        .opacity(item.done ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text("Heutige Quests") } footer: {
                Text("Alle Quests eines Tages geschafft: +\(Quest.bonus) XP Bonus. Eigene Quests hakst du durch Antippen ab.")
            }

            Section {
                ForEach(state.profile.habitList, id: \.self) { Text($0) }
                    .onDelete { idx in state.profile.habits = state.profile.habitList.enumerated().filter { !idx.contains($0.offset) }.map(\.element) }
                HStack {
                    TextField("Neue Quest, z. B. „10 Minuten dehnen“", text: $newHabit)
                    Button("Hinzufügen") {
                        state.profile.habits = state.profile.habitList + [newHabit.trimmingCharacters(in: .whitespaces)]
                        newHabit = ""
                    }
                    .disabled(newHabit.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Eigene Quests") } footer: { Text("Gelten jeden Tag, +15 XP pro Quest.") }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 16) {
                    ForEach(p.badges(state.profile), id: \.symbol) { b in
                        VStack(spacing: 6) {
                            Image(systemName: b.unlocked ? b.symbol : "questionmark").font(.title2)
                                .frame(width: 52, height: 52)
                                .background(b.unlocked ? Color.orange.opacity(0.2) : Color.gray.opacity(0.1), in: Circle())
                                .foregroundStyle(b.unlocked ? .orange : .secondary)
                            Text(b.title).font(.caption2).multilineTextAlignment(.center)
                        }
                        .opacity(b.unlocked ? 1 : 0.45)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Erfolge – \(p.badges(state.profile).filter(\.unlocked).count)/\(p.badges(state.profile).count) freigeschaltet")
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Label("\(p.streak)", systemImage: "flame.fill").labelStyle(.titleAndIcon).foregroundStyle(.orange) }
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

    /// Eigene Quest für heute abhaken bzw. wieder öffnen
    private func toggle(_ habit: String) {
        let id = "habit-\(Day.today)-\(habit)"
        if let e = context.entry(id), !e.deleted {
            state.delete(e, context)
        } else {
            context.upsert(id: id, module: "quests", date: Day.today, values: ["habit": habit], dirty: !state.demo)
            state.changed(context)
        }
    }
}

/// Aktuelle Woche (Mo–So): gefüllter Punkt = an dem Tag mindestens eine Quest geschafft
private struct WeekStrip: View {
    let active: Set<String>
    var body: some View {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let monday = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
        return HStack {
            ForEach(days, id: \.self) { d in
                let day = Day.string(d), today = day == Day.today
                VStack(spacing: 6) {
                    Text(d, format: .dateTime.weekday(.narrow)).font(.caption2)
                    Text(d, format: .dateTime.day()).font(.callout.bold())
                    Image(systemName: active.contains(day) ? "circle.fill" : "circle").font(.caption2)
                        .foregroundStyle(active.contains(day) ? .orange : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(today ? Color.orange.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

/// Heute: fällige Trainingseinheit oder Ruhetag – plus Zugang zu den Programmen
struct TodayCard: View {
    let progress: QuestProgress
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query private var entries: [Entry]

    var body: some View {
        let plan = state.profile.plan
        let doneToday = entries.contains { $0.id == "plan-" + Day.today && !$0.deleted }
        Section {
            if let plan, plan.finished {
                Label("Programm abgeschlossen!", systemImage: "trophy.fill").font(.headline).foregroundStyle(.orange)
                Text("Glückwunsch – \(progress.planDone) Einheiten geschafft. Such dir ein neues Programm aus.")
            } else if let plan, plan.isTrainingDay(Day.today), let planned = plan.next(done: progress.planDone - (doneToday ? 1 : 0)) {
                let suggestion = state.profile.suggestion?.day == Day.today ? state.profile.suggestion : nil
                let day = suggestion?.session ?? planned
                Text(day.title).font(.headline)
                if let suggestion {
                    Label("Von deinem Coach angepasst", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(.orange)
                    if !suggestion.note.isEmpty { Text(suggestion.note).font(.caption).foregroundStyle(.secondary) }
                } else if let hint = localHint(entries) {
                    Label { Text(hint) } icon: { Image(systemName: "arrow.up.right.circle") }.font(.caption).foregroundStyle(.secondary)
                }
                ForEach(day.exercises, id: \.self) { Label($0, systemImage: "checkmark.circle").font(.subheadline) }
                if let done = entries.first(where: { $0.id == "plan-" + Day.today && !$0.deleted }) {
                    Label("Einheit erledigt ✓", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    FeedbackButtons(entry: done)
                } else {
                    Button("Einheit abschließen (+\(planXP) XP)") {
                        context.upsert(id: "plan-" + Day.today, module: "training", date: Day.today,
                                       values: ["name": day.title, "minutes": 45], dirty: !state.demo)
                        state.changed(context)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    NavigationLink { VoiceCoachView(plan: day) } label: {
                        Label("Sprach-Coach starten", systemImage: "mic.circle.fill").foregroundStyle(.purple)
                    }
                    if (OnDevice.available || state.aiAvailable) && suggestion == nil { CoachButton(session: planned, entries: entries) }
                }
                if state.profile.modules.contains("exercises") {
                    NavigationLink("Sätze eintragen") {
                        ExerciseModule().detail(entries.filter { $0.module == "exercises" && !$0.deleted }).navigationTitle(Text("Übungen")).themed()
                    }
                }
            } else if plan != nil {
                Label("Ruhetag", systemImage: "moon.zzz").font(.headline)
                Text("Erholung gehört zum Training. Heute zählen deine eigenen Quests – Schlaf, Essen, Ausgleich.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Wähle ein Trainingsprogramm – an Trainingstagen gibt es dann eine Einheit mit +\(planXP) XP.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if progress.missed > 0 {
                if state.profile.penalties == true {
                    Text("Verpasste Einheiten: \(progress.missed) (−\(progress.missed * missedXP) XP)").font(.caption).foregroundStyle(.red)
                } else {
                    Text("Verpasste Einheiten: \(progress.missed)").font(.caption).foregroundStyle(.secondary)
                }
            }
            NavigationLink("Programm verwalten") { PlanView() }
        } header: { Text(state.profile.plan?.name ?? String(localized: "Training")) }
    }
}

/// Charakterkarte: Ringe für Level, Workouts und Serie, Klasse, Rang und Körperdaten
private struct CharacterCard: View {
    let progress: QuestProgress
    @Environment(AppState.self) private var state
    @Query(sort: \Entry.date) private var entries: [Entry]
    @State private var showCard = false

    var body: some View {
        let p = progress, prof = state.profile
        let weight = entries.last { $0.module == "body" && !$0.deleted && $0.num("weight") != nil }?.num("weight") ?? prof.weight
        VStack(spacing: 14) {
            HStack {
                stat(Text("\(p.level)"), "Level", p.levelProgress, .orange)
                stat(Text("\(p.workouts)"), "Workouts", min(Double(p.workouts % 10) / 10, 1), .purple)
                stat(Text("\(p.streak)"), "Serie", min(Double(p.streak) / 7, 1), .red)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Klasse").foregroundStyle(.secondary); Text(p.characterClass).bold()
                    Text("Größe").foregroundStyle(.secondary); Text("\(prof.height.whole) cm").bold()
                }
                GridRow {
                    Text("Rang").foregroundStyle(.secondary); Text(p.rank).bold()
                    Text("Gewicht").foregroundStyle(.secondary); Text("\(weight.short) kg").bold()
                }
                GridRow {
                    Text("Alter").foregroundStyle(.secondary); Text("\(prof.age)").bold()
                    Text("Ziel").foregroundStyle(.secondary); Text("\(prof.targetWeight.short) kg").bold()
                }
            }
            .font(.subheadline)
            Text("\(p.xp) XP · noch \(QuestProgress.xp(for: p.level + 1) - p.xp) XP bis Level \(p.level + 1)")
                .font(.caption).foregroundStyle(.secondary)
            if let next = p.nextRank {
                Text("Nächster Rang ab Level \(next.level): \(String(localized: next.title))").font(.caption).foregroundStyle(.secondary)
            }
            Button("Spielerkarte", systemImage: "person.crop.rectangle") { showCard = true }
                .buttonStyle(.bordered).tint(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .sheet(isPresented: $showCard) { PlayerCardView(progress: p) }
    }

    private func stat(_ value: Text, _ label: LocalizedStringResource, _ progress: Double, _ color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Ring(progress: progress, color: color, size: 64)
                value.font(.title3.bold())
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
