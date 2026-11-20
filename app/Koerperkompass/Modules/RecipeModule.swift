import PhotosUI
import SwiftData
import SwiftUI

/// Rezepte: eigene Rezeptsammlung – aus Reel-Links (über Reelkoch auf dem eigenen Server) oder eingefügtem Text.
/// Ein Eintrag je Rezept; „Gegessen“ trägt Portionen mit Nährwerten in die Ernährung ein. Der Coach kennt die Rezepte.
struct RecipeModule: AppModule {
    let id = "recipes"
    let name: LocalizedStringResource = "Rezepte"
    let symbol = "book.closed.fill"
    let fields: [Field] = []

    func tile(_ entries: [Entry]) -> AnyView { AnyView(RecipeTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(RecipeList(entries: entries)) }
}

extension Entry {
    var ingredients: [(amount: String, name: String)] {
        (values["ingredients"] as? [[String: Any]] ?? []).map { ($0["amount"] as? String ?? "", $0["name"] as? String ?? "") }
    }
    var steps: [String] { values["steps"] as? [String] ?? [] }
    /// Kurzform für den Coach: „Hähnchen-Curry (520 kcal, 45 g Eiweiß pro Portion)“
    var recipeLine: String {
        let n = [num("kcal").map { "\($0.whole) kcal" }, num("protein").map { "\($0.whole) g Eiweiß" }].compactMap { $0 }
        return (text("title") ?? "") + (n.isEmpty ? "" : " (\(n.joined(separator: ", ")) pro Portion)")
    }
}

private struct RecipeTile: View {
    let entries: [Entry]
    var body: some View {
        TileCard(module: RecipeModule()) {
            Text("\(entries.count) Rezepte").font(.headline)
            if let last = entries.max(by: { $0.updated < $1.updated }) {
                Text(last.text("title") ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

/// Laufende Reel-Aufträge (Reelkoch-id → Link), überstehen das Schließen der App
private enum RecipeJobs {
    static var all: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: "recipeJobs") as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "recipeJobs") }
    }
}

private struct RecipeList: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var search = ""
    @State private var jobs = RecipeJobs.all
    @State private var jobStatus: [String: String] = [:]
    @State private var error: String?
    @State private var addLink = false
    @State private var addText = false
    @State private var fromReelkoch = false

