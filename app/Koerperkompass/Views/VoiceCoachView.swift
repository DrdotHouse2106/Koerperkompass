import AVFoundation
import Speech
import SwiftData
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Sprach-Coach im Training: Du sprichst („10 Wiederholungen mit 60 Kilo, war schwer“), der Coach trägt den Satz ein,
/// antwortet gesprochen und zählt die Pause runter. Spracherkennung, Sprachausgabe und Antworten laufen auf dem iPhone
/// (Apple Intelligence) – kostenlos und offline. Ohne Apple Intelligence erkennt eine einfache Regel Wiederholungen und Gewicht.
@Observable @MainActor final class VoiceCoach {
    struct Line: Identifiable {
        let id = UUID()
        let fromCoach: Bool
        let text: String
    }

    var lines: [Line] = []
    var listening = false
    var thinking = false
    var heard = ""
    var rest = 0
    var error: String?

    private let synth = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restTask: Task<Void, Never>?
    private var session: Any?  // LanguageModelSession (ab iOS 26)
    private let plan: PlanDay
    private let profile: String

    init(plan: PlanDay, profile: String) {
        self.plan = plan
        self.profile = profile
    }

    func start() {
        let hello = String(localized: "Los geht’s! Heute: \(plan.title). Sag mir nach jedem Satz, wie viele Wiederholungen mit welchem Gewicht – und wie es sich angefühlt hat.")
        lines.append(Line(fromCoach: true, text: hello))
        speak(hello)
    }

    // MARK: Zuhören

    func toggleListening() async {
        if listening { finishListening(); return }
        guard await authorize() else {
            error = String(localized: "Bitte erlaube Mikrofon und Spracherkennung in den iOS-Einstellungen.")
            return
        }
        synth.stopSpeaking(at: .immediate)
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try audio.setActive(true)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
            request = req
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in req.append(buffer) }
            engine.prepare()
            try engine.start()
            heard = ""
            listening = true
            task = recognizer?.recognitionTask(with: req) { [weak self] result, _ in
                let text = result?.bestTranscription.formattedString
                Task { @MainActor in if let text { self?.heard = text } }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func finishListening() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        listening = false
        Task {
            try? await Task.sleep(for: .milliseconds(600))  // letzte Wörter abwarten
            task?.cancel()
            let text = heard.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { await handle(text) }
        }
    }

