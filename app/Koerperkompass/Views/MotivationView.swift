import AVFoundation
import Speech
import AppIntents
import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Motivation: Sprüche ohne Ende zum Durchwischen – gemischt aus dem Vorrat und persönlichen Sprüchen
/// (Apple Intelligence oder Claude). Favoriten, Teilen und „Als Bild sichern“ (z. B. als Hintergrundbild).
struct MotivationView: View {
    @Environment(AppState.self) private var state
    @Query private var entries: [Entry]
    @State private var items: [String] = []
    @State private var order: [Int] = []
    @State private var loadingPersonal = false
    @AppStorage("motivationFavs") private var favData = Data()
    @AppStorage("motivationStyle") private var style = "soft"  // "soft" oder "dark"
    @AppStorage("darkLang") private var darkLang = DarkStory.language
    @State private var stories: [DarkStory] = []
    @State private var storyOrder: [Int] = []
    @State private var speaker = Speaker()
    @State private var clips: [Clip] = []
    @State private var addClip = false

    private var favs: [String] { (try? JSONDecoder().decode([String].self, from: favData)) ?? [] }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if style == "clips" {
                    if clips.isEmpty {
                        ClipEmpty(add: { addClip = true }).containerRelativeFrame([.horizontal, .vertical])
                    }
                    ForEach(clips) { clip in
                        ClipPage(clip: clip, api: state.api, delete: { deleteClip(clip) }, rename: { renameClip(clip, $0) })
                            .containerRelativeFrame([.horizontal, .vertical])
                    }
                } else if style == "dark" {
                    ForEach(Array(stories.enumerated()), id: \.offset) { i, story in
                        DarkPage(story: story, speaker: speaker, api: state.ttsAvailable && !state.demo ? state.api : nil)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .onAppear { if i >= stories.count - 3 { moreStories() } }
                    }
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, text in
                        page(text)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .onAppear { if i >= items.count - 3 { more() } }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .onChange(of: style) { speaker.stop(); if style == "dark" && stories.isEmpty { moreStories() }; if style == "clips" { Task { await loadClips() } } }
        .task { if style == "clips" { await loadClips() } }
        .sheet(isPresented: $addClip, onDismiss: { Task { await loadClips() } }) { ClipAddSheet() }
        .onChange(of: darkLang) { speaker.stop(); stories = []; storyOrder = []; moreStories() }
        .onDisappear { speaker.stop() }
        .scrollTargetBehavior(.paging)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .tabBar)  // sonst liegen die Knöpfe unten hinter der Tab-Leiste
        .navigationTitle("Motivation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Picker("Stil", selection: $style) {
                    Text("Sanft").tag("soft")
                    Text("Dark").tag("dark")
                    if state.clipsAvailable { Text("Meine Clips").tag("clips") }
                }
                if style == "clips" { Button("Clip aus Link hinzufügen", systemImage: "plus") { addClip = true } }
                if style == "dark" {
                    Picker("Sprache", selection: $darkLang) {
                        Text("Deutsch").tag("de")
                        Text("Englisch").tag("en")
                        Text("Gemischt").tag("mix")
                    }
                    if state.aiAvailable && state.aiConsent {
                        Button("Neue persönliche Geschichten", systemImage: "sparkles") { personalStories() }.disabled(loadingPersonal)
                    }
                } else {
                    Button("Neue persönliche Sprüche", systemImage: "sparkles") { personal() }.disabled(loadingPersonal)
                    if !favs.isEmpty { Button("Meine Favoriten zeigen", systemImage: "heart.fill") { items = favs } }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .onAppear { if items.isEmpty { more() }; if style == "dark" && stories.isEmpty { moreStories() } }
    }

    private func loadClips() async {
        guard let data = try? await state.api.call("GET", "/api/clips") else { return }
        clips = (try? JSONDecoder().decode([Clip].self, from: data)) ?? []
    }

    private func deleteClip(_ c: Clip) {
        Task {
            _ = try? await state.api.call("DELETE", "/api/clips/\(c.id)")
            try? FileManager.default.removeItem(at: Clip.cache(c.id))
            try? FileManager.default.removeItem(at: Clip.cache(c.id).deletingPathExtension().appendingPathExtension("json"))
            await loadClips()
        }
    }

