import SwiftUI

/// Rückmeldung nach einer Trainingseinheit
enum Feedback: String, CaseIterable {
    case easy, ok, hard
    var emoji: String { ["😌", "💪", "🥵"][Self.allCases.firstIndex(of: self)!] }
    var title: LocalizedStringResource {
        switch self {
        case .easy: "Zu leicht"
        case .ok: "Genau richtig"
        case .hard: "Zu schwer"
        }
    }
    var color: Color { [Color.green, Theme.orange, Color.red][Self.allCases.firstIndex(of: self)!] }
}

/// Trainingsverlauf der letzten 4 Wochen als Text (für Claude): Einheiten mit Rückmeldung und eingetragene Sätze
func trainingHistory(_ entries: [Entry]) -> String {
    let from = Day.last(28)[0]
    let live = entries.filter { !$0.deleted && $0.date >= from }
    let sessions = live.filter { $0.module == "training" }.sorted { $0.date < $1.date }.map { e in
        var line = "\(e.date): \(e.text("name") ?? "Training"), \((e.num("minutes") ?? 0).whole) min"
        if let f = e.text("feedback").flatMap { Feedback(rawValue: $0) } { line += ", Rückmeldung: \(String(localized: f.title))" }
        return line
    }
    let sets = live.filter { $0.module == "exercises" }.sorted { $0.date < $1.date }.map { e in
        "\(e.date): \(e.text("exercise") ?? "") \((e.num("reps") ?? 0).whole) Wdh." + (e.num("weight").map { " mit \($0.short) kg" } ?? "")
    }
    return (["Einheiten:"] + (sessions.isEmpty ? ["keine"] : sessions) + ["Sätze:"] + (sets.isEmpty ? ["keine"] : sets)).joined(separator: "\n")
}

/// Einfache Steigerungsregel ohne Claude: richtet sich nach der letzten Rückmeldung
func localHint(_ entries: [Entry]) -> LocalizedStringResource? {
    let last = entries.filter { $0.module == "training" && !$0.deleted && $0.text("feedback") != nil && $0.date < Day.today }
        .max { $0.date < $1.date }
    switch last?.text("feedback").flatMap { Feedback(rawValue: $0) } {
    case .easy: return "Letztes Mal zu leicht: Nimm heute etwas mehr Gewicht (z. B. +2,5 kg) oder mach 2 Wiederholungen bzw. einen Satz mehr."
    case .ok: return "Letztes Mal genau richtig: Gleiche Belastung – versuch bei jeder Übung 1 Wiederholung mehr."
    case .hard: return "Letztes Mal zu schwer: Heute etwas weniger Gewicht oder einen Satz weniger und längere Pausen."
    case nil: return nil
    }
}

/// Rückmeldung zur heutigen Einheit abgeben
struct FeedbackButtons: View {
    let entry: Entry
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context

    var body: some View {
        let current = entry.text("feedback").flatMap { Feedback(rawValue: $0) }
        VStack(alignment: .leading, spacing: 8) {
            Text("Wie war das Training?").font(.subheadline.bold())
            HStack(spacing: 8) {
                ForEach(Feedback.allCases, id: \.self) { f in
                    Button {
                        var v = entry.values
                        v["feedback"] = f.rawValue
                        entry.values = v
                        entry.touch()
                        state.changed(context)
                    } label: {
                        VStack(spacing: 2) {
                            Text(f.emoji).font(.title2)
                            Text(f.title).font(.caption2.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(f.color.opacity(current == f ? 0.45 : 0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// „Nächste Einheit mit Claude anpassen“ – wertet Verlauf und Rückmeldungen aus
struct CoachButton: View {
    let session: PlanDay
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var error: String?
    @State private var askConsent = false

    var body: some View {
        Group {
            Button(busy ? LocalizedStringKey("Dein Coach plant die Einheit …") : "Einheit für mich anpassen", systemImage: "sparkles") {
                // Auf dem iPhone (Apple Intelligence) ohne Datenweitergabe, sonst Claude mit Zustimmung
                if OnDevice.available || state.aiConsent { run() } else { askConsent = true }
            }
            .disabled(busy)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
            .alert("Daten an Claude senden?", isPresented: $askConsent) {
                Button("Zustimmen") { state.aiConsent = true; run() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Dein Profil, die geplante Einheit und dein Trainingsverlauf der letzten 4 Wochen (Einheiten, Rückmeldungen, Sätze) werden über deinen Server an die Claude API (Anthropic) gesendet.")
            }
    }

    private func run() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            if OnDevice.available {
                if let s = await OnDevice.nextSession(session, history: trainingHistory(entries), profile: state.profile.aiText) {
                    state.profile.suggestion = s
                    return
                }
                if !state.aiAvailable { error = String(localized: "Anpassung gerade nicht möglich – versuch es gleich noch einmal."); return }
            }
            do {
                let r = try await state.api.object("POST", "/api/ai/next", json: [
                    "profile": state.profile.aiText, "plan": state.profile.plan?.name ?? "",
                    "session": "\(session.title): " + session.exercises.joined(separator: "; "),
                    "history": trainingHistory(entries), "lang": Locale.current.language.languageCode?.identifier ?? "de",
                ])
                let exercises = r["exercises"] as? [String] ?? []
                guard !exercises.isEmpty else { throw API.Failure(message: String(localized: "Antwort nicht verwertbar")) }
                state.profile.suggestion = Suggestion(day: Day.today,
                                                      session: PlanDay(title: r["title"] as? String ?? session.title, exercises: exercises),
                                                      note: r["note"] as? String ?? "")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
