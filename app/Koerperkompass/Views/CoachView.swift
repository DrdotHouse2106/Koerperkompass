import SwiftData
import SwiftUI

/// Gesundheitscoach: Gespräch mit Claude über die eigenen Daten. Der Verlauf bleibt nur auf dem iPhone.
struct CoachView: View {
    @Environment(AppState.self) private var state
    @Query(sort: \Entry.date) private var entries: [Entry]
    @AppStorage("coachChat") private var stored = Data()
    @AppStorage("coachReminder") private var reminder = false
    @AppStorage("coachHour") private var hour = 8
    @State private var input = ""
    @State private var busy = false
    @State private var error: String?
    @State private var askConsent = false
    @State private var pending: String?
    @State private var showCompass = false

    struct Message: Codable, Hashable {
        let role: String  // "user" oder "assistant"
        let text: String
    }

    private var messages: [Message] { (try? JSONDecoder().decode([Message].self, from: stored)) ?? [] }

    private let prompts: [LocalizedStringResource] = [
        "Mein Tag: Gib mir ein kurzes Briefing mit einem Tipp für heute.",
        "Was soll ich heute noch essen?",
        "Wie war meine Woche?",
        "Bin müde – trainieren oder lieber Pause?",
        "Wie komme ich schneller zu meinem Ziel?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        intro
                        ForEach(Array(messages.enumerated()), id: \.offset) { i, m in
                            bubble(m).id(i)
                        }
                        if busy {
                            HStack { ProgressView(); Text("Dein Coach denkt nach …").foregroundStyle(.secondary) }
                                .frame(maxWidth: .infinity, alignment: .leading).id("busy")
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { withAnimation { proxy.scrollTo(messages.count - 1, anchor: .bottom) } }
                .onChange(of: busy) { if busy { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } } }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Auswertung", systemImage: "chart.bar.xaxis") { showCompass = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Tägliche Erinnerung", isOn: $reminder)
                        Picker("Uhrzeit", selection: $hour) {
                            ForEach(6..<22) { Text("\($0):00 Uhr").tag($0) }
                        }
                        Button("Gespräch löschen", systemImage: "trash", role: .destructive) { stored = Data() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showCompass) { CompassView() }
            .onChange(of: [reminder ? 1 : 0, hour]) {
                Task {
                    if reminder { await Reminders.scheduleCoach(hour: hour) } else { Reminders.cancelCoach() }
                }
            }
            .alert("Daten an Claude senden?", isPresented: $askConsent) {
                Button("Zustimmen") { state.aiConsent = true; if let pending { send(pending) } }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Für das Gespräch werden deine Nachricht, dein Profil und eine Zusammenfassung deiner Daten (Ernährung, Getränke, Gewicht, Training; Schlaf und Schritte nur mit Health-Zustimmung) über deinen Server an die Claude API (Anthropic) gesendet. Der Gesprächsverlauf bleibt auf deinem iPhone.")
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(symbol: "heart.text.square.fill", module: "quests", size: 48)
                VStack(alignment: .leading) {
                    Text("Dein Gesundheitscoach").font(.title3.bold())
                    Text("Kennt deine Ziele, dein Essen, Trinken und Training.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !state.aiAvailable {
                Text(state.demo
                     ? LocalizedStringKey("Im Demo-Modus ist der Coach nicht verfügbar – er braucht deinen eigenen Server mit Claude-API-Key.")
                     : "Damit der Coach antworten kann, muss auf deinem Server ein Claude-API-Key eingetragen sein (ANTHROPIC_API_KEY, siehe Anleitung).")
                    .font(.callout).foregroundStyle(.orange)
            }
            Text("Keine ärztliche Beratung – bei Beschwerden bitte ärztlich abklären lassen.").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Theme.orange)
    }