    private func renameClip(_ c: Clip, _ title: String) {
        Task {
            _ = try? await state.api.call("PUT", "/api/clips/\(c.id)", json: ["title": title])
            await loadClips()
        }
    }

    /// Nächste Dark-Geschichten: durchgemischt, erst wieder, wenn alle dran waren
    private func moreStories() {
        let pool = DarkStory.pool(darkLang)
        guard !pool.isEmpty else { return }
        for _ in 0..<6 {
            if storyOrder.isEmpty { storyOrder = Array(pool.indices).shuffled() }
            stories.append(pool[storyOrder.removeFirst()])
        }
    }

    /// Persönliche Dark-Geschichten von Claude (Stilvorlage auf dem Server)
    private func personalStories() {
        loadingPersonal = true
        Task {
            defer { loadingPersonal = false }
            guard let data = try? await state.api.call("POST", "/api/ai/motivation", json: [
                "style": "dark", "count": 3, "lang": darkLang,
                "context": coachContext(entries, state.profile, healthUpload: state.healthUpload),
            ]), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let list = obj["stories"], let d = try? JSONSerialization.data(withJSONObject: list),
                let new = try? JSONDecoder().decode([DarkStory].self, from: d) else { return }
            stories = new + stories
        }
    }

    private func page(_ text: String) -> some View {
        ZStack(alignment: .bottom) {
            MotivationCard(text: text)
            HStack(spacing: 28) {
                Button { toggleFav(text) } label: {
                    Image(systemName: favs.contains(text) ? "heart.fill" : "heart").font(.title2)
                }
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up").font(.title2) }
                // Als Bild teilen/sichern (z. B. „Bild sichern“ → als Hintergrundbild verwenden); erst beim Teilen erzeugt
                ShareLink(item: QuoteImage(text: text), preview: SharePreview(Text("Motivation"))) {
                    Image(systemName: "photo.on.rectangle").font(.title2)
                }
            }
            .foregroundStyle(.white)
            .padding(.bottom, 50)
        }
    }

    /// Nächste Sprüche: Vorrat durchgemischt, ein Spruch kommt erst wieder, wenn alle dran waren
    private func more() {
        let pool = Motivation.pool
        let streak = QuestProgress(entries, state.profile).streak
        var add: [String] = []
        if items.isEmpty && UserDefaults.standard.string(forKey: "aiMotivationDay") == Day.today {
            add += UserDefaults.standard.stringArray(forKey: "aiMotivation") ?? []  // persönliche von heute zuerst (nie von gestern)
        }
        for _ in 0..<10 {
            if order.isEmpty { order = Array(pool.indices).shuffled() }
            add.append(Motivation.fill(pool[order.removeFirst()], profile: state.profile, streak: streak))
        }
        items += add
    }

    /// Persönliche Sprüche zu deinen Daten (Apple Intelligence auf dem iPhone, sonst Claude mit Zustimmung)
    private func personal() {
        loadingPersonal = true
        Task {
            defer { loadingPersonal = false }
            let ctx = coachContext(entries, state.profile, healthUpload: true)
            var list = await OnDevice.motivation(count: 5, context: ctx) ?? []
            if list.isEmpty && state.aiAvailable && state.aiConsent,
               let r = try? await state.api.object("POST", "/api/ai/motivation", json: [
                   "context": coachContext(entries, state.profile, healthUpload: state.healthUpload), "count": 5,
                   "lang": Locale.current.language.languageCode?.identifier ?? "de",
               ]) {
                list = r["messages"] as? [String] ?? []
            }
            items = list + items
        }
    }

    private func toggleFav(_ text: String) {
        var f = favs
        if let i = f.firstIndex(of: text) { f.remove(at: i) } else { f.append(text) }
        favData = (try? JSONEncoder().encode(f)) ?? Data()
    }
}

