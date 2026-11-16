import AVFoundation
import SwiftData
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Stil des Trainings-Coaches: bestimmt Tonfall, Sprechweise und Standardsprüche
enum Persona: String, CaseIterable, Identifiable {
    case drill, sarge, buddy, cheer, calm
    var id: String { rawValue }

    /// Derbe Sprache – vor der ersten Auswahl nachfragen
    var harsh: Bool { self == .sarge }

    var title: LocalizedStringResource {
        switch self {
        case .drill: "Drill Sergeant"
        case .sarge: "Drill Sergeant – Hardcore"
        case .buddy: "Kumpel"
        case .cheer: "Cheerleader"
        case .calm: "Ruhig & sachlich"
        }
    }
    var emoji: String { ["🎖", "💀", "🤜", "📣", "🧘"][Self.allCases.firstIndex(of: self)!] }

    /// Anweisung für das Sprachmodell
    var style: String {
        switch self {
        case .drill: "Du bist ein harter, lauter Drill Sergeant: kurze Befehle, fordernd, keine Ausreden, treibst an („Noch zwei! Aufgeben ist keine Option!“), aber nie beleidigend und immer sicherheitsbewusst."
        case .sarge: "Du bist ein brutal harter, brüllender Ausbilder aus dem Militär-Drill: derb, laut, sarkastisch, beleidigend und mit Schimpfwörtern. Du verspottest Faulheit, Jammern, Schwäche und Ausreden (z. B. „Weichei“, „Schlafmütze“, „Jammerlappen“), schreist kurze Befehle und duldest keine Pause ohne Erlaubnis. Grenzen: niemals Beleidigungen über Körper, Gewicht, Aussehen, Herkunft, Geschlecht oder Sexualität, keine Drohungen; bei Schmerzen sofort ernst werden und abbrechen lassen."
        case .buddy: "Du bist ein lockerer, freundlicher Trainingskumpel: entspannt, humorvoll, ermutigend, wie ein guter Freund im Gym."
        case .cheer: "Du bist ein begeisterter Cheerleader: überschwänglich, feierst jede Wiederholung, viele Ausrufezeichen und Energie."
        case .calm: "Du bist ein ruhiger, sachlicher Coach: knapp, technisch präzise, Fokus auf saubere Ausführung, Atmung und Tempo."
        }
    }

    /// Sprechtempo und Tonhöhe
    var rate: Float { [0.56, 0.6, 0.5, 0.55, 0.45][Self.allCases.firstIndex(of: self)!] }
    var pitch: Float { [0.8, 0.7, 1.0, 1.25, 0.95][Self.allCases.firstIndex(of: self)!] }

    /// Anfeuern ohne Apple Intelligence
    var cheers: [LocalizedStringResource] {
        switch self {
        case .drill: ["Weiter! Schmerz ist nur Schwäche, die den Körper verlässt!", "Noch zwei! Ich will Schweiß sehen!", "Aufgeben ist keine Option! Drück!", "Du bist kein Zuschauer – du bist Soldat! Weiter!"]
        case .sarge: [
            "Was ist das hier, eine Kaffeefahrt?! Beweg dich, du Schlafmütze!",
            "Ich hab Gartenzwerge gesehen, die mehr Einsatz zeigen! NOCH ZWEI!",
            "Hast du da gerade geseufzt?! Seufzen ist für Zivilisten! WEITER!",
            "Du nennst das eine Wiederholung? Meine Kaffeetasse arbeitet härter als du, Weichei!",
            "Aufhören? Aufhören darfst du, wenn ICH es sage! DRÜCK!",
            "Jammerlappen werden hier nicht gefüttert! Noch eine, aber sauber!",
            "Hör auf zu zittern und fang an zu arbeiten! LOS, LOS, LOS!",
            "Du schwitzt ja kaum! Ist das ein Training oder ein Wellness-Wochenende?!",
            "Meine Oma hebt schwerere Einkaufstüten! Zeig mir, dass du mehr kannst!",
            "Müde?! Müde ist für Leute ohne Ziel! Du hast eins – also WEITER!",
        ]
        case .buddy: ["Komm, du packst das! Noch ein paar!", "Läuft bei dir! Dranbleiben!", "Stark, Alter! Noch einer geht immer!"]
        case .cheer: ["Wow! Du bist der Wahnsinn! Weiter so!", "Jaaa! Noch eine! Ich glaub an dich!", "Unglaublich! Du rockst das!"]
        case .calm: ["Ruhig atmen, saubere Bewegung.", "Kontrolliert weiter, Spannung halten.", "Gleichmäßiges Tempo, du machst das gut."]
        }
    }

