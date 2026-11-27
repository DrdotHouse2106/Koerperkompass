import AVFoundation
import SwiftData
import SwiftUI

/// Dauer-Coach: ein langer, ununterbrochener Monolog im Dark-Stil (10–30 Minuten) über einem dunklen Klangteppich.
/// Claude schreibt ihn Abschnitt für Abschnitt (der nächste entsteht, während der aktuelle läuft), persönlich zu deinen Daten.
/// Läuft mit gesperrtem Bildschirm weiter (Hintergrund-Audio).
struct MonologView: View {
    @Environment(AppState.self) private var state
    @Query private var entries: [Entry]
    @AppStorage("darkLang") private var lang = DarkStory.language
    @AppStorage("monologMinutes") private var minutes = 20
    @AppStorage("monologTheme") private var theme = "Disziplin"
    @State private var speaker = Speaker()
    @State private var drone = Drone()
    @State private var task: Task<Void, Never>?
    @State private var line = ""
    @State private var block = 0
    @State private var error: String?

    static let themes = ["Disziplin", "Training", "Durchhalten", "Neustart", "Selbstvertrauen", "Erholung"]
    private var blocks: Int { max(1, minutes * 10 / 25) }  // ein Abschnitt ≈ 2,5 Minuten
    private var running: Bool { task != nil }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(white: 0.1), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 24) {
                if running {
                    Text("Abschnitt \(block) von \(blocks)").font(.caption).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(line).font(.system(size: 28, weight: .heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
                        .padding(.horizontal, 24).animation(.easeInOut(duration: 0.3), value: line)
                    Spacer()
                } else {
                    Form {
                        Picker("Dauer", selection: $minutes) { ForEach([10, 20, 30], id: \.self) { Text("\($0) Minuten").tag($0) } }
                        Picker("Thema", selection: $theme) { ForEach(Self.themes, id: \.self) { Text(LocalizedStringKey($0)).tag($0) } }
                        Picker("Sprache", selection: $lang) { Text("Deutsch").tag("de"); Text("Englisch").tag("en"); Text("Gemischt").tag("mix") }
                        Section {
                            Text("Eine Stimme spricht ohne Pause zu dir – eigene Texte im Dark-Stil, persönlich zu deinem Weg. Läuft auch bei gesperrtem Bildschirm, z. B. beim Laufen oder im Gym.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Button { running ? stop() : start() } label: {
                    Image(systemName: running ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 64)).foregroundStyle(.white.opacity(0.9))
                }
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Dauer-Coach")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stop() }
    }

    private func fetch(_ n: Int, previous: String) async -> [String] {
        let r = try? await state.api.object("POST", "/api/ai/monolog", json: [
            "context": coachContext(entries, state.profile, healthUpload: state.healthUpload), "lang": lang, "theme": theme,
            "block": n, "blocks": blocks, "previous": previous,
        ])
        return r?["lines"] as? [String] ?? []
    }

    private func start() {
        error = nil
        speaker.api = state.ttsAvailable ? state.api : nil
        speaker.persona = lang == "en" ? "darkEn" : "dark"
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            line = String(localized: "Einen Moment …")
            var lines = await fetch(1, previous: "")
            for n in 1...blocks {
                guard !lines.isEmpty, !Task.isCancelled else { break }
                if n == 1 { try? Speaker.activateSession(record: false); drone.start() }
                block = n
                // Nächsten Abschnitt schon schreiben lassen, während dieser läuft
                let next = n < blocks ? Task { await fetch(n + 1, previous: lines.suffix(4).joined(separator: " ")) } : nil
                for (i, l) in lines.enumerated() where !Task.isCancelled {
                    line = l
                    // Stimme für die nächsten zwei Zeilen schon erzeugen lassen, damit keine Lücken entstehen
                    if i == 0 { lines.prefix(3).dropFirst().forEach(speaker.prefetch) } else if i + 2 < lines.count { speaker.prefetch(lines[i + 2]) }
                    speaker.speak(l, rate: 0.45, pitch: 0.8)
                    await speaker.waitUntilDone()
                }
                lines = await next?.value ?? []
                if n < blocks && lines.isEmpty && !Task.isCancelled { error = String(localized: "Nächster Abschnitt konnte nicht geladen werden.") }
            }
            stop()
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        speaker.stop()
        drone.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

/// Dunkler, ruhiger Klangteppich (tiefe Sinustöne mit langsamem Schweben), direkt auf dem iPhone erzeugt
final class Drone {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?

    func start() {
        guard node == nil else { return }
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let freqs = [55.0, 82.41, 110.0, 164.81]
        var phases = [Double](repeating: 0, count: freqs.count), t = 0.0
        let node = AVAudioSourceNode { _, _, frames, list in
            for f in 0..<Int(frames) {
                t += 1 / rate
                let swell = 0.6 + 0.4 * sin(2 * .pi * 0.04 * t)
                var v = 0.0
                for i in freqs.indices {
                    phases[i] += 2 * .pi * freqs[i] * (1 + 0.002 * sin(t * 0.3 + Double(i))) / rate
                    v += sin(phases[i]) / Double(i + 1)
                }
                let s = Float(v * 0.035 * swell * min(1, t / 4))  // sanft einblenden
                for b in UnsafeMutableAudioBufferListPointer(list) { b.mData?.assumingMemoryBound(to: Float.self)[f] = s }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        try? engine.start()
        self.node = node
    }

    func stop() {
        engine.stop()
        if let node { engine.detach(node) }
        node = nil
    }
}
