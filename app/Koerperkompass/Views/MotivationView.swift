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

    private var favs: [String] { (try? JSONDecoder().decode([String].self, from: favData)) ?? [] }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if style == "dark" {
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
        .onChange(of: style) { speaker.stop(); if style == "dark" && stories.isEmpty { moreStories() } }
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
                }
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
        if items.isEmpty { add += UserDefaults.standard.stringArray(forKey: "aiMotivation") ?? [] }  // persönliche von heute zuerst
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
                speaker.speak(spoken, rate: 0.42, pitch: 0.8)
                await speaker.waitUntilDone()
                try? await Task.sleep(for: .milliseconds(350))
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
