import SwiftData
import SwiftUI

/// Tab „Training“: heutige Einheit, fertige Programme als Karten, eigenes Programm mit Claude, Übungen und Verlauf.
struct TrainingView: View {
    @Environment(AppState.self) private var state
    @Query private var entries: [Entry]

    var body: some View {
        let p = QuestProgress(entries, state.profile)
        NavigationStack {
            List {
                if let plan = state.profile.plan {
                    Section {
                        HStack(spacing: 14) {
                            IconBadge(symbol: plan.symbol ?? "figure.strengthtraining.traditional", module: "training", size: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.name).font(.title3.bold())
                                Text("\(p.planDone) Einheiten · bis \(Day.date(plan.end).formatted(.dateTime.day().month()))")
                                    .font(.caption).foregroundStyle(.secondary)
                                ProgressView(value: min(Double(Day.date(Day.today).timeIntervalSince(Day.date(plan.start))) / Double(plan.weeks * 7 * 86400), 1))
                                    .tint(.purple)
                            }
                        }
                    }
                }
                TodayCard(progress: p)

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(recommendedPlans(state.profile), id: \.name) { t in
                                NavigationLink { PlanDetail(plan: t) } label: { PlanCard(plan: t) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: { Text("Empfohlen für dich") } footer: {
                    Text("Passend zu deinem Ziel und deiner Aktivität. Nach jeder Einheit gibst du Rückmeldung – daraus wird die nächste Einheit angepasst.")
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(planTemplates, id: \.name) { t in
                                NavigationLink { PlanDetail(plan: t) } label: { PlanCard(plan: t) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: { Text("Alle Programme") }

                Section {
                    NavigationLink { ExerciseLibraryView() } label: { Label("Übungsbibliothek", systemImage: "figure.strengthtraining.traditional") }
                    NavigationLink { PlanView() } label: { Label("Persönliches Programm mit Claude", systemImage: "sparkles") }
                    NavigationLink {
                        ExerciseModule().detail(entries.filter { $0.module == "exercises" && !$0.deleted }).navigationTitle(Text("Übungen")).themed()
                    } label: { Label("Übungen & Sätze", systemImage: "chart.line.uptrend.xyaxis") }
                    NavigationLink {
                        TrainingModule().detail(entries.filter { $0.module == "training" && !$0.deleted }).navigationTitle(Text("Trainingsverlauf")).themed()
                    } label: { Label("Trainingsverlauf", systemImage: "calendar") }
                }
            }
            .themed()
            .navigationTitle("Training")
        }
    }
}

/// Programmkarte mit Verlauf in der Farbe des Niveaus
struct PlanCard: View {
    let plan: TrainingPlan
    var body: some View {
        let c = levelColor(plan.level)
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: plan.symbol ?? "figure.strengthtraining.traditional").font(.system(size: 34, weight: .bold))
            Spacer()
            Text(plan.level.uppercased()).font(.caption2.bold()).opacity(0.85)
            Text(plan.name).font(.headline).lineLimit(2)
            Text(plan.info ?? "").font(.caption).lineLimit(3).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(width: 190, height: 230, alignment: .topLeading)
        .background(LinearGradient(colors: [c, c.opacity(0.45), .black.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: c.opacity(0.4), radius: 8, y: 4)
    }
}

/// Wochentage auswählen (Mo–So)
struct WeekdayPicker: View {
    @Binding var days: Set<Int>
    var body: some View {
        HStack(spacing: 6) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) {
                    if days.contains(d) { days.remove(d) } else { days.insert(d) }
                }
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(days.contains(d) ? Color.purple : Color.white.opacity(0.08), in: Circle())
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }
        }
    }
}

/// Programm ansehen, Trainingstage wählen und starten
struct PlanDetail: View {
    let plan: TrainingPlan
    @State private var weekdays: Set<Int>
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    init(plan: TrainingPlan) {
        self.plan = plan
        _weekdays = State(initialValue: Set(plan.weekdays))
    }

    var body: some View {
        List {
            Section {
                PlanCard(plan: plan).frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
            ForEach(plan.days.indices, id: \.self) { i in
                Section {
                    ForEach(plan.days[i].exercises, id: \.self) { Label($0, systemImage: "checkmark.circle") }
                } header: {
                    HStack {
                        Text(plan.days[i].title)
                        Spacer()
                        Text("+\(planXP) XP").foregroundStyle(.orange)
                    }
                }
            }
            Section {
                WeekdayPicker(days: $weekdays).padding(.vertical, 4)
            } header: { Text("Trainingstage") } footer: {
                Text("\(weekdays.count) × pro Woche. Die übrigen Tage sind Ruhetage. Die Trainingstage kommen reihum dran.")
            }
            Section {
                Button {
                    var p = plan
                    p.weekdays = weekdays.sorted()
                    p.start = Day.today
                    p.weeks = 4
                    state.profile.plan = p
                    dismiss()
                } label: {
                    Text("Programm starten (4 Wochen)").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.purple)
                .disabled(weekdays.isEmpty)
                .listRowBackground(Color.clear)
            } footer: {
                if state.profile.plan != nil { Text("Ein laufendes Programm wird ersetzt.") }
            }
        }
        .themed()
        .navigationTitle(plan.name)
    }
}

/// Aktuelles Programm verwalten und ein persönliches Programm mit Claude erstellen
struct PlanView: View {
    @Environment(AppState.self) private var state
    @Query private var entries: [Entry]
    @State private var weekdays: Set<Int> = [2, 4, 6]
    @State private var wish = ""
    @State private var generated: TrainingPlan?
    @State private var busy = false
    @State private var error: String?
    @State private var askConsent = false

    var body: some View {
        List {
            if let plan = state.profile.plan {
                Section("Aktuelles Programm") {
                    LabeledContent(plan.name, value: plan.level)
                    LabeledContent("Zeitraum", value: "\(Day.date(plan.start).formatted(date: .abbreviated, time: .omitted)) – \(Day.date(plan.end).formatted(date: .abbreviated, time: .omitted))")
                    Toggle("Strafpunkte bei verpasstem Training", isOn: Binding(
                        get: { state.profile.penalties == true }, set: { state.profile.penalties = $0 }))
                    Button("Programm beenden", role: .destructive) { state.profile.plan = nil }
                }
            }
            if state.aiAvailable {
                Section {
                    TextField("Wunsch, z. B. „Muskelaufbau, nur Kurzhanteln, 40 min“", text: $wish, axis: .vertical)
                    WeekdayPicker(days: $weekdays).padding(.vertical, 4)
                    Button(busy ? LocalizedStringKey("Programm wird erstellt …") : "Programm mit Claude erstellen", systemImage: "sparkles") {
                        if state.aiConsent { generate() } else { askConsent = true }
                    }
                    .disabled(busy)
                    if let error { Text(error).foregroundStyle(.red) }
                    if let generated {
                        NavigationLink { PlanDetail(plan: generated) } label: { Label(generated.name, systemImage: "sparkles") }
                    }
                } header: { Text("Persönliches Programm") } footer: {
                    Text("Claude erstellt ein 4-Wochen-Programm aus deinem Wunsch, deinem Profil und deinen bisherigen Rückmeldungen. Keine ärztliche Beratung – bei Beschwerden bitte abklären lassen.")
                }
            } else {
                Section {
                    Text("Für persönliche Programme kann auf deinem Server ein Claude-API-Key hinterlegt werden. Bis dahin findest du fertige Programme im Tab „Training“.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .themed()
        .navigationTitle("Programm")
        .onAppear { if let p = state.profile.plan { weekdays = Set(p.weekdays) } }
        .alert("Daten an Claude senden?", isPresented: $askConsent) {
            Button("Zustimmen") { state.aiConsent = true; generate() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dein Wunsch, dein Profil (Ziel, Alter, Größe, Gewicht) und dein Trainingsverlauf (Einheiten, Rückmeldungen, Sätze) werden über deinen Server an die Claude API (Anthropic) gesendet.")
        }
    }

    private func generate() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let r = try await state.api.object("POST", "/api/ai/plan", json: [
                    "wish": wish, "days": max(weekdays.count, 1), "profile": state.profile.aiText, "history": trainingHistory(entries),
                    "lang": Locale.current.language.languageCode?.identifier ?? "de",
                ])
                let days = (r["days"] as? [[String: Any]] ?? []).map {
                    PlanDay(title: $0["title"] as? String ?? "", exercises: $0["exercises"] as? [String] ?? [])
                }
                guard !days.isEmpty else { throw API.Failure(message: String(localized: "Antwort nicht verwertbar")) }
                generated = TrainingPlan(name: r["name"] as? String ?? String(localized: "Mein Programm"), level: String(localized: "Persönlich"),
                                         weekdays: weekdays.sorted(), days: days, symbol: "sparkles", info: wish)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
