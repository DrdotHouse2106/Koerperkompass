import AVFoundation
import Speech

/// Spracheingabe (nach Möglichkeit auf dem iPhone): start() hört zu, stop() liefert den erkannten Text.
@Observable @MainActor final class SpeechInput {
    var listening = false
    var heard = ""
    var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current.language.languageCode?.identifier == "en"
                                                ? Locale(identifier: "en-US") : Locale(identifier: "de-DE"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !listening else { return }
        guard await authorize() else {
            error = String(localized: "Bitte erlaube Mikrofon und Spracherkennung in den iOS-Einstellungen.")
            return
        }
        do {
            try Speaker.activateSession()
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
            request = req
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in req.append(buffer) }
            engine.prepare()
            try engine.start()
            heard = ""
            error = nil
            listening = true
            task = recognizer?.recognitionTask(with: req) { [weak self] result, _ in
                let text = result?.bestTranscription.formattedString
                Task { @MainActor in if let text { self?.heard = text } }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Beendet das Zuhören und gibt den erkannten Text zurück (leer, wenn nichts verstanden wurde)
    func stop() async -> String {
        guard listening else { return "" }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        listening = false
        try? await Task.sleep(for: .milliseconds(600))  // letzte Wörter abwarten
        task?.cancel()
        return heard.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func authorize() async -> Bool {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }
}

/// Sprachausgabe mit einstellbarem Tempo und Tonhöhe (je nach Coach-Stil)
@MainActor final class Speaker {
    private let synth = AVSpeechSynthesizer()

    static func activateSession() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try audio.setActive(true)
    }

    func speak(_ text: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate, pitch: Float = 1) {
        try? Self.activateSession()
        // Markdown-Zeichen nicht mitsprechen
        let clean = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "- ", with: "").replacingOccurrences(of: "*", with: "")
        let u = AVSpeechUtterance(string: clean)
        u.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier == "en" ? "en-US" : "de-DE")
        u.rate = rate
        u.pitchMultiplier = pitch
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
