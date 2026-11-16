import SwiftData
import SwiftUI

/// Gesprächsprotokoll für die Testphase: hilft, die Coaches nachzuschärfen.
/// Gespeichert als Einträge im Modul „coachlog“ – nur auf dem iPhone und dem eigenen Server. Abschaltbar.
enum CoachLog {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "coachLogOn") as? Bool ?? true }

    /// kind: „training“ oder „gesundheit“; source: „apple“, „haiku“, „claude“ oder „regel“
    static func add(kind: String, persona: String = "", heard: String, reply: String, source: String, ms: Int, extra: [String: Any] = [:]) {
        guard enabled else { return }
        var v: [String: Any] = ["kind": kind, "persona": persona, "heard": heard, "reply": reply, "source": source, "ms": ms,
                                "time": Date().formatted(date: .omitted, time: .standard)]
        v.merge(extra) { $1 }
        let context = ModelContext(sharedContainer)
        context.insert(Entry(module: "coachlog", values: v))
        try? context.save()
    }

    /// Lesbarer Text zum Teilen und Auswerten
    static func text(_ entries: [Entry]) -> String {
        entries.sorted { ($0.date, $0.updated) < ($1.date, $1.updated) }.map { e in
            var line = "[\(e.date) \(e.text("time") ?? "")] \(e.text("kind") ?? "") · \(e.text("persona") ?? "-") · \(e.text("source") ?? "") · \((e.num("ms") ?? 0).whole) ms\n"
            line += "  Ich: \(e.text("heard") ?? "")\n  Coach: \(e.text("reply") ?? "")"
            if let reps = e.num("reps"), reps > 0 {
                line += "\n  Eingetragen: \(e.text("exercise") ?? "") \(reps.whole) Wdh." + ((e.num("weight") ?? 0) > 0 ? " mit \((e.num("weight") ?? 0).short) kg" : "")
                    + ((e.num("rest") ?? 0) > 0 ? ", Pause \((e.num("rest") ?? 0).whole) s" : "")
            }
            return line
        }.joined(separator: "\n\n")
    }
}

/// Hinweis-Leiste in den Coach-Ansichten
struct CoachLogBanner: View {
    @AppStorage("coachLogOn") private var on = true
    var body: some View {
        if on {
            HStack {
                Text("🧪 Testphase: Gespräche werden protokolliert (nur auf deinem iPhone und Server).").font(.caption2)
                Spacer()
                Button("Aus") { on = false }.font(.caption2.bold())
            }
            .padding(8)
            .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }
    }
}

/// Einstellungen → Gesprächsprotokoll
struct CoachLogView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @AppStorage("coachLogOn") private var on = true
    @Query(filter: #Predicate<Entry> { $0.module == "coachlog" && !$0.removed }, sort: \Entry.date, order: .reverse) private var entries: [Entry]

    var body: some View {
        List {
            Section {
                Toggle("Gespräche protokollieren", isOn: $on)
                ShareLink("Protokoll teilen (\(entries.count) Einträge)", item: CoachLog.text(entries))
                    .disabled(entries.isEmpty)
                Button("Protokoll löschen", role: .destructive) {
                    entries.forEach { state.delete($0, context) }
                }
                .disabled(entries.isEmpty)
            } footer: {
                Text("Für die Testphase: Teile das Protokoll (z. B. mit Claude im Chat), um Antworten, Stile und Erkennung zu verbessern. Gespeichert wird nur auf deinem iPhone und deinem Server.")
            }
            ForEach(Dictionary(grouping: entries, by: \.date).keys.sorted(by: >), id: \.self) { day in
                Section(Day.date(day).formatted(date: .complete, time: .omitted)) {
                    ForEach(entries.filter { $0.date == day }) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(e.text("time") ?? "") · \(e.text("persona") ?? e.text("kind") ?? "") · \(e.text("source") ?? "") · \((e.num("ms") ?? 0).whole) ms")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("🗣 \(e.text("heard") ?? "")").font(.callout)
                            Text("🤖 \(e.text("reply") ?? "")").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .themed()
        .navigationTitle("Gesprächsprotokoll")
    }
}