/// Ein Spruch groß auf Verlauf – auch als Bild (Hintergrundbild, Teilen)
struct MotivationCard: View {
    let text: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.2), Theme.petrol.opacity(0.9), Theme.orange.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                Image(systemName: "safari.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.8))
                Text(text)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 32)
            }
        }
    }

    /// Als Bild in Bildschirmgröße (für Hintergrundbild oder Teilen)
    @MainActor static func image(_ text: String) -> UIImage? {
        let r = ImageRenderer(content: MotivationCard(text: text).frame(width: 430, height: 932))
        r.scale = 3
        return r.uiImage
    }
}

/// Spruch als PNG – wird erst beim Teilen gerendert
struct QuoteImage: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { q in
            await MainActor.run { MotivationCard.image(q.text)?.pngData() } ?? Data()
        }
    }
}

/// Kurzbefehl: Motivationsbild für heute – z. B. in einer Automation mit „Hintergrundbild festlegen“
struct MotivationImageIntent: AppIntent {
    static var title: LocalizedStringResource = "Motivations-Hintergrundbild"
    static var description = IntentDescription("Erzeugt ein Bild mit einem motivierenden Spruch – z. B. für die Aktion „Hintergrundbild festlegen“.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let profile = UserDefaults.standard.data(forKey: "profile").flatMap { try? JSONDecoder().decode(Profile.self, from: $0) } ?? Profile()
        let entries = (try? ModelContext(sharedContainer).fetch(FetchDescriptor<Entry>())) ?? []
        let personal = UserDefaults.standard.string(forKey: "aiMotivationDay") == Day.today ? UserDefaults.standard.stringArray(forKey: "aiMotivation") ?? [] : []
        let text = personal.first ?? Motivation.fill(Motivation.pool.randomElement() ?? "", profile: profile, streak: QuestProgress(entries, profile).streak)
        guard let data = MotivationCard.image(text)?.pngData() else { throw API.Failure(message: String(localized: "Bild konnte nicht erzeugt werden")) }
        return .result(value: IntentFile(data: data, filename: "motivation.png", type: .png))
    }
}

/// Eine Dark-Geschichte: Schwarz-Weiß, Schlagworte rot; „Abspielen“ zeigt Zeile für Zeile und liest mit tiefer Stimme vor
struct DarkPage: View {
    let story: DarkStory
    let speaker: Speaker
    let api: API?
    @State private var current: Int?  // Zeile beim Abspielen
    @State private var task: Task<Void, Never>?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(white: 0.13), .black], startPoint: .top, endPoint: .bottom)
            if let i = current {
                Self.styled(story.lines[i], size: 38)
                    .multilineTextAlignment(.center).padding(.horizontal, 28)
                    .id(i).transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(story.lines, id: \.self) { Self.styled($0, size: 22) }
                }
                .padding(.horizontal, 28)
            }
            VStack {
                Spacer()
                Button { current == nil ? play() : stop() } label: {
                    Image(systemName: current == nil ? "play.circle.fill" : "stop.circle.fill").font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.bottom, 60)
            }
        }
        .onDisappear { stop() }
    }

    private func play() {
        speaker.api = api
        speaker.persona = story.lang == "en" ? "darkEn" : "dark"
        task = Task {
            for i in story.lines.indices {
                withAnimation(.easeInOut(duration: 0.4)) { current = i }
                // GROSSBUCHSTABEN nur fürs Auge – vorgelesen normal geschrieben, sonst buchstabiert die Stimme
                let spoken = story.lines[i].split(separator: " ").map { w in
                    let l = w.filter(\.isLetter)
                    return l.count >= 2 && l == l.uppercased() ? w.lowercased().capitalized : String(w)
                }.joined(separator: " ")
                speaker.speak(spoken, rate: story.inner == true ? 0.5 : 0.42, pitch: 0.8)  // innere Stimme drängender
                await speaker.waitUntilDone()
                try? await Task.sleep(for: .milliseconds(story.inner == true ? 150 : 350))
                if Task.isCancelled { return }
            }
            withAnimation { current = nil }
        }
    }

    private func stop() {
        task?.cancel()
        speaker.stop()
        current = nil
    }

    /// Wörter in GROSSBUCHSTABEN rot und fett hervorheben
    static func styled(_ line: String, size: CGFloat) -> Text {
        var a = AttributedString()
        for (n, word) in line.split(separator: " ").enumerated() {
            var w = AttributedString((n == 0 ? "" : " ") + word)
            let letters = word.filter(\.isLetter)
            let loud = letters.count >= 2 && letters == letters.uppercased()
            w.foregroundColor = loud ? .red : .white
            w.font = .system(size: loud ? size * 1.15 : size, weight: loud ? .black : .semibold)
            a += w
        }
        return Text(a)
    }
}