    private func bubble(_ m: Message) -> some View {
        let mine = m.role == "user"
        let text = (try? AttributedString(markdown: m.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(m.text)
        return HStack {
            if mine { Spacer(minLength: 40) }
            Text(text)
                .padding(12)
                .background(mine ? Theme.orange.opacity(0.85) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(.white)
                .textSelection(.enabled)
            if !mine { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(prompts.indices, id: \.self) { i in
                        Button { send(String(localized: prompts[i])) } label: {
                            Text(prompts[i]).font(.caption).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                TextField("Frag deinen Coach …", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .disabled(!state.aiAvailable)
    }

    private func save(_ list: [Message]) { stored = (try? JSONEncoder().encode(Array(list.suffix(60)))) ?? Data() }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        guard state.aiConsent else { pending = text; askConsent = true; return }
        input = ""
        error = nil
        let list = messages + [Message(role: "user", text: text)]
        save(list)
        busy = true
        Task {
            defer { busy = false }
            do {
                let r = try await state.api.object("POST", "/api/ai/coach", json: [
                    "messages": list.suffix(30).map { ["role": $0.role, "content": $0.text] },
                    "context": coachContext(entries, state.profile, healthUpload: state.healthUpload),
                    "lang": Locale.current.language.languageCode?.identifier ?? "de",
                ])
                save(list + [Message(role: "assistant", text: r["text"] as? String ?? "")])
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Zusammenfassung der eigenen Daten für den Coach. Health-Daten nur mit Zustimmung zum Hochladen.
func coachContext(_ all: [Entry], _ p: Profile, healthUpload: Bool) -> String {
    let entries = all.filter { !$0.deleted && (healthUpload || !($0.id.hasPrefix("activity-") || $0.id.hasPrefix("health-"))) }
    let today = entries.filter { $0.date == Day.today }
    func sum(_ module: String, _ key: String) -> Double {
        today.filter { $0.module == module }.compactMap { $0.num(key) }.reduce(0, +)
    }
    let kcal = sum("nutrition", "kcal") + sum("water", "kcal")
    let meals = today.filter { $0.module == "nutrition" }.compactMap { e -> String? in
        guard let n = e.text("name") else { return nil }
        return "\(n) (\(e.text("meal") ?? ""))"
    }
    var drinks = "- Getrunken: \(hydration(entries).whole) von \(p.waterGoal.whole) ml"
    if sum("water", "caffeine") > 0 { drinks += ", Koffein \(sum("water", "caffeine").whole) mg" }
    if sum("water", "alcohol") > 0 { drinks += ", Alkohol \(sum("water", "alcohol").whole) g" }
    var lines: [String] = []
    lines.append("Profil: \(p.aiText), Trinkziel \(p.waterGoal.whole) ml")
    lines.append("Heute \(Day.today), \(Date().formatted(date: .omitted, time: .shortened)) Uhr:")
    lines.append("- Gegessen: \(kcal.whole) von \(p.kcal.whole) kcal, Eiweiß \(sum("nutrition", "protein").whole)/\(p.protein.whole) g, Kohlenhydrate \(sum("nutrition", "carbs").whole)/\(p.carbs.whole) g, Fett \(sum("nutrition", "fat").whole)/\(p.fat.whole) g")
    lines.append("- Mahlzeiten: " + (meals.isEmpty ? "noch nichts eingetragen" : meals.joined(separator: ", ")))
    lines.append(drinks)
    if let plan = p.plan {
        lines.append("- Trainingsprogramm: \(plan.name), heute " + (plan.isTrainingDay(Day.today) ? "Trainingstag" : "Ruhetag")
                     + (today.contains { $0.module == "training" } ? " (erledigt)" : ""))
    }
    let q = QuestProgress(all, p)
    lines.append("- Spiel: Level \(q.level), Serie \(q.streak) Tage, diese Woche \(q.weekQuests) Quests")
    let days = Day.last(7)
    lines.append("\nLetzte 7 Tage:")
    for m in allModules where p.modules.contains(m.id) && !m.fields.isEmpty && (healthUpload || m.id != "activity") {
        let stats = m.summary(entries.filter { $0.module == m.id }, days: days)
        if !stats.isEmpty { lines.append("\(String(localized: m.name)):\n" + stats.map(\.text).joined(separator: "\n")) }
    }
    lines.append("\nTraining (4 Wochen):\n" + trainingHistory(entries))
    return lines.joined(separator: "\n")
}

