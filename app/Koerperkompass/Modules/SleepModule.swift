import SwiftData
import SwiftUI

/// Schlaf: wie gut du geschlafen hast (1–5), wie lange und was gestört hat. Ergänzt die Schlafdauer aus Apple Health
/// (Modul Aktivität) um das eigene Gefühl – der Coach berücksichtigt beides (z. B. leichteres Training nach schlechter Nacht).
struct SleepModule: AppModule {
    let id = "sleep"
    let name: LocalizedStringResource = "Schlaf"
    let symbol = "bed.double.fill"
    let fields = [Field(key: "quality", name: "Schlafqualität", unit: "(1–5)", agg: .avg), Field(key: "hours", name: "Schlafdauer", unit: "h", agg: .avg)]

    func tile(_ entries: [Entry]) -> AnyView { AnyView(SleepTile(entries: entries)) }
    func detail(_ entries: [Entry]) -> AnyView { AnyView(SleepDetail(entries: entries)) }
}

enum Sleep {
    static let levels: [(emoji: String, title: LocalizedStringResource)] = [
        ("😫", "Sehr schlecht"), ("😕", "Schlecht"), ("😐", "Geht so"), ("🙂", "Gut"), ("😴", "Sehr gut"),
    ]
    static let issues: [(id: String, name: LocalizedStringResource)] = [
        ("fallAsleep", "Schwer eingeschlafen"), ("wokeUp", "Oft aufgewacht"), ("early", "Zu früh wach"), ("dreams", "Schlecht geträumt"),
        ("pain", "Schmerzen"), ("noise", "Lärm/Störung"), ("stress", "Gedankenkreisen"), ("late", "Zu spät ins Bett"),
    ]
    static func level(_ q: Double?) -> (emoji: String, title: LocalizedStringResource) { levels[max(0, min(4, Int(q ?? 3) - 1))] }
    static func issueName(_ id: String) -> String { issues.first { $0.id == id }.map { String(localized: $0.name) } ?? id }

    /// Für den Coach: letzte Nacht (Gefühl, Dauer, Störungen)
    static func summary(_ entries: [Entry]) -> String? {
        guard let e = entries.filter({ $0.module == "sleep" && !$0.deleted && Day.last(2).contains($0.date) }).max(by: { $0.date < $1.date })
        else { return nil }
        var s = "\(e.date == Day.today ? "letzte Nacht" : e.date): \(String(localized: level(e.num("quality")).title))"
        if let h = e.num("hours"), h > 0 { s += ", \(h.short) h" }
        let i = (e.values["issues"] as? [String] ?? []).map(issueName)
        if !i.isEmpty { s += " (" + i.joined(separator: ", ") + ")" }
        return s
    }
}

private struct SleepTile: View {
    let entries: [Entry]
    var body: some View {
        let last = entries.filter { $0.date == Day.today }.last
        TileCard(module: SleepModule()) {
            if let last {
                let l = Sleep.level(last.num("quality"))
                Text("\(l.emoji) \(String(localized: l.title))").font(.headline)
                if let h = last.num("hours"), h > 0 { Text("\(h.short) h").font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("Wie hast du geschlafen?").font(.headline)
            }
        }
    }
}

private struct SleepDetail: View {
    let entries: [Entry]
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query private var all: [Entry]
    @State private var quality: Int?
    @State private var hours: Double = 7
    @State private var issues: Set<String> = []
    @State private var saved = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { i in
                        Button { quality = i } label: {
                            Text(Sleep.levels[i - 1].emoji).font(.system(size: quality == i ? 36 : 28))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Theme.orange.opacity(quality == i ? 0.4 : 0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let quality { Text(Sleep.levels[quality - 1].title).font(.headline).frame(maxWidth: .infinity) }
                Stepper("Geschlafen: \(hours.short) h", value: $hours, in: 0...14, step: 0.5)
            } header: { Text("Wie hast du letzte Nacht geschlafen?") } footer: {
                Text("Die Dauer ist mit dem Wert aus Apple Health vorbelegt, falls vorhanden.")
            }
            if quality != nil {
                Section("Was hat gestört?") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(Sleep.issues, id: \.id) { item in
                            let on = issues.contains(item.id)
                            Button { if on { issues.remove(item.id) } else { issues.insert(item.id) } } label: {
                                Text(item.name).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background((on ? Theme.orange : Color.white).opacity(on ? 0.5 : 0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    Button(saved ? LocalizedStringKey("Eingetragen ✓") : "Eintragen", systemImage: "checkmark.circle.fill") { save() }.bold()
                }
            }
            Section("Verlauf") {
                EntryRows(entries: entries.sorted { $0.date > $1.date }) { e in
                    let l = Sleep.level(e.num("quality"))
                    let i = (e.values["issues"] as? [String] ?? []).map(Sleep.issueName)
                    return "\(l.emoji) \(String(localized: l.title))" + ((e.num("hours") ?? 0) > 0 ? " · \((e.num("hours") ?? 0).short) h" : "")
                        + (i.isEmpty ? "" : " · " + i.joined(separator: ", "))
                }
            }
            Section {
                Text("Keine ärztliche Beratung. Schläfst du über Wochen schlecht, sprich mit einer Ärztin oder einem Arzt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // Dauer aus Apple Health (Modul Aktivität) vorbelegen
            if let h = all.first(where: { $0.module == "activity" && $0.date == Day.today && !$0.deleted })?.num("sleepHours"), h > 0 {
                hours = (h * 2).rounded() / 2
            }
        }
        .onChange(of: quality) { saved = false }
    }

    private func save() {
        guard let quality else { return }
        context.insert(Entry(module: "sleep", values: ["quality": quality, "hours": hours, "issues": Array(issues), "time": Day.now]))
        state.changed(context)
        saved = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