// MARK: Meine Clips – private Tonspuren aus Reels (nur im eigenen Konto, nie geteilt)

struct Clip: Codable, Identifiable, Hashable {
    let id: String
    let url: String
    let title: String
    static func cache(_ id: String) -> URL { URL.cachesDirectory.appendingPathComponent("clips/\(id).m4a") }
}

/// Ein Clip: dunkle Seite, Titel, Abspielen mit pulsierenden Balken
struct ClipPage: View {
    let clip: Clip
    let api: API
    let delete: () -> Void
    let rename: (String) -> Void
    @State private var player: AVAudioPlayer?
    @State private var lines: [ClipLine] = []
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var playing = false
    @State private var loading = false
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(white: 0.12), .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 28) {
                TimelineView(.animation(minimumInterval: 0.12, paused: !playing)) { t in
                    HStack(spacing: 5) {
                        ForEach(0..<16, id: \.self) { i in
                            let h = playing ? 12 + 50 * abs(sin(t.date.timeIntervalSinceReferenceDate * 3 + Double(i) * 0.7)) : 8
                            Capsule().fill(i % 4 == 0 ? Color.red : .white.opacity(0.8)).frame(width: 6, height: h)
                        }
                    }
                    .frame(height: 70)
                }
                if !clip.title.isEmpty {
                    Text(clip.title).font(.system(size: 26, weight: .heavy)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 28)
                }
                Button { toggle() } label: {
                    Image(systemName: loading ? "hourglass.circle.fill" : playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64)).foregroundStyle(.white.opacity(0.9))
                }
                .disabled(loading)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                // Transkript läuft mit: aktuelle Zeile hell, die nächste gedämpft
                TimelineView(.animation(minimumInterval: 0.1, paused: !playing)) { _ in
                    let t = player?.currentTime ?? 0
                    let i = lines.lastIndex { $0.start <= t + 0.1 } ?? -1
                    VStack(spacing: 10) {
                        Text(i >= 0 && t <= lines[i].end + 1.5 ? lines[i].text : " ")
                            .font(.title3.bold()).foregroundStyle(.white)
                        Text(i + 1 < lines.count ? lines[i + 1].text : " ").font(.body).foregroundStyle(.white.opacity(0.4))
                    }
                    .multilineTextAlignment(.center).padding(.horizontal, 28).frame(minHeight: 110)
                    .animation(.easeInOut(duration: 0.25), value: i)
                }
                .opacity(lines.isEmpty ? 0 : 1)
            }
            VStack {
                Spacer()
                HStack(spacing: 28) {
                    if let u = URL(string: clip.url) { Link(destination: u) { Image(systemName: "link").font(.title3) } }
                    Button { newTitle = clip.title; renaming = true } label: { Image(systemName: "pencil").font(.title3) }
                    Button { confirmDelete = true } label: { Image(systemName: "trash").font(.title3) }
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 50)
            }
        }
        .onDisappear { player?.stop(); playing = false }
        .alert("Eigener Titel", isPresented: $renaming) {
            TextField("Titel (optional)", text: $newTitle)
            Button("Speichern") { rename(newTitle) }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Clip löschen?", isPresented: $confirmDelete) { Button("Löschen", role: .destructive) { player?.stop(); delete() } }
    }

    private func toggle() {
        if let player, playing { player.pause(); playing = false; return }
        if let player { player.play(); playing = true; return }
        loading = true
        Task {
            defer { loading = false }
            let file = Clip.cache(clip.id)
            var data = try? Data(contentsOf: file)
            if data == nil {
                data = try? await api.call("GET", "/api/clips/\(clip.id)")
                if let data {
                    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: file)
                }
            }
            guard let data, let p = try? AVAudioPlayer(data: data) else { error = String(localized: "Ton konnte nicht geladen werden"); return }
            if lines.isEmpty { Task { lines = await ClipLine.transcript(file) } }
            try? Speaker.activateSession()
            player = p
            p.play()
            playing = true
            // Ende abwarten, damit die Balken stoppen
            while p.isPlaying { try? await Task.sleep(for: .milliseconds(300)) }
            if p.currentTime == 0 { playing = false }
        }
    }
}

