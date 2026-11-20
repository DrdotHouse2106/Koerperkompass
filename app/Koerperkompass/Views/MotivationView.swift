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

    private var favs: [String] { (try? JSONDecoder().decode([String].self, from: favData)) ?? [] }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, text in
                    page(text)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .onAppear { if i >= items.count - 3 { more() } }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .ignoresSafeArea()
        .navigationTitle("Motivation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Neue persönliche Sprüche", systemImage: "sparkles") { personal() }.disabled(loadingPersonal)
                if !favs.isEmpty { Button("Meine Favoriten zeigen", systemImage: "heart.fill") { items = favs } }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .onAppear { if items.isEmpty { more() } }
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
            .padding(.bottom, 70)
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
