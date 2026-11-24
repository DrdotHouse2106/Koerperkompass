import SwiftData
import SwiftUI

/// Gesundheitscoach: Gespräch mit Claude über die eigenen Daten. Der Verlauf bleibt nur auf dem iPhone.
struct CoachView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
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
    @State private var speech = SpeechInput()
    @State private var speaker = Speaker()
    @AppStorage("coachSpeak") private var speakReplies = true
    @State private var talking = false
    @FocusState private var inputFocused: Bool
    @State private var talkTask: Task<Void, Never>?
    @State private var phase = ""

    struct Message: Codable, Hashable {
        let role: String  // "user" oder "assistant"
        let text: String
        var log: Proposal? = nil  // vom Coach vorgeschlagene Einträge (Essen, Getränke, Gewicht)
        var day: String? = Day.today  // Tag der Nachricht – ältere Nachrichten werden für den Coach als solche markiert
    }

    /// Einträge, die der Coach aus dem Gespräch vorschlägt – gespeichert erst nach Tipp auf „Eintragen“
    struct Proposal: Codable, Hashable {
        struct Item: Codable, Hashable {
            var meal, name, amount, time: String?
            var kcal, protein, carbs, fat, ml, caffeine, alcohol: Double?
            var food: ParsedFood {
                ParsedFood(meal: Meal(rawValue: meal ?? "") ?? .now, name: name ?? "", amount: amount ?? "", kcal: kcal ?? 0,
                           protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0, ml: ml ?? 0, caffeine: caffeine ?? 0, alcohol: alcohol ?? 0,
                           time: time ?? "")
            }
        }
        struct MoodItem: Codable, Hashable { var level: Int?; var feelings: [String]?; var areas: [String]? }
        struct SymptomItem: Codable, Hashable { var symptom: String?; var severity: Int? }
        var day: Int?
        var items: [Item]?
        var weight: Double?
        var mood: MoodItem?
        var symptoms: [SymptomItem]?
        var done: Bool?
        var isEmpty: Bool { (items ?? []).isEmpty && weight == nil && mood?.level == nil && (symptoms ?? []).isEmpty }
        var date: String { Day.string(Calendar.current.date(byAdding: .day, value: min(day ?? 0, 0), to: Date())!) }
    }

    private var messages: [Message] { (try? JSONDecoder().decode([Message].self, from: stored)) ?? [] }

    private let prompts: [LocalizedStringResource] = [
        "Lern mich kennen: Stell mir ein paar Fragen.",
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
                        CoachLogBanner()
                        intro
                        ForEach(Array(messages.enumerated()), id: \.offset) { i, m in
                            bubble(m).id(i)
                            if let p = m.log { proposal(p, i) }
                        }
                        if busy {
                            HStack { ProgressView(); Text("Dein Coach denkt nach …").foregroundStyle(.secondary) }
                                .frame(maxWidth: .infinity, alignment: .leading).id("busy")
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)  // beim Öffnen am Ende des Gesprächs
                .scrollDismissesKeyboard(.interactively)  // Verlauf nach unten ziehen schließt die Tastatur
                // Bei jeder neuen Nachricht (auch wenn der Verlauf voll ist und die Anzahl gleich bleibt), beim Nachdenken
                // und beim Öffnen der Tastatur ans Ende springen
                .onChange(of: stored) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: busy) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: inputFocused) { if inputFocused { withAnimation { proxy.scrollTo("end", anchor: .bottom) } } }
                .onAppear { proxy.scrollTo("end", anchor: .bottom); AppLog.add("Coach: Ansicht neu, \(messages.count) Nachrichten") }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { inputFocused = false }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Auswertung", systemImage: "chart.bar.xaxis") { showCompass = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Antworten vorlesen", isOn: $speakReplies)
                        Toggle("Tägliche Erinnerung", isOn: $reminder)
                        Picker("Uhrzeit", selection: $hour) {
                            ForEach(6..<22) { Text("\($0):00 Uhr").tag($0) }
                        }
                        Button("Gespräch löschen", systemImage: "trash", role: .destructive) { stored = Data() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showCompass) { CompassView() }
            .task { if speakReplies && state.ttsAvailable { _ = await Speaker.wake(state.api) } }  // Sprach-PC vorsorglich wecken
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
            Text("Tipp: Tippe auf die Welle für ein freies Gespräch – sprechen, kurz Pause machen, der Coach antwortet und hört dann wieder zu. Oder aufs Mikrofon für einzelne Nachrichten.")
                .font(.caption).foregroundStyle(.secondary)
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
            if talking {
                // Gesprächsmodus: Status und Beenden statt Eingabefeld
                HStack(spacing: 12) {
                    Image(systemName: "waveform").font(.title2).foregroundStyle(Theme.orange).symbolEffect(.variableColor.iterative, isActive: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase).font(.subheadline.bold())
                        if speech.listening && !speech.heard.isEmpty { Text(speech.heard).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        Text("Sag „Tschüss“ zum Beenden").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Beenden", systemImage: "xmark.circle.fill") { stopTalk() }.labelStyle(.iconOnly).font(.title).foregroundStyle(.red)
                }
                .padding(.horizontal)
            } else {
            HStack {
                Button { startTalk() } label: {
                    Image(systemName: "waveform.circle.fill").font(.title).foregroundStyle(Theme.orange)
                }
                .accessibilityLabel(Text("Gespräch starten"))
                Button {
                    Task {
                        if speech.listening {
                            let text = await speech.stop()
                            if !text.isEmpty { send(text) }
                        } else {
                            speaker.stop()
                            await speech.start()
                        }
                    }
                } label: {
                    Image(systemName: speech.listening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title).foregroundStyle(speech.listening ? .red : Theme.orange)
                }
                TextField(speech.listening ? LocalizedStringKey("Ich höre zu …") : "Frag deinen Coach …", text: $input, axis: .vertical)
                    .focused($inputFocused)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onChange(of: speech.heard) { if speech.listening && !talking { input = speech.heard } }
        .onDisappear { if talking { stopTalk() } }
        .disabled(!state.aiAvailable)
    }

    /// Karte unter der Antwort: vorgeschlagene Einträge mit „Eintragen“
    private func proposal(_ p: Proposal, _ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(p.day == -1 ? LocalizedStringKey("Für gestern eintragen?") : "Eintragen?", systemImage: "square.and.pencil").font(.caption.bold())
            ForEach(Array((p.items ?? []).enumerated()), id: \.offset) { _, x in
                Text("\((x.ml ?? 0) > 0 ? "🥤" : "🍽") \(x.name ?? "") \(x.amount.map { "(\($0))" } ?? "") · \((x.kcal ?? 0).whole) kcal").font(.caption)
            }
            if let w = p.weight { Text("⚖️ \(w.short) kg").font(.caption) }
            if let l = p.mood?.level { Text("\(Mood.levels[max(0, min(6, l - 1))].emoji) \(String(localized: Mood.levels[max(0, min(6, l - 1))].title))").font(.caption) }
            ForEach(Array((p.symptoms ?? []).enumerated()), id: \.offset) { _, s in
                Text("🤒 \(Symptoms.name(s.symptom ?? "")) · \(String(localized: Symptoms.severities[max(0, min(2, (s.severity ?? 1) - 1))]))").font(.caption)
            }
            if p.done == true {
                Label("Eingetragen", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
            } else {
                HStack {
                    Button("Eintragen") { apply(p, i) }.buttonStyle(.borderedProminent).tint(Theme.orange)
                    Button("Verwerfen", role: .cancel) { mark(i, nil) }.buttonStyle(.bordered)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func apply(_ p: Proposal, _ i: Int) {
        ParsedFood.save((p.items ?? []).map(\.food), day: p.date, context: context, state: state)
        if let kg = p.weight, kg > 20, kg < 400 {
            context.insert(Entry(module: "body", date: p.date, values: ["weight": kg]))
            if p.date == Day.today {
                if state.healthEnabled { Health.saveWeight(kg) }
                state.profile.weight = kg
            }
            state.changed(context)
        }
        if let l = p.mood?.level, (1...7).contains(l) {
            context.insert(Entry(module: "mood", date: p.date, values: [
                "mood": l, "valence": Mood.valence(l), "feelings": p.mood?.feelings ?? [], "areas": p.mood?.areas ?? [], "kind": "moment", "time": Day.now,
            ]))
            if state.healthEnabled && p.date == Day.today { Health.saveMood(level: l, daily: false, feelings: p.mood?.feelings ?? [], areas: p.mood?.areas ?? []) }
        }
        for s in p.symptoms ?? [] {
            guard let id = s.symptom, Symptoms.all.contains(where: { $0.id == id }) else { continue }
            let sev = max(1, min(3, s.severity ?? 1))
            context.insert(Entry(module: "symptoms", date: p.date, values: ["symptom": id, "name": Symptoms.name(id), "severity": sev, "time": Day.now]))
            if state.healthEnabled && p.date == Day.today { Health.saveSymptom(id, severity: sev) }
        }
        state.changed(context)
        var done = p
        done.done = true
        mark(i, done)
    }

    /// Vorschlag einer Nachricht ändern (nil = verwerfen)
    private func mark(_ i: Int, _ p: Proposal?) {
        var list = messages
        guard list.indices.contains(i) else { return }
        list[i].log = p
        save(list)
    }

    private func save(_ list: [Message]) { stored = (try? JSONEncoder().encode(Array(list.suffix(60)))) ?? Data() }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        guard state.aiConsent else { pending = text; askConsent = true; return }
        // Beim Absenden das Mikrofon beenden – sonst nimmt es die vorgelesene Antwort mit auf
        if speech.listening { Task { _ = await speech.stop() } }
        inputFocused = false
        Task {
            if let spoken = await ask(text), speakReplies {
                speaker.api = state.ttsAvailable ? state.api : nil
                speaker.speak(spoken)
            }
        }
    }

    /// Nachricht an den Coach; liefert den Text zum Vorlesen (nil bei Fehler)
    private func ask(_ text: String) async -> String? {
        input = ""
        error = nil
        let list = messages + [Message(role: "user", text: text)]
        save(list)
        busy = true
        let started = Date()
        defer { busy = false }
            do {
                let r = try await state.api.object("POST", "/api/ai/coach", json: [
                    // Nachrichten früherer Tage mit Datum, damit der Coach Gestern nicht für Heute hält
                    "messages": list.suffix(30).map { m in
                        ["role": m.role, "content": (m.day ?? "") == Day.today ? m.text : "[\(m.day.map { Day.date($0).formatted(date: .abbreviated, time: .omitted) } ?? String(localized: "früher"))] " + m.text]
                    },
                    "context": coachContext(entries, state.profile, healthUpload: state.healthUpload,
                                            mention: list.filter { $0.role == "user" }.suffix(3).map(\.text).joined(separator: " ")),
                    "lang": Locale.current.language.languageCode?.identifier ?? "de",
                    "voice": talking,  // Gesprächsmodus: kurz und gesprochen antworten
                ])
                var reply = r["text"] as? String ?? ""
                // Was der Coach über dich gelernt hat, ins Profil übernehmen (sichtbar unter Einstellungen → Über mich)
                var p = state.profile, notes: [String] = []
                if let learn = r["learn"] as? [String], !learn.isEmpty { p.learn(learn); notes += learn }
                if let routine = r["routine"] as? String, !routine.isEmpty {
                    p.routine = routine
                    notes.append(String(localized: "Alltag aktualisiert"))
                }
                if let eq = r["equipment"] as? [String] {
                    p.equipment = eq.filter { id in Profile.equipmentOptions.contains { $0.id == id } }
                    notes.append(String(localized: "Geräte: \(p.equipmentText)"))
                }
                if p != state.profile { state.profile = p }
                let spoken = reply
                if !notes.isEmpty { reply += "\n\n_📝 Gemerkt: " + notes.joined(separator: "; ") + "_" }
                CoachLog.add(kind: "gesundheit", heard: text, reply: reply, source: "claude", ms: Int(Date().timeIntervalSince(started) * 1000))
                // Vorgeschlagene Einträge aus dem Gespräch (Essen, Getränke, Gewicht)
                let log = (r["log"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                    .flatMap { try? JSONDecoder().decode(Proposal.self, from: $0) }
                    .flatMap { $0.isEmpty ? nil : $0 }
                save(list + [Message(role: "assistant", text: reply, log: log)])
                return spoken
            } catch {
                self.error = error.localizedDescription
                return nil
            }
    }

    // MARK: Gesprächsmodus – freihändig: zuhören, nach einer Pause absenden, Antwort vorlesen, wieder zuhören

    private func startTalk() {
        guard state.aiConsent else { askConsent = true; return }
        speaker.stop()
        inputFocused = false
        talking = true
        talkTask = Task {
            speaker.api = state.ttsAvailable ? state.api : nil
            var next: String?  // Antwort auf die Eintragen-Frage, die eigentlich etwas anderes war
            while talking && !Task.isCancelled {
                let text: String
                if let n = next {
                    text = n
                    next = nil
                } else {
                    phase = String(localized: "Ich höre zu …")
                    await speech.start()
                    text = await speech.waitForPause()
                }
                guard talking else { break }
                if text.isEmpty { break }  // längere Zeit nichts gesagt → Gespräch beenden
                if isGoodbye(text) {
                    speaker.speak(String(localized: "Alles klar, bis später!"))
                    break
                }
                phase = String(localized: "Dein Coach denkt nach …")
                guard let reply = await ask(text) else { break }
                phase = String(localized: "Dein Coach spricht …")
                speaker.speak(reply)
                await speaker.waitUntilDone()
                // Vorgeschlagene Einträge per Sprache bestätigen
                if let i = messages.indices.last, let p = messages[i].log, p.done != true, talking {
                    phase = String(localized: "Eintragen?")
                    speaker.speak(confirmQuestion(p))
                    await speaker.waitUntilDone()
                    phase = String(localized: "Ich höre zu …")
                    await speech.start()
                    let answer = await speech.waitForPause(timeout: 15)
                    guard talking else { break }
                    switch yesNo(answer) {
                    case true?:
                        apply(p, i)
                        speaker.speak(String(localized: "Ist eingetragen."))
                        await speaker.waitUntilDone()
                    case false?:
                        mark(i, nil)
                        speaker.speak(String(localized: "Okay, trage ich nicht ein."))
                        await speaker.waitUntilDone()
                    case nil:
                        if !answer.isEmpty { next = answer }  // keine klare Antwort → als normale Nachricht weiter
                    }
                }
            }
            talking = false
        }
    }

    private func stopTalk() {
        talking = false
        talkTask?.cancel()
        speaker.stop()
        Task { _ = await speech.stop() }
    }

    /// Frage zum Vorlesen: „Soll ich das eintragen: Currywurst, Pommes und Cola, zusammen 1020 Kilokalorien?“
    private func confirmQuestion(_ p: Proposal) -> String {
        let items = p.items ?? []
        var parts: [String] = []
        if !items.isEmpty {
            let names = items.compactMap(\.name).formatted(.list(type: .and))
            parts.append(String(localized: "\(names), zusammen \(items.compactMap(\.kcal).reduce(0, +).whole) Kilokalorien"))
        }
        if let w = p.weight { parts.append(String(localized: "dein Gewicht von \(w.short) Kilo")) }
        if let l = p.mood?.level { parts.append(String(localized: "deine Stimmung „\(String(localized: Mood.levels[max(0, min(6, l - 1))].title))“")) }
        let symptoms = (p.symptoms ?? []).compactMap { $0.symptom.map(Symptoms.name) }
        if !symptoms.isEmpty { parts.append(symptoms.formatted(.list(type: .and))) }
        let what = parts.joined(separator: String(localized: " und "))
        return p.day == -1 ? String(localized: "Soll ich das für gestern eintragen: \(what)?") : String(localized: "Soll ich das eintragen: \(what)?")
    }

    /// Ja/Nein aus der gesprochenen Antwort (nil = unklar)
    private func yesNo(_ text: String) -> Bool? {
        let w = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        if !w.isDisjoint(with: ["nein", "nee", "ne", "nö", "nicht", "lass", "falsch", "no", "nope"]) { return false }
        if !w.isDisjoint(with: ["ja", "jo", "jep", "jawohl", "gerne", "gern", "klar", "okay", "ok", "mach", "bitte", "genau", "passt", "trag", "richtig", "yes", "yeah"]) { return true }
        return nil
    }

    /// „Tschüss“, „Stopp“, „Ende“ … beendet das Gespräch
    private func isGoodbye(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        return words.contains { ["tschüss", "tschüs", "stopp", "bye"].contains($0) } || words.last == "ende" || words == ["ende"]
    }
}

/// Zusammenfassung der eigenen Daten für den Coach. Health-Daten nur mit Zustimmung zum Hochladen.
/// mention: zuletzt Gesagtes – dort erwähnte Rezepte bekommen ihre Zutaten mit
func coachContext(_ all: [Entry], _ p: Profile, healthUpload: Bool, mention: String = "") -> String {
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
    // Getränke mit Uhrzeit (soweit bekannt) – zeigt, wann getrunken wurde, z. B. Koffein spät am Tag
    let timed = today.filter { $0.module == "water" && $0.text("time") != nil }.sorted { ($0.text("time") ?? "") < ($1.text("time") ?? "") }
    if !timed.isEmpty {
        drinks += "\n- Getränke heute: " + timed.map { "\($0.text("time") ?? "") \($0.text("name") ?? "") \(($0.num("ml") ?? 0).whole) ml" }.joined(separator: ", ")
    }
    var lines: [String] = []
    lines.append("Profil: \(p.aiText), Trinkziel \(p.waterGoal.whole) ml")
    lines.append("Heute \(Date().formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE")))), \(Day.today), \(Date().formatted(date: .omitted, time: .shortened)) Uhr:")
    lines.append("- Gegessen: \(kcal.whole) von \(p.kcal.whole) kcal, Eiweiß \(sum("nutrition", "protein").whole)/\(p.protein.whole) g, Kohlenhydrate \(sum("nutrition", "carbs").whole)/\(p.carbs.whole) g, Fett \(sum("nutrition", "fat").whole)/\(p.fat.whole) g")
    lines.append("- Mahlzeiten: " + (meals.isEmpty ? "noch nichts eingetragen" : meals.joined(separator: ", ")))
    lines.append(drinks)
    if let sym = Symptoms.summary(entries) { lines.append("- Beschwerden (letzte 7 Tage): " + sym) }
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
    let said = mention.lowercased()
    let recipes = entries.filter { $0.module == "recipes" }.prefix(40).map { e in
        let hit = (e.text("title") ?? "").lowercased().split { !$0.isLetter }.contains { $0.count >= 4 && said.contains($0) }
        return e.recipeLine + (hit && !e.ingredients.isEmpty ? " – Zutaten: " + e.ingredients.map { [$0.amount, $0.name].filter { !$0.isEmpty }.joined(separator: " ") }.joined(separator: ", ") : "")
    }
    if !recipes.isEmpty { lines.append("\nEigene Rezeptsammlung (gern passend vorschlagen):\n- " + recipes.joined(separator: "\n- ")) }
    return lines.joined(separator: "\n")
}

