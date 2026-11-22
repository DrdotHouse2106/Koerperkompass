import SwiftData
import SwiftUI

/// Übungsbibliothek: rund 870 Übungen (gemeinfreie free-exercise-db über den eigenen Server) mit Muskelgruppen-Filter,
/// Körperfigur (Hauptmuskeln rot, Hilfsmuskeln blau), Bildern im Wechsel, Anleitung, YouTube-Suche und eigenem Fortschritt.
struct LibExercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    var nameDe: String?
    let level: String?
    let equipment: String?
    let primary: [String]
    let secondary: [String]
    let category: String?
    let images: [String]
    var instructions: [String]?
    var instructionsDe: [String]?

    var title: String { (nameDe ?? "").isEmpty ? name : nameDe! }

    /// Passt die Übung zu den Geräten im Profil? (nil = Geräte unbekannt → alles)
    func fits(_ equipment: [String]?) -> Bool {
        guard let mine = equipment else { return true }
        let gym = mine.contains("gym")
        switch self.equipment {
        case nil, "body only": return true
        case "dumbbell": return gym || mine.contains("dumbbells")
        case "barbell", "e-z curl bar": return gym || mine.contains("barbell")
        case "kettlebells": return gym || mine.contains("kettlebell")
        case "bands": return gym || mine.contains("bands")
        default: return gym
        }
    }
}

/// Muskelgruppen der Datenbank → deutscher Name
let muscleNames: [(id: String, name: LocalizedStringResource)] = [
    ("chest", "Brust"), ("shoulders", "Schultern"), ("biceps", "Bizeps"), ("triceps", "Trizeps"), ("forearms", "Unterarme"),
    ("abdominals", "Bauch"), ("lats", "Latissimus"), ("middle back", "Mittlerer Rücken"), ("lower back", "Unterer Rücken"),
    ("traps", "Nacken/Trapez"), ("neck", "Hals"), ("glutes", "Gesäß"), ("quadriceps", "Oberschenkel vorn"),
    ("hamstrings", "Oberschenkel hinten"), ("adductors", "Adduktoren"), ("abductors", "Abduktoren"), ("calves", "Waden"),
]

func muscleName(_ id: String) -> String { muscleNames.first { $0.id == id }.map { String(localized: $0.name) } ?? id }

/// Bibliothek einmal laden und auf dem iPhone zwischenspeichern
@Observable @MainActor final class ExerciseStore {
    static let shared = ExerciseStore()
    var all: [LibExercise] = []
    var error: String?
    private let file = URL.cachesDirectory.appendingPathComponent("exercises.json")

    func load(_ api: API) async {
        if all.isEmpty, let d = try? Data(contentsOf: file) { all = (try? JSONDecoder().decode([LibExercise].self, from: d)) ?? [] }
        // neu holen, solange noch Namen unübersetzt sind (der Server übersetzt im Hintergrund)
        guard all.isEmpty || all.contains(where: { ($0.nameDe ?? "").isEmpty }) else { return }
        do {
            let d = try await api.call("GET", "/api/exercises")
            all = try JSONDecoder().decode([LibExercise].self, from: d)
            try? d.write(to: file)
            error = nil
        } catch { if all.isEmpty { self.error = error.localizedDescription } }
    }
}

struct ExerciseLibraryView: View {
    @Environment(AppState.self) private var state
    @State private var store = ExerciseStore.shared
    @State private var search = ""
    @State private var muscle: String?
    @State private var onlyMine = true

