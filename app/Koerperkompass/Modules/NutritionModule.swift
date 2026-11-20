import Charts
import PhotosUI
import SwiftUI

/// Ernährung: Tagesziele, Ringe für Eiweiß/Kohlenhydrate/Fett, 7-Tage-Diagramm, Tagebuch, optional Foto.
struct NutritionModule: AppModule {
    let id = "nutrition"
    let name: LocalizedStringResource = "Ernährung"
    let symbol = "fork.knife"
    let fields = [
        Field(key: "kcal", name: "Energie", unit: "kcal", agg: .sum),
        Field(key: "protein", name: "Eiweiß", unit: "g", agg: .sum),
        Field(key: "carbs", name: "Kohlenhydrate", unit: "g", agg: .sum),
        Field(key: "fat", name: "Fett", unit: "g", agg: .sum),
    ]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(NutritionTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(NutritionDetail(entries: entries)) }
}

enum Meal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    /// Übliche Uhrzeit, wenn keine genannt wurde
    var defaultTime: String { ["breakfast": "08:00", "lunch": "12:30", "snack": "15:30", "dinner": "18:30"][rawValue] ?? "12:00" }
    var title: LocalizedStringResource {
        switch self {
        case .breakfast: "Frühstück"
        case .lunch: "Mittagessen"
        case .dinner: "Abendessen"
        case .snack: "Snack"
        }
    }
}

/// Summen eines Tages
private func totals(_ entries: [Entry], _ day: String) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
    var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
    for e in entries where e.date == day {
        kcal += e.num("kcal") ?? 0
        protein += e.num("protein") ?? 0
        carbs += e.num("carbs") ?? 0
        fat += e.num("fat") ?? 0
    }
    return (kcal, protein, carbs, fat)
}

private struct MacroRings: View {
    let entries: [Entry]
    let day: String
    var size: CGFloat = 44
    @Environment(AppState.self) private var state
    var body: some View {
        let t = totals(entries, day), p = state.profile
        HStack(spacing: size / 3) {
            Ring(progress: t.protein / max(p.protein, 1), color: .blue, label: "Eiweiß", size: size)
            Ring(progress: t.carbs / max(p.carbs, 1), color: .orange, label: "Kohlenh.", size: size)
            Ring(progress: t.fat / max(p.fat, 1), color: .pink, label: "Fett", size: size)
        }
    }
}

private struct NutritionTile: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    var body: some View {
        TileCard(module: NutritionModule()) {
            Text("\(totals(entries, Day.today).kcal.whole) / \(state.profile.kcal.whole) kcal").font(.headline)
            MacroRings(entries: entries, day: Day.today, size: 34)
        }
    }
}

private struct NutritionDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var date = Date()
    @State private var adding: Meal?
    @State private var moving: Entry?
    private var day: String { Day.string(date) }

    var body: some View {
        let t = totals(entries, day)
        List {
            Section {
                DatePicker("Tag", selection: $date, in: ...Date(), displayedComponents: .date)
                VStack(spacing: 12) {
                    Text("\(t.kcal.whole) von \(state.profile.kcal.whole) kcal").font(.title2.bold())
                    MacroRings(entries: entries, day: day, size: 64)
                    Text("Eiweiß \(t.protein.whole)/\(state.profile.protein.whole) g · KH \(t.carbs.whole)/\(state.profile.carbs.whole) g · Fett \(t.fat.whole)/\(state.profile.fat.whole) g")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            MealInputSection(day: day, entries: entries)
            Section {
                NavigationLink("Mein Plan – Ziele, BMI und Makros") { GoalsView() }
            }
            Section("Letzte 7 Tage") {
                Chart {
                    ForEach(Day.last(7), id: \.self) { d in
                        BarMark(x: .value("Tag", Day.date(d), unit: .day), y: .value("kcal", totals(entries, d).kcal))
                    }
                    RuleMark(y: .value("Ziel", state.profile.kcal))
                        .lineStyle(StrokeStyle(dash: [4]))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 180)
            }
            let drinks = entries.filter { $0.module == "water" && $0.date == day && !$0.deleted }
            if !drinks.isEmpty {
                Section("Getränke") {
                    EntryRows(entries: drinks) { e in "\(e.text("name") ?? "") · \((e.num("kcal") ?? 0).whole) kcal" }
                }
            }
            ForEach(Meal.allCases) { meal in
                Section {
                    EntryRows(entries: entries.filter { $0.module == "nutrition" && $0.date == day && $0.text("meal") == meal.rawValue },
                              row: { e in "\(e.text("name") ?? "–") · \((e.num("kcal") ?? 0).whole) kcal" },
                              onTap: { moving = $0 })
                    Button("Hinzufügen", systemImage: "plus") { adding = meal }
                } header: { Text(meal.title) }
            }
        }
        .sheet(item: $adding) { meal in FoodEditor(meal: meal, day: day) }
        // Eintrag antippen → in eine andere Mahlzeit verschieben
        .confirmationDialog("Verschieben nach …", isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }), titleVisibility: .visible) {
            ForEach(Meal.allCases) { meal in
                Button(String(localized: meal.title)) {
                    if let e = moving {
                        var v = e.values
                        v["meal"] = meal.rawValue
                        e.values = v
                        e.touch()
                        state.changed(context)
                    }
                    moving = nil
                }
            }
        } message: { Text(moving?.text("name") ?? "") }
    }
}