    var restOver: LocalizedStringResource {
        switch self {
        case .drill: "Pause vorbei! Hoch mit dir, nächster Satz – sofort!"
        case .sarge: "Pause vorbei, Schlafmütze! Hoch mit dir, aber zack zack! Ich hab nicht den ganzen Tag Zeit!"
        case .buddy: "So, Pause rum – auf geht’s, nächster Satz!"
        case .cheer: "Pause vorbei! Zeit zu glänzen – nächster Satz!"
        case .calm: "Die Pause ist vorbei. Nächster Satz, wenn du bereit bist."
        }
    }
}

/// Trainings-Coach per Sprache: sprechen („10 Wiederholungen mit 60 Kilo, war schwer“), der Satz wird eingetragen,
/// der Coach antwortet im gewählten Stil und zählt die Pause runter. Läuft mit Apple Intelligence auf dem iPhone –
/// kostenlos und offline. Ohne Apple Intelligence erkennt eine einfache Regel Wiederholungen und Gewicht.
@Observable @MainActor final class VoiceCoach {
    struct Line: Identifiable {
        let id = UUID()
        let fromCoach: Bool
        let text: String
    }

    var lines: [Line] = []
    var thinking = false
    var voiceLoading = false  // Sprach-PC wird geweckt
    var rest = 0
    var persona: Persona { didSet { session = nil; speaker.persona = persona.rawValue } }
    let speech = SpeechInput()

    private let speaker = Speaker()
    private var restTask: Task<Void, Never>?
    private var session: Any?  // LanguageModelSession (ab iOS 26)
    private let plan: PlanDay
    private let profile: String
    private let api: API?  // Claude (kleines Modell) als Ersatz, wenn Apple Intelligence fehlt

    init(plan: PlanDay, profile: String, persona: Persona, api: API?, voiceServer: API?) {
        self.plan = plan
        self.profile = profile
        self.persona = persona
        self.api = api
        speaker.api = voiceServer
        speaker.persona = persona.rawValue
    }

    /// Sprach-PC wecken und warten, bis die beste Stimme bereit ist (bis dahin vorgerenderte Sätze bzw. Piper)
    func wakeVoice() {
        guard let api = speaker.api else { return }
        Task {
            for _ in 0..<24 {  // höchstens ca. 3 Minuten
                if await Speaker.wake(api) { break }
                voiceLoading = true
                try? await Task.sleep(for: .seconds(8))
            }
            voiceLoading = false
        }
    }

    func start() {
        wakeVoice()
        say(String(localized: "Los geht’s! Heute: \(plan.title). Sag mir nach jedem Satz, wie viele Wiederholungen mit welchem Gewicht – und wie es sich angefühlt hat."))
    }

    private func say(_ text: String) {
        lines.append(Line(fromCoach: true, text: text))
        speaker.speak(text, rate: persona.rate, pitch: persona.pitch)
    }

    func toggleListening() async {
        if speech.listening {
            let text = await speech.stop()
            if !text.isEmpty { await handle(text) }
        } else {
            speaker.stop()
            await speech.start()
        }
    }

    /// Mitten im Satz anfeuern
    func cheer() async {
        let started = Date()
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDevice.available, let s = activeSession(),
           let r = try? await s.respond(to: String(localized: "Ich bin mitten im Satz – feuer mich mit einem kurzen Satz an!")) {
            say(r.content)
            CoachLog.add(kind: "anfeuern", persona: persona.rawValue, heard: "🔥", reply: r.content, source: "apple", ms: Int(Date().timeIntervalSince(started) * 1000))
            return
        }
        #endif
        let line = String(localized: persona.cheers.randomElement()!)
        say(line)
        CoachLog.add(kind: "anfeuern", persona: persona.rawValue, heard: "🔥", reply: line, source: "regel", ms: 0)
    }