    var body: some View {
        let list = entries.filter { search.isEmpty || ($0.text("title") ?? "").localizedCaseInsensitiveContains(search) }
            .sorted { ($0.text("title") ?? "") < ($1.text("title") ?? "") }
        List {
            if !jobs.isEmpty {
                Section("Wird erstellt") {
                    ForEach(jobs.keys.sorted(), id: \.self) { id in
                        HStack {
                            ProgressView()
                            VStack(alignment: .leading) {
                                Text(jobs[id] ?? "").font(.caption).lineLimit(1)
                                Text(jobStatus[id] ?? String(localized: "wartet")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        let keys = jobs.keys.sorted()
                        for i in idx { jobs[keys[i]] = nil }
                        RecipeJobs.all = jobs
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Section {
                ForEach(list) { e in
                    NavigationLink { RecipeView(entry: e) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.text("title") ?? "–").font(.headline)
                            if let k = e.num("kcal") {
                                Text("\(k.whole) kcal · \((e.num("protein") ?? 0).whole) g Eiweiß pro Portion").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { idx in idx.map { list[$0] }.forEach { state.delete($0, context) } }
            } footer: {
                if entries.isEmpty {
                    Text("Füge oben rechts einen Reel-Link (Facebook, Instagram, TikTok) oder einen Rezepttext ein. Dein Coach schlägt dir dann Rezepte aus deiner Sammlung vor, die zu deinem Tag passen.")
                }
            }
        }
        .searchable(text: $search, prompt: Text("Rezept suchen"))
        .toolbar {
            Menu {
                Button("Link einfügen", systemImage: "link") { addLink = true }
                if state.reelkochAvailable {
                    Button("Aus Reelkoch übernehmen", systemImage: "square.and.arrow.down") { fromReelkoch = true }
                }
                if state.aiAvailable { Button("Text oder Foto einfügen", systemImage: "doc.text.image") { addText = true } }
            } label: { Image(systemName: "plus") }
            .disabled(state.demo)
        }
        .sheet(isPresented: $addLink) { ReelLinkSheet { id, url in jobs[id] = url; RecipeJobs.all = jobs } }
        .sheet(isPresented: $addText) { RecipeTextSheet() }
        .sheet(isPresented: $fromReelkoch) { ReelkochSheet { id, url in jobs[id] = url; RecipeJobs.all = jobs } }
        .task(id: jobs.count) { await poll() }
    }

    /// Laufende Aufträge alle paar Sekunden abfragen, fertige Rezepte speichern
    private func poll() async {
        while !jobs.isEmpty && !Task.isCancelled {
            for id in jobs.keys.sorted() {
                do {
                    let r = try await state.api.object("GET", "/api/recipes/reel/\(id)?nutrition=\(state.aiConsent ? 1 : 0)")
                    let status = r["status"] as? String ?? ""
                    if var recipe = r["recipe"] as? [String: Any] {
                        if recipe["source"] == nil { recipe["source"] = jobs[id] }
                        context.upsert(id: "reel-\(id)", module: "recipes", date: Day.today, values: recipe, dirty: true)
                        state.changed(context)
                        jobs[id] = nil
                    } else if status == "Fehler" {
                        error = String(localized: "Rezept konnte nicht erstellt werden: \(r["fehler"] as? String ?? "")")
                        jobs[id] = nil
                    } else {
                        jobStatus[id] = status
                    }
                } catch {
                    self.error = error.localizedDescription
                }
            }
            RecipeJobs.all = jobs
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

/// Link einfügen: Reel/Video → Auftrag bei Reelkoch, Rezeptseite → Rezept sofort (eingebettete Rezeptdaten, sonst Claude)
private struct ReelLinkSheet: View {
    let added: (String, String) -> Void
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
                    Button("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard") { url = UIPasteboard.general.string ?? url }
                    if let error { Text(error).foregroundStyle(.red) }
                } footer: {
                    Text("Reel oder Video (Facebook, Instagram, TikTok, YouTube): Reelkoch auf deinem Server liest das Rezept aus Beschreibung, Ton und Bildern – meist 1–2 Minuten, du kannst die App solange schließen. Rezeptseite (z. B. Chefkoch): Das Rezept wird direkt übernommen; fehlen dort Rezeptdaten, liest Claude die Seite (nur mit deiner Zustimmung).")
                }
            }
            .navigationTitle("Link einfügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") { send() }.disabled(busy || !url.lowercased().hasPrefix("http"))
                }
            }
        }
    }

    private func send() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let r = try await state.api.object("POST", "/api/recipes/link", json: [
                    "url": url.trimmingCharacters(in: .whitespaces), "ai": state.aiConsent,
                    "lang": Locale.current.language.languageCode?.identifier ?? "de",
                ])
                if let recipe = r["recipe"] as? [String: Any] {
                    context.insert(Entry(module: "recipes", values: recipe))
                    state.changed(context)
                    dismiss()
                } else if let id = r["id"] as? String {
                    added(id, url)
                    dismiss()
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// Fertige Rezepte aus Reelkoch übernehmen
private struct ReelkochSheet: View {
    let added: (String, String) -> Void
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Entry> { $0.module == "recipes" }) private var existing: [Entry]
    @State private var list: [[String: Any]] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(list.indices, id: \.self) { i in
                    let id = list[i]["id"] as? String ?? "", have = existing.contains { $0.id == "reel-\(id)" && !$0.deleted }
                    Button {
                        added(id, list[i]["url"] as? String ?? "")
                        list.remove(at: i)
                    } label: {
                        HStack {
                            Text(list[i]["title"] as? String ?? "–")
                            Spacer()
                            Image(systemName: have ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(have ? .green : .accentColor)
                        }
                    }
                    .disabled(have)
                }
            }
            .navigationTitle("Aus Reelkoch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .task {
                do {
                    let data = try await state.api.call("GET", "/api/recipes/reelkoch")
                    list = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

/// Rezepttext einfügen (z. B. Beschreibung eines Reels) → Claude strukturiert ihn
private struct RecipeTextSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var askConsent = false
    @State private var photo: UIImage?  // Kochbuchseite, Rezeptkarte, Screenshot
    @State private var pick: PhotosPickerItem?
    @State private var camera = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let photo {
                        HStack {
                            Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 160)
                            Spacer()
                            Button { self.photo = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                        }
                    }
                    PhotosPicker("Foto oder Screenshot auswählen", selection: $pick, matching: .images)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Foto aufnehmen", systemImage: "camera") { camera = true }
                    }
                } header: { Text("Foto (z. B. Kochbuchseite)") }
                Section {
                    TextEditor(text: $text).frame(minHeight: photo == nil ? 200 : 80)
                    Button("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard") { text = UIPasteboard.general.string ?? text }
                    if let error { Text(error).foregroundStyle(.red) }
                } header: { Text(photo == nil ? "Rezepttext" : "Hinweis (optional)") } footer: {
                    Text("Claude macht daraus ein Rezept mit Zutaten, Schritten und geschätzten Nährwerten pro Portion.")
                }
            }
            .onChange(of: pick) {
                Task { if let d = try? await pick?.loadTransferable(type: Data.self) { photo = UIImage(data: d) } }
            }
            .sheet(isPresented: $camera) { CameraPicker(image: $photo).ignoresSafeArea() }
            .navigationTitle("Text oder Foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? LocalizedStringKey("Wird erstellt …") : "Erstellen") {
                        if state.aiConsent { send() } else { askConsent = true }
                    }
                    .disabled(busy || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil))
                }
            }
            .alert("Text an Claude senden?", isPresented: $askConsent) {
                Button("Zustimmen") { state.aiConsent = true; send() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Der Rezepttext bzw. das Foto wird über deinen Server an die Claude API (Anthropic) gesendet.")
            }
        }
    }

    private func send() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let r = try await state.api.object("POST", "/api/ai/recipe", json: [
                    "text": text, "lang": Locale.current.language.languageCode?.identifier ?? "de",
                    "image": photo?.jpeg(maxSide: 1600, quality: 0.75)?.base64EncodedString() ?? "",
                ])
                if let e = r["error"] as? String { error = e; return }
                context.insert(Entry(module: "recipes", values: r))
                state.changed(context)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// Rezept ansehen: Nährwerte, Zutaten, Schritte, Quelle – und „Gegessen“
private struct RecipeView: View {
    let entry: Entry
    @State private var eat = false
    @State private var pick: PhotosPickerItem?
    @State private var camera = false
    @State private var shot: UIImage?
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                // Eigenes Foto (auf dem iPhone verkleinert gespeichert) vor dem Bild der Rezeptseite
                if let b = entry.text("photo"), let d = Data(base64Encoded: b), let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFill().frame(maxHeight: 220).clipped().listRowInsets(EdgeInsets())
                } else if let img = entry.text("image"), let u = URL(string: img) {
                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                        .frame(maxHeight: 220).clipped().listRowInsets(EdgeInsets())
                }
                HStack {
                    PhotosPicker(selection: $pick, matching: .images) { Label(entry.text("photo") == nil ? "Foto hinzufügen" : "Foto ändern", systemImage: "photo") }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Spacer()
                        Button("Aufnehmen", systemImage: "camera") { camera = true }
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
                Text(entry.text("title") ?? "").font(.title2.bold())
                let info = [entry.text("servings").flatMap { $0.isEmpty ? nil : String(localized: "\($0) Portionen") },
                            entry.text("time").flatMap { $0.isEmpty ? nil : $0 }].compactMap { $0 }
                if !info.isEmpty { Text(info.joined(separator: " · ")).foregroundStyle(.secondary) }
                if let k = entry.num("kcal") {
                    Text("Pro Portion: \(k.whole) kcal · Eiweiß \((entry.num("protein") ?? 0).whole) g · KH \((entry.num("carbs") ?? 0).whole) g · Fett \((entry.num("fat") ?? 0).whole) g")
                        .font(.callout)
                    Text("Geschätzte Werte – keine ärztliche Beratung.").font(.caption2).foregroundStyle(.secondary)
                }
                Button("Gegessen", systemImage: "fork.knife") { eat = true }.bold()
            }
            Section("Zutaten") {
                ForEach(Array(entry.ingredients.enumerated()), id: \.offset) { _, z in
                    HStack(alignment: .top) {
                        Text(z.amount).bold().frame(minWidth: 70, alignment: .leading)
                        Text(z.name)
                    }
                }
            }
            Section("Zubereitung") {
                ForEach(Array(entry.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top) { Text("\(i + 1).").bold(); Text(s) }
                }
            }
            if let n = entry.text("notes"), !n.isEmpty { Section("Hinweise") { Text(n) } }
            if let s = entry.text("source"), let url = URL(string: s) {
                Section { Link("Original ansehen", destination: url) }
            }
        }
        .themed()
        .navigationTitle(Text(entry.text("title") ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $eat) { EatSheet(entry: entry) }
        .onChange(of: pick) { Task { if let d = try? await pick?.loadTransferable(type: Data.self) { setPhoto(UIImage(data: d)) } } }
        .onChange(of: shot) { setPhoto(shot) }
        .sheet(isPresented: $camera) { CameraPicker(image: $shot).ignoresSafeArea() }
    }