/// Eintrag anlegen – von Hand oder per Foto (Schätzung über Claude, falls auf dem Server eingerichtet)
private struct FoodEditor: View {
    let meal: Meal
    let day: String
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var image: UIImage?
    @State private var pick: PhotosPickerItem?
    @State private var camera = false
    @State private var askConsent = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bezeichnung", text: $name)
                    TextField("Kalorien (kcal)", value: $kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Eiweiß (g)", value: $protein, format: .number).keyboardType(.decimalPad)
                    TextField("Kohlenhydrate (g)", value: $carbs, format: .number).keyboardType(.decimalPad)
                    TextField("Fett (g)", value: $fat, format: .number).keyboardType(.decimalPad)
                }
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                    }
                    PhotosPicker("Foto auswählen", selection: $pick, matching: .images)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Foto aufnehmen", systemImage: "camera") { camera = true }
                    }
                    if image != nil && state.aiAvailable {
                        Button(busy ? LocalizedStringKey("Schätze …") : "Nährwerte schätzen", systemImage: "sparkles") {
                            if state.aiConsent { estimate() } else { askConsent = true }
                        }
                        .disabled(busy)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                } header: { Text("Foto (optional)") } footer: {
                    if state.aiAvailable { Text("Die Schätzung ist nur ein Anhaltspunkt – bitte prüfen.") }
                }
            }
            .navigationTitle(Text(meal.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern", action: save).disabled(name.isEmpty && kcal == nil) }
            }
            .onChange(of: pick) {
                Task {
                    if let data = try? await pick?.loadTransferable(type: Data.self) { image = UIImage(data: data) }
                }
            }
            .sheet(isPresented: $camera) { CameraPicker(image: $image).ignoresSafeArea() }
            .alert("Foto an Claude senden?", isPresented: $askConsent) {
                Button("Zustimmen") { state.aiConsent = true; estimate() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Das Foto wird über deinen Server an die Claude API (Anthropic) gesendet, um die Nährwerte zu schätzen. Du kannst die Zustimmung in den Einstellungen widerrufen.")
            }
        }
    }

    private func estimate() {
        guard let jpeg = image?.jpeg(maxSide: 1024, quality: 0.7) else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let r = try await state.api.object("POST", "/api/ai/photo", json: ["image": jpeg.base64EncodedString(), "lang": Locale.current.language.languageCode?.identifier ?? "de"])
                if let n = r["name"] as? String, name.isEmpty { name = n }
                kcal = (r["kcal"] as? NSNumber)?.doubleValue
                protein = (r["protein"] as? NSNumber)?.doubleValue
                carbs = (r["carbs"] as? NSNumber)?.doubleValue
                fat = (r["fat"] as? NSNumber)?.doubleValue
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        var v: [String: Any] = ["meal": meal.rawValue, "name": name]
        for (k, x) in [("kcal", kcal), ("protein", protein), ("carbs", carbs), ("fat", fat)] { if let x { v[k] = x } }
        if let thumb = image?.jpeg(maxSide: 320, quality: 0.5) { v["photo"] = thumb.base64EncodedString() }
        context.insert(Entry(module: "nutrition", date: day, values: v))
        if state.healthEnabled && day == Day.today {
            Health.saveMeal(name: name, kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
        }
        state.changed(context)
        dismiss()
    }
}

/// Kamera über UIImagePickerController
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

extension UIImage {
    /// Verkleinert und als JPEG – spart Speicher und Übertragung
    func jpeg(maxSide: CGFloat, quality: CGFloat) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            .jpegData(compressionQuality: quality)
    }
}