    private func handle(_ text: String) async {
        lines.append(Line(fromCoach: false, text: text))
        thinking = true
        defer { thinking = false }
        let started = Date()
        var source = "regel"
        var turn = (reply: "", exercise: "", reps: 0, weight: 0.0, rest: 0)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDevice.available, let s = activeSession() {
            if let r = try? await s.respond(to: text, generating: GenTurn.self) {
                let c = r.content
                turn = (c.reply, c.exercise, c.reps, c.weight, c.restSeconds)
                source = "apple"
            } else {
                session = nil  // z. B. Gespräch zu lang – beim nächsten Mal frisch starten
            }
        }
        #endif
        if turn.reply.isEmpty, let api, let r = try? await api.object("POST", "/api/ai/voice", json: [
            "style": persona.style, "plan": "\(plan.title): " + plan.exercises.joined(separator: "; "), "profile": profile,
            "history": lines.suffix(6).map { ($0.fromCoach ? "Coach: " : "Ich: ") + $0.text }.joined(separator: "\n"), "text": text,
        ]), let reply = r["reply"] as? String, !reply.isEmpty {
            turn = (reply, r["exercise"] as? String ?? "", (r["reps"] as? NSNumber)?.intValue ?? 0,
                    (r["weight"] as? NSNumber)?.doubleValue ?? 0, (r["restSeconds"] as? NSNumber)?.intValue ?? 0)
            source = "haiku"
        }
        if turn.reply.isEmpty { turn = simple(text) }
        if turn.reps > 0 {
            var v: [String: Any] = ["exercise": turn.exercise.isEmpty ? String(localized: "Übung") : turn.exercise, "reps": Double(turn.reps)]
            if turn.weight > 0 { v["weight"] = turn.weight }
            let context = ModelContext(sharedContainer)
            context.insert(Entry(module: "exercises", values: v))
            try? context.save()
        }
        say(turn.reply)
        if turn.rest > 0 { startRest(turn.rest) }
        CoachLog.add(kind: "training", persona: persona.rawValue, heard: text, reply: turn.reply, source: source,
                     ms: Int(Date().timeIntervalSince(started) * 1000),
                     extra: ["exercise": turn.exercise, "reps": turn.reps, "weight": turn.weight, "rest": turn.rest])
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func activeSession() -> LanguageModelSession? {
        if let s = session as? LanguageModelSession { return s }
        let s = LanguageModelSession(instructions: """
        \(persona.style) Du begleitest ein Training per Sprache. Antworte immer sehr kurz (1–2 Sätze, wird vorgelesen), \
        per Du, auf Deutsch, ohne Emojis. Wenn ein Satz gemeldet wird, erkenne Übung, Wiederholungen und Gewicht und \
        empfiehl die Pause (meist 60–120 Sekunden, bei schweren Grundübungen bis 180). War es zu schwer, rate zu weniger \
        Gewicht; zu leicht, zu etwas mehr. Bei Schmerzen: Übung sofort abbrechen. Heutige Einheit: \(plan.title): \
        \(plan.exercises.joined(separator: "; ")). Profil: \(profile)
        """)
        session = s
        return s
    }
    #endif

    /// Einfache Erkennung ohne Apple Intelligence: Zahlen für Wiederholungen und Gewicht
    private func simple(_ text: String) -> (reply: String, exercise: String, reps: Int, weight: Double, rest: Int) {
        let lower = text.lowercased()
        let numbers = lower.split(whereSeparator: { !$0.isNumber && $0 != "," && $0 != "." })
            .compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        let exercise = plan.exercises.map { $0.components(separatedBy: " – ").first ?? $0 }
            .first { lower.contains($0.lowercased().components(separatedBy: " ").first ?? "") } ?? ""
        guard let reps = numbers.first, reps > 0 else {
            return (String(localized: "Ich hab dich gehört! Sag mir einfach Wiederholungen und Gewicht, zum Beispiel: zehn Wiederholungen mit sechzig Kilo."), "", 0, 0, 0)
        }
        let hard = lower.contains("schwer") || lower.contains("hart")
        let reply = String(localized: persona.cheers.randomElement()!) + " "
            + (hard ? String(localized: "Zwei Minuten Pause, nächster Satz etwas leichter.") : String(localized: "Eingetragen! 90 Sekunden Pause."))
        return (reply, exercise, Int(reps), numbers.count > 1 ? numbers[1] : 0, hard ? 120 : 90)
    }

    func startRest(_ seconds: Int) {
        restTask?.cancel()
        rest = seconds
        guard seconds > 0 else { return }
        restTask = Task {
            while rest > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                rest -= 1
                if rest == 10 { speaker.speak(String(localized: "Noch zehn Sekunden."), rate: persona.rate, pitch: persona.pitch) }
            }
            if !Task.isCancelled { say(String(localized: persona.restOver)) }
        }
    }

    func stop() {
        restTask?.cancel()
        speaker.stop()
        Task { _ = await speech.stop() }
        Speaker.deactivate()
    }
}