    var body: some View {
        let list = store.all.filter { e in
            (muscle == nil || e.primary.contains(muscle!)) && (!onlyMine || e.fits(state.profile.equipment))
                && (search.isEmpty || e.title.localizedCaseInsensitiveContains(search) || e.name.localizedCaseInsensitiveContains(search))
        }.sorted { $0.title < $1.title }
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(muscleNames, id: \.id) { m in
                            Button { muscle = muscle == m.id ? nil : m.id } label: {
                                VStack(spacing: 4) {
                                    BodyMap(primary: [m.id], secondary: [], back: BodyMap.isBack(m.id)).frame(width: 34, height: 64)
                                    Text(m.name).font(.caption2).lineLimit(1)
                                }
                                .padding(6)
                                .background(muscle == m.id ? Color.red.opacity(0.25) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if state.profile.equipment != nil {
                    Toggle("Nur mit meinen Geräten", isOn: $onlyMine)
                }
            } footer: { Text("\(list.count) Übungen") }
            if let error = store.error { Text(error).foregroundStyle(.red) }
            ForEach(list) { e in
                NavigationLink { ExerciseDetailView(exercise: e) } label: {
                    HStack(spacing: 12) {
                        ExerciseImage(path: e.images.first, server: state.server).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.subheadline.bold()).lineLimit(2)
                            Text(e.primary.map(muscleName).joined(separator: ", ")).font(.caption).foregroundStyle(.red.opacity(0.9))
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: Text("Übung suchen"))
        .themed()
        .navigationTitle("Übungsbibliothek")
        .task { await store.load(state.api) }
        .overlay { if store.all.isEmpty && store.error == nil { ProgressView() } }
    }
}

/// Bild einer Übung vom eigenen Server (zwischengespeichert)
struct ExerciseImage: View {
    let path: String?
    let server: String
    var body: some View {
        if let path, let url = URL(string: server + "/api/exercises/img/" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
        } else {
            Color.white.opacity(0.06)
        }
    }
}

struct ExerciseDetailView: View {
    @State var exercise: LibExercise
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Entry> { $0.module == "exercises" }) private var all: [Entry]
    @State private var reps: Double?
    @State private var weight: Double?

    private var sets: [Entry] {
        all.filter { !$0.deleted && ($0.text("exerciseId") == exercise.id || $0.text("exercise") == exercise.title) }
            .sorted { ($0.date, $0.updated) > ($1.date, $1.updated) }
    }

    var body: some View {
        List {
            Section {
                // Start- und Endbild im Wechsel – wie eine kleine Animation
                TimelineView(.periodic(from: .now, by: 1)) { t in
                    let i = Int(t.date.timeIntervalSince1970) % max(exercise.images.count, 1)
                    ExerciseImage(path: exercise.images.indices.contains(i) ? exercise.images[i] : nil, server: state.server)
                        .frame(height: 240).frame(maxWidth: .infinity).clipped()
                }
                .listRowInsets(EdgeInsets())
                HStack(spacing: 24) {
                    BodyMap(primary: exercise.primary, secondary: exercise.secondary, back: false).frame(width: 70, height: 140)
                    BodyMap(primary: exercise.primary, secondary: exercise.secondary, back: true).frame(width: 70, height: 140)
                    VStack(alignment: .leading, spacing: 6) {
                        Label(exercise.primary.map(muscleName).joined(separator: ", "), systemImage: "circle.fill").foregroundStyle(.red)
                        if !exercise.secondary.isEmpty {
                            Label(exercise.secondary.map(muscleName).joined(separator: ", "), systemImage: "circle.fill").foregroundStyle(.blue)
                        }
                        if let eq = exercise.equipment { Text(equipmentName(eq)).foregroundStyle(.secondary) }
                        if let l = exercise.level { Text(levelName(l)).foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity)
            }
            Section("Anleitung") {
                let steps = (exercise.instructionsDe ?? []).isEmpty ? (exercise.instructions ?? []) : exercise.instructionsDe!
                if steps.isEmpty { ProgressView() }
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top) { Text("\(i + 1).").bold(); Text(s) }
                }
                if let u = URL(string: "https://www.youtube.com/results?search_query=" + ((exercise.name + " exercise").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                    Link(destination: u) { Label("Auf YouTube ansehen", systemImage: "play.rectangle.fill") }
                }
            }
            Section("Satz eintragen") {
                HStack {
                    TextField("Wiederholungen", value: $reps, format: .number).keyboardType(.numberPad)
                    TextField("Gewicht (kg)", value: $weight, format: .number).keyboardType(.decimalPad)
                    Button("Eintragen") {
                        var v: [String: Any] = ["exercise": exercise.title, "exerciseId": exercise.id, "reps": reps ?? 0, "time": Day.now]
                        if let weight, weight > 0 { v["weight"] = weight }
                        context.insert(Entry(module: "exercises", values: v))
                        state.changed(context)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    .disabled((reps ?? 0) <= 0)
                }
            }
            if !sets.isEmpty {
                Section("Mein Fortschritt") {
                    let maxW = sets.compactMap { $0.num("weight") }.max(), maxR = sets.compactMap { $0.num("reps") }.max()
                    let series = Dictionary(grouping: sets, by: \.date).sorted { $0.key < $1.key }
                        .compactMap { $0.value.compactMap { $0.num("weight") ?? $0.num("reps") }.max() }
                    HStack {
                        if let maxW { VStack { Text("\(maxW.short) kg").font(.title3.bold()); Text("Rekord Gewicht").font(.caption2) } }
                        Spacer()
                        if let maxR { VStack { Text("\(maxR.whole)").font(.title3.bold()); Text("Rekord Wdh.").font(.caption2) } }
                        Spacer()
                        let tier = Tier.of(series)
                        VStack { Text(tier.title).font(.title3.bold()).foregroundStyle(tier.color); Text("Stufe").font(.caption2) }
                    }
                    ForEach(sets.prefix(10)) { e in
                        HStack {
                            Text("\((e.num("reps") ?? 0).whole) Wdh." + (e.num("weight").map { " · \($0.short) kg" } ?? ""))
                            Spacer()
                            Text(Day.date(e.date), format: .dateTime.day().month()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .themed()
        .navigationTitle(Text(exercise.title))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Anleitung (auf Deutsch, sobald übersetzt)
            if let d = try? await state.api.call("GET", "/api/exercises/\(exercise.id)"),
               let full = try? JSONDecoder().decode(LibExercise.self, from: d) { exercise = full }
        }
    }

    private func equipmentName(_ e: String) -> String {
        [ "body only": "Körpergewicht", "dumbbell": "Kurzhanteln", "barbell": "Langhantel", "kettlebells": "Kettlebell",
          "bands": "Widerstandsbänder", "cable": "Kabelzug", "machine": "Maschine", "medicine ball": "Medizinball",
          "exercise ball": "Gymnastikball", "foam roll": "Faszienrolle", "e-z curl bar": "SZ-Stange", "other": "Sonstiges" ][e]
            .map { String(localized: String.LocalizationValue($0)) } ?? e
    }

    private func levelName(_ l: String) -> String {
        ["beginner": String(localized: "Anfänger"), "intermediate": String(localized: "Fortgeschritten"), "expert": String(localized: "Profi")][l] ?? l
    }
}

/// Einfache Körperfigur von vorn oder hinten; Hauptmuskeln rot, Hilfsmuskeln blau
struct BodyMap: View {
    let primary: [String]
    let secondary: [String]
    let back: Bool

    static func isBack(_ m: String) -> Bool { ["lats", "middle back", "lower back", "traps", "triceps", "glutes", "hamstrings", "calves"].contains(m) }

    /// Muskelflächen im Raster 100 × 200
    private static let front: [(String, [CGRect])] = [
        ("neck", [CGRect(x: 45, y: 21, width: 10, height: 6)]),
        ("shoulders", [CGRect(x: 24, y: 28, width: 11, height: 10), CGRect(x: 65, y: 28, width: 11, height: 10)]),
        ("chest", [CGRect(x: 35, y: 31, width: 14, height: 13), CGRect(x: 51, y: 31, width: 14, height: 13)]),
        ("biceps", [CGRect(x: 22, y: 40, width: 8, height: 17), CGRect(x: 70, y: 40, width: 8, height: 17)]),
        ("forearms", [CGRect(x: 20, y: 59, width: 8, height: 20), CGRect(x: 72, y: 59, width: 8, height: 20)]),
        ("abdominals", [CGRect(x: 41, y: 46, width: 18, height: 28)]),
        ("abductors", [CGRect(x: 33, y: 78, width: 5, height: 14), CGRect(x: 62, y: 78, width: 5, height: 14)]),
        ("adductors", [CGRect(x: 45, y: 86, width: 10, height: 18)]),
        ("quadriceps", [CGRect(x: 35, y: 86, width: 12, height: 40), CGRect(x: 53, y: 86, width: 12, height: 40)]),
        ("calves", [CGRect(x: 37, y: 138, width: 9, height: 30), CGRect(x: 54, y: 138, width: 9, height: 30)]),
    ]
    private static let backSide: [(String, [CGRect])] = [
        ("neck", [CGRect(x: 45, y: 21, width: 10, height: 6)]),
        ("traps", [CGRect(x: 38, y: 26, width: 24, height: 11)]),
        ("shoulders", [CGRect(x: 24, y: 28, width: 11, height: 10), CGRect(x: 65, y: 28, width: 11, height: 10)]),
        ("triceps", [CGRect(x: 22, y: 40, width: 8, height: 17), CGRect(x: 70, y: 40, width: 8, height: 17)]),
        ("forearms", [CGRect(x: 20, y: 59, width: 8, height: 20), CGRect(x: 72, y: 59, width: 8, height: 20)]),
        ("lats", [CGRect(x: 34, y: 39, width: 9, height: 22), CGRect(x: 57, y: 39, width: 9, height: 22)]),
        ("middle back", [CGRect(x: 44, y: 38, width: 12, height: 18)]),
        ("lower back", [CGRect(x: 43, y: 58, width: 14, height: 14)]),
        ("glutes", [CGRect(x: 35, y: 74, width: 30, height: 14)]),
        ("hamstrings", [CGRect(x: 35, y: 90, width: 12, height: 36), CGRect(x: 53, y: 90, width: 12, height: 36)]),
        ("calves", [CGRect(x: 37, y: 136, width: 10, height: 32), CGRect(x: 53, y: 136, width: 10, height: 32)]),
    ]

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 100, size.height / 200)
            let dx = (size.width - 100 * s) / 2
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: dx + x * s, y: y * s, width: w * s, height: h * s) }
            let base = Color.white.opacity(0.18)
            // Grundfigur
            ctx.fill(Path(ellipseIn: r(41, 2, 18, 18)), with: .color(base))
            for rect in [r(32, 25, 36, 56), r(20, 28, 11, 54), r(69, 28, 11, 54), r(34, 80, 15, 112), r(51, 80, 15, 112)] {
                ctx.fill(Path(roundedRect: rect, cornerRadius: 5 * s), with: .color(base))
            }
            for (m, rects) in back ? Self.backSide : Self.front {
                let color: Color? = primary.contains(m) ? .red : secondary.contains(m) ? .blue : nil
                guard let color else { continue }
                for rect in rects { ctx.fill(Path(roundedRect: r(rect.minX, rect.minY, rect.width, rect.height), cornerRadius: 3 * s), with: .color(color.opacity(0.85))) }
            }
        }
    }
}