    /// Foto verkleinert im Eintrag speichern (geht mit Abgleich und Verschlüsselung mit)
    private func setPhoto(_ img: UIImage?) {
        guard let jpg = img?.jpeg(maxSide: 900, quality: 0.6) else { return }
        var v = entry.values
        v["photo"] = jpg.base64EncodedString()
        entry.values = v
        entry.touch()
        state.changed(context)
    }
}

/// Portionen eines Rezepts in die Ernährung eintragen
private struct EatSheet: View {
    let entry: Entry
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var portions = 1.0
    @State private var meal = Meal.now

    var body: some View {
        NavigationStack {
            Form {
                Stepper("\(portions.short) Portionen", value: $portions, in: 0.5...6, step: 0.5)
                Picker("Mahlzeit", selection: $meal) { ForEach(Meal.allCases) { Text($0.title).tag($0) } }
                if entry.num("kcal") == nil {
                    Text("Für dieses Rezept gibt es keine Nährwerte – es wird nur der Name eingetragen.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(((entry.num("kcal") ?? 0) * portions).whole) kcal").bold()
                }
            }
            .navigationTitle("Gegessen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Eintragen") { save() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let name = (entry.text("title") ?? "") + (portions == 1 ? "" : " (\(portions.short) Portionen)")
        var v: [String: Any] = ["meal": meal.rawValue, "name": name]
        for k in ["kcal", "protein", "carbs", "fat"] { if let x = entry.num(k) { v[k] = x * portions } }
        context.insert(Entry(module: "nutrition", values: v))
        if state.healthEnabled {
            Health.saveMeal(name: name, kcal: v["kcal"] as? Double ?? 0, protein: v["protein"] as? Double ?? 0,
                            carbs: v["carbs"] as? Double ?? 0, fat: v["fat"] as? Double ?? 0)
        }
        state.changed(context)
        dismiss()
    }
}