struct VoiceCoachView: View {
    let plan: PlanDay
    @Environment(AppState.self) private var state
    @AppStorage("voicePersona") private var personaID = Persona.buddy.rawValue
    @AppStorage("harshConfirmed") private var harshConfirmed = false
    @State private var coach: VoiceCoach?
    @State private var askHarsh: Persona?

    var body: some View {
        VStack(spacing: 12) {
            CoachLogBanner()
            if coach?.voiceLoading == true {
                Label("Kleinen Moment, die Stimme wird geladen …", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
            }
            // Stil wählen
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Persona.allCases) { p in
                        Button {
                            if p.harsh && !harshConfirmed { askHarsh = p; return }
                            personaID = p.rawValue
                            coach?.persona = p
                        } label: {
                            Text("\(p.emoji) \(String(localized: p.title))").font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(personaID == p.rawValue ? Color.purple : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            if let coach {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(coach.lines) { l in
                                Text(l.text)
                                    .padding(10)
                                    .background(l.fromCoach ? Color.white.opacity(0.08) : Color.purple.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                                    .frame(maxWidth: .infinity, alignment: l.fromCoach ? .leading : .trailing)
                                    .id(l.id)
                            }
                            if coach.thinking { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: coach.lines.count) { if let last = coach.lines.last { withAnimation { proxy.scrollTo(last.id) } } }
                }
                if coach.rest > 0 {
                    VStack {
                        Text("Pause").font(.caption.bold()).foregroundStyle(.secondary)
                        Text("\(coach.rest / 60):\(String(format: "%02d", coach.rest % 60))")
                            .font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                        Button("Pause überspringen") { coach.startRest(0) }.font(.caption)
                    }
                }
                if coach.speech.listening && !coach.speech.heard.isEmpty {
                    Text(coach.speech.heard).font(.callout).foregroundStyle(.secondary).padding(.horizontal)
                }
                if let error = coach.speech.error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack(spacing: 10) {
                    ForEach([60, 90, 120], id: \.self) { s in
                        Button("\(s) s") { coach.startRest(s) }.buttonStyle(.bordered)
                    }
                    Button("🔥 Feuer mich an!") { Task { await coach.cheer() } }.buttonStyle(.borderedProminent).tint(.orange)
                }
                Button {
                    Task { await coach.toggleListening() }
                } label: {
                    Image(systemName: coach.speech.listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 110, height: 110)
                        .background(coach.speech.listening ? Color.red : Color.purple, in: Circle())
                        .shadow(color: (coach.speech.listening ? Color.red : Color.purple).opacity(0.6), radius: 16)
                }
                .buttonStyle(.plain)
                Text(coach.speech.listening ? LocalizedStringKey("Sprich jetzt – tippen zum Beenden") : "Tippen und sprechen")
                    .font(.caption).foregroundStyle(.secondary)
                Text(OnDevice.available ? LocalizedStringKey("🍏 Läuft mit Apple Intelligence auf deinem iPhone – kostenlos und offline.")
                     : state.aiAvailable && state.aiConsent ? "☁️ Läuft mit Claude Haiku über deinen Server – Bruchteile eines Cents pro Antwort."
                     : "Ohne Apple Intelligence und Claude erkennt der Coach nur Wiederholungen und Gewicht.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Trainings-Coach")
        .alert("Derbe Sprache?", isPresented: Binding(get: { askHarsh != nil }, set: { if !$0 { askHarsh = nil } })) {
            Button("Ja, ich kann das ab") {
                harshConfirmed = true
                if let p = askHarsh { personaID = p.rawValue; coach?.persona = p }
                askHarsh = nil
            }
            Button("Lieber nicht", role: .cancel) { askHarsh = nil }
        } message: {
            Text("Dieser Coach brüllt, schimpft und beleidigt dich – wegen Faulheit und Jammern, nie wegen deines Körpers. Nur wählen, wenn dich das wirklich motiviert. Du kannst jederzeit wechseln.")
        }
        .onAppear {
            if coach == nil {
                let c = VoiceCoach(plan: plan, profile: state.profile.aiText, persona: Persona(rawValue: personaID) ?? .buddy,
                                   api: !OnDevice.available && state.aiAvailable && state.aiConsent ? state.api : nil,
                                   voiceServer: state.ttsAvailable && !state.demo ? state.api : nil)
                coach = c
                c.start()
            }
            UIApplication.shared.isIdleTimerDisabled = true  // Bildschirm bleibt an
        }
        .onDisappear {
            coach?.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
