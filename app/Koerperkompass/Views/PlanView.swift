import SwiftUI

/// Trainingsprogramme: aktuelles Programm, Vorlagen und – mit Claude auf dem Server – ein persönliches 4-Wochen-Programm.
struct PlanView: View {
    @Environment(AppState.self) private var state
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
            Section {
                HStack {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                        Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) {
                            if weekdays.contains(d) { weekdays.remove(d) } else { weekdays.insert(d) }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .tint(weekdays.contains(d) ? .orange : .gray)
                    }
                }
            } header: { Text("Trainingstage") } footer: {
                Text("\(weekdays.count) × pro Woche. Die übrigen Tage sind Ruhetage.")
            }
            Section("Vorlagen") {
                ForEach(planTemplates, id: \.name) { t in
                    NavigationLink { PlanDetail(plan: t, weekdays: weekdays) } label: {
                        VStack(alignment: .leading) {
                            Text(t.name).font(.headline)
                            Text("\(t.level) · \(t.days.count) Trainingstage im Wechsel").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if state.aiAvailable {
                Section {
                    TextField("Wunsch, z. B. „Muskelaufbau, nur Kurzhanteln, 40 min“", text: $wish, axis: .vertical)
                    Button(busy ? LocalizedStringKey("Programm wird erstellt …") : "Programm mit Claude erstellen", systemImage: "sparkles") {
                        if state.aiConsent { generate() } else { askConsent = true }
                    }
                    .disabled(busy)
                    if let error { Text(error).foregroundStyle(.red) }
                    if let generated {
                        NavigationLink { PlanDetail(plan: generated, weekdays: weekdays) } label: {
                            Label(generated.name, systemImage: "sparkles")
                        }
                    }
                } header: { Text("Persönliches Programm") } footer: {
                    Text("Claude erstellt ein 4-Wochen-Programm aus deinem Wunsch und deinem Profil. Keine ärztliche Beratung – bei Beschwerden bitte abklären lassen.")
                }
            }
        }
        .navigationTitle("Trainingsprogramme")
        .onAppear { if let p = state.profile.plan { weekdays = Set(p.weekdays) } }
        .alert("Daten an Claude senden?", isPresented: $askConsent) {
            Button("Zustimmen") { state.aiConsent = true; generate() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dein Wunsch und dein Profil (Ziel, Alter, Größe, Gewicht) werden über deinen Server an die Claude API (Anthropic) gesendet.")
        }
    }

    private func generate() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let r = try await state.api.object("POST", "/api/ai/plan", json: [
                    "wish": wish, "days": max(weekdays.count, 1), "profile": state.profile.aiText,
                    "lang": Locale.current.language.languageCode?.identifier ?? "de",
                ])
                let days = (r["days"] as? [[String: Any]] ?? []).map {
                    PlanDay(title: $0["title"] as? String ?? "", exercises: $0["exercises"] as? [String] ?? [])
                }
                guard !days.isEmpty else { throw API.Failure(message: String(localized: "Antwort nicht verwertbar")) }
                generated = TrainingPlan(name: r["name"] as? String ?? String(localized: "Mein Programm"), level: String(localized: "Persönlich"), days: days)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Programm ansehen und starten
private struct PlanDetail: View {
    let plan: TrainingPlan
    let weekdays: Set<Int>
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(plan.days.indices, id: \.self) { i in
                Section {
                    ForEach(plan.days[i].exercises, id: \.self) { Text($0) }
                } header: {
                    HStack {
                        Text(plan.days[i].title)
                        Spacer()
                        Text("+\(planXP) XP").foregroundStyle(.orange)
                    }
                }
            }
            Section {
                Button("Programm starten (4 Wochen)") {
                    var p = plan
                    p.weekdays = weekdays.sorted()
                    p.start = Day.today
                    p.weeks = 4
                    state.profile.plan = p
                    dismiss()
                }
                .bold()
                .disabled(weekdays.isEmpty)
            } footer: {
                Text("Die Trainingstage kommen reihum dran. Ein laufendes Programm wird ersetzt.")
            }
        }
        .navigationTitle(plan.name)
    }
}