    private func authorize() async -> Bool {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    // MARK: Antworten

    private func handle(_ text: String) async {
        lines.append(Line(fromCoach: false, text: text))
        thinking = true
        defer { thinking = false }
        var turn = (reply: "", exercise: "", reps: 0, weight: 0.0, rest: 0, feedback: "")
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDevice.available {
            if let t = await ask(text) { turn = t }
        }
        #endif
        if turn.reply.isEmpty { turn = simple(text) }
        if turn.reps > 0 {
            let name = turn.exercise.isEmpty ? String(localized: "Übung") : turn.exercise
            var v: [String: Any] = ["exercise": name, "reps": Double(turn.reps)]
            if turn.weight > 0 { v["weight"] = turn.weight }
            let context = ModelContext(sharedContainer)
            context.insert(Entry(module: "exercises", values: v))
            try? context.save()
        }
        lines.append(Line(fromCoach: true, text: turn.reply))
        speak(turn.reply)
        if turn.rest > 0 { startRest(turn.rest) }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func ask(_ text: String) async -> (reply: String, exercise: String, reps: Int, weight: Double, rest: Int, feedback: String)? {
        let s = (session as? LanguageModelSession) ?? newSession()
        session = s
        do {
            let r = try await s.respond(to: text, generating: GenTurn.self)
            let c = r.content
            return (c.reply, c.exercise, c.reps, c.weight, c.restSeconds, c.feedback)
        } catch {
            session = nil  // z. B. Gesprächsverlauf zu lang – beim nächsten Mal frisch starten
            return nil
        }
    }

    @available(iOS 26.0, *)
    private func newSession() -> LanguageModelSession {
        LanguageModelSession(instructions: """
        Du bist ein motivierender Personal Trainer und begleitest ein Training per Sprache. Antworte immer kurz (1–2 Sätze, \
        wird vorgelesen), per Du, auf Deutsch. Wenn ein Satz gemeldet wird, erkenne Übung, Wiederholungen und Gewicht, lobe kurz \
        und empfiehl die Pause (meist 60–120 Sekunden, bei schweren Grundübungen bis 180). War es zu schwer, rate zu weniger \
        Gewicht; zu leicht, zu etwas mehr. Keine Diagnosen; bei Schmerzen: Übung abbrechen. Heutige Einheit: \(plan.title): \
        \(plan.exercises.joined(separator: "; ")). Profil: \(profile)
        """)
    }
    #endif

    /// Einfache Erkennung ohne Apple Intelligence: Zahlen für Wiederholungen und Gewicht
    private func simple(_ text: String) -> (reply: String, exercise: String, reps: Int, weight: Double, rest: Int, feedback: String) {
        let lower = text.lowercased()
        let numbers = lower.split(whereSeparator: { !$0.isNumber && $0 != "," && $0 != "." })
            .compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        let exercise = plan.exercises.map { $0.components(separatedBy: " – ").first ?? $0 }
            .first { lower.contains($0.lowercased().components(separatedBy: " ").first ?? "") } ?? ""
        guard let reps = numbers.first, reps > 0 else {
            return (String(localized: "Ich hab dich gehört! Sag mir einfach Wiederholungen und Gewicht, zum Beispiel: zehn Wiederholungen mit sechzig Kilo."), "", 0, 0, 0, "")
        }
        let weight = numbers.count > 1 ? numbers[1] : 0
        let hard = lower.contains("schwer") || lower.contains("hart")
        let reply = hard
            ? String(localized: "Stark gekämpft! Gönn dir zwei Minuten Pause – beim nächsten Satz ruhig etwas leichter.")
            : String(localized: "Sauber, eingetragen! 90 Sekunden Pause, dann weiter.")
        return (reply, exercise, Int(reps), weight, hard ? 120 : 90, hard ? "hard" : "ok")
    }

    // MARK: Sprechen und Pause

    func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier == "en" ? "en-US" : "de-DE")
        synth.speak(u)
    }

    func startRest(_ seconds: Int) {
        restTask?.cancel()
        rest = seconds
        restTask = Task {
            while rest > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                rest -= 1
                if rest == 10 { speak(String(localized: "Noch zehn Sekunden.")) }
            }
            if !Task.isCancelled { speak(String(localized: "Pause vorbei – auf zum nächsten Satz! 💪")) }
        }
    }

    func stop() {
        restTask?.cancel()
        synth.stopSpeaking(at: .immediate)
        if listening { engine.stop(); engine.inputNode.removeTap(onBus: 0); listening = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct VoiceCoachView: View {
    let plan: PlanDay
    @Environment(AppState.self) private var state
    @State private var coach: VoiceCoach?

    var body: some View {
        VStack(spacing: 14) {
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
                        Text("\(coach.rest / 60):\(String(format: "%02d", coach.rest % 60))").font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                        Button("Pause überspringen") { coach.startRest(0) }.font(.caption)
                    }
                }
                if coach.listening && !coach.heard.isEmpty {
                    Text(coach.heard).font(.callout).foregroundStyle(.secondary).padding(.horizontal)
                }
                if let error = coach.error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack(spacing: 10) {
                    ForEach([60, 90, 120], id: \.self) { s in
                        Button("\(s) s") { coach.startRest(s) }.buttonStyle(.bordered)
                    }
                }
                Button {
                    Task { await coach.toggleListening() }
                } label: {
                    Image(systemName: coach.listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 110, height: 110)
                        .background(coach.listening ? Color.red : Color.purple, in: Circle())
                        .shadow(color: (coach.listening ? Color.red : Color.purple).opacity(0.6), radius: 16)
                }
                .buttonStyle(.plain)
                Text(coach.listening ? LocalizedStringKey("Sprich jetzt – tippen zum Beenden") : "Tippen und sprechen")
                    .font(.caption).foregroundStyle(.secondary)
                Text(OnDevice.available ? LocalizedStringKey("🍏 Läuft mit Apple Intelligence auf deinem iPhone – kostenlos und offline.")
                     : "Ohne Apple Intelligence erkennt der Coach nur Wiederholungen und Gewicht.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Sprach-Coach")
        .onAppear {
            if coach == nil {
                let c = VoiceCoach(plan: plan, profile: state.profile.aiText)
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
