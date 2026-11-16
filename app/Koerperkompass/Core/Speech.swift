import AVFoundation
import CryptoKit
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
/// Stimme vom eigenen Server (Kartoffelbox/Piper, falls eingerichtet), auf dem iPhone zwischengespeichert;
/// sonst – oder ohne Verbindung – die iPhone-Stimme.
@MainActor final class Speaker {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    /// Server für die Sprachausgabe (nil = nur iPhone-Stimme)
    var api: API?
    /// Coach-Stil: bestimmt die Stimme auf dem Server
    var persona = "coach"

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
        let useServer = api != nil && (UserDefaults.standard.object(forKey: "serverVoice") as? Bool ?? true)
        guard useServer, let api else { speakLocal(clean, rate: rate, pitch: pitch); return }
        let persona = persona
        Task {
            if let data = await Self.audio(clean, persona: persona, api: api), let p = try? AVAudioPlayer(data: data) {
                synth.stopSpeaking(at: .immediate)
                player?.stop()
                player = p
                p.play()
            } else {
                speakLocal(clean, rate: rate, pitch: pitch)
            }
        }
    }

    private func speakLocal(_ text: String, rate: Float, pitch: Float) {
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice()
        u.rate = rate
        u.pitchMultiplier = pitch
        synth.speak(u)
    }

    /// Ton vom Server, auf dem iPhone zwischengespeichert (gleicher Schlüssel wie auf dem Server)
    private static func audio(_ text: String, persona: String, api: API) async -> Data? {
        let key = SHA256.hash(data: Data("\(persona)|\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
        let dir = URL.cachesDirectory.appendingPathComponent("tts", isDirectory: true)
        let file = dir.appendingPathComponent(key + ".wav")
        if let data = try? Data(contentsOf: file) { return data }
        guard let result = try? await api.response("POST", "/api/tts", json: ["text": text, "persona": persona]) else { return nil }
        let (data, resp) = result
        guard data.count > 44, data.prefix(4) == Data("RIFF".utf8) else { return nil }
        // Nur die endgültige Fassung speichern – Rückfall-Töne (z. B. Piper, solange Kartoffelbox geweckt wird) nicht
        if resp?.value(forHTTPHeaderField: "X-KK-TTS-Final") == "1" {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: file)
        }
        return data
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        player?.stop()
    }

    /// Sprach-PC wecken (Wake-on-LAN über den eigenen Server); true, sobald die beste Stimme bereit ist
    static func wake(_ api: API) async -> Bool {
        guard let r = try? await api.object("POST", "/api/tts/wake") else { return true }
        return r["ready"] as? Bool ?? true
    }

    /// Sprache der App (de/en)
    static var languagePrefix: String { Locale.current.language.languageCode?.identifier == "en" ? "en" : "de" }

    /// Installierte Stimmen der App-Sprache, beste zuerst (Premium > Erweitert > Standard)
    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languagePrefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    /// Gewählte Stimme (Einstellungen) oder automatisch die beste installierte
    static func voice() -> AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: "voiceID"), let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return voices.first ?? AVSpeechSynthesisVoice(language: languagePrefix == "en" ? "en-US" : "de-DE")
    }

    static func qualityName(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: String(localized: "Premium")
        case .enhanced: String(localized: "Erweitert")
        default: String(localized: "Standard")
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