struct ClipEmpty: View {
    let add: () -> Void
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                Image(systemName: "waveform").font(.system(size: 48)).foregroundStyle(.red)
                Text("Meine Clips").font(.title2.bold()).foregroundStyle(.white)
                Text("Füge den Link zu einem Reel oder Video ein – dein Server speichert nur den Ton, nur für dich. Am schnellsten über Teilen mit dem Kurzbefehl „Clip speichern“.")
                    .font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 32)
                Button("Clip aus Link hinzufügen", systemImage: "plus", action: add).buttonStyle(.borderedProminent).tint(.red)
            }
        }
    }
}

struct ClipAddSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://www.facebook.com/…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
                    Button("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard") { url = UIPasteboard.general.string ?? url }
                    if let error { Text(error).foregroundStyle(.red) }
                } footer: {
                    Text("Nur für dich: Der Ton wird in deinem Konto auf deinem Server gespeichert, nicht geteilt und nicht weitergegeben. Bitte nur für den privaten Gebrauch.")
                }
            }
            .navigationTitle("Clip hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? LocalizedStringKey("Wird geladen …") : "Hinzufügen") {
                        busy = true
                        error = nil
                        Task {
                            defer { busy = false }
                            do { _ = try await state.api.object("POST", "/api/clips", json: ["url": url.trimmingCharacters(in: .whitespaces)]); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(busy || !url.lowercased().hasPrefix("https://"))
                }
            }
        }
    }
}

/// Eine Zeile des mitlaufenden Transkripts. Erkannt wird auf dem iPhone (Apple-Spracherkennung, wenn möglich ohne Netz),
/// Deutsch und Englisch werden probiert, das sicherere Ergebnis gewinnt. Das Ergebnis liegt im Cache neben dem Ton.
struct ClipLine: Codable {
    let start, end: Double
    let text: String

    static func transcript(_ audio: URL) async -> [ClipLine] {
        let cache = audio.deletingPathExtension().appendingPathExtension("json")
        if let d = try? Data(contentsOf: cache), let l = try? JSONDecoder().decode([ClipLine].self, from: d) { return l }
        guard await withCheckedContinuation({ c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }) else { return [] }
        var best: [SFTranscriptionSegment] = [], score = 0.0
        for id in ["en-US", "de-DE"] {
            let segs = await recognize(audio, id)
            let s = segs.reduce(0) { $0 + Double($1.confidence) }
            if s > score { best = segs; score = s }
        }
        // Wörter zu Zeilen bündeln: höchstens 7 Wörter, neue Zeile auch nach einer Pause
        var lines: [ClipLine] = [], words: [SFTranscriptionSegment] = []
        func flush() {
            guard let f = words.first, let l = words.last else { return }
            lines.append(ClipLine(start: f.timestamp, end: l.timestamp + l.duration, text: words.map(\.substring).joined(separator: " ")))
            words = []
        }
        for w in best {
            if let l = words.last, words.count >= 7 || w.timestamp - (l.timestamp + l.duration) > 0.7 { flush() }
            words.append(w)
        }
        flush()
        if let d = try? JSONEncoder().encode(lines) { try? d.write(to: cache) }
        return lines
    }

    private static func recognize(_ audio: URL, _ locale: String) async -> [SFTranscriptionSegment] {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: locale)), r.isAvailable else { return [] }
        let req = SFSpeechURLRecognitionRequest(url: audio)
        req.shouldReportPartialResults = false
        req.requiresOnDeviceRecognition = r.supportsOnDeviceRecognition
        return await withCheckedContinuation { c in
            var done = false
            r.recognitionTask(with: req) { result, error in
                guard !done, error != nil || result?.isFinal == true else { return }
                done = true
                c.resume(returning: result?.bestTranscription.segments ?? [])
            }
        }
    }
}
