import SwiftData
import SwiftUI
import VisionKit

/// Freunde – auf demselben oder einem anderen Körperkompass-Server – und die Wochen-Challenge.
/// Geteilt wird nur die Spielerkarte (Name, Level, Rang, Serie, Wochenwerte), nie Gesundheitsdaten.
struct FriendsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query private var entries: [Entry]
    @State private var friends: [Friend] = []
    @State private var input = ""
    @State private var link: Invite?
    @State private var scanning = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        let me = QuestProgress(entries, state.profile)
        List {
            if state.demo {
                Text("Freunde gibt es nur mit eigenem Server – im Demo-Modus nicht verfügbar.").foregroundStyle(.secondary)
            } else {
                Section {
                    let board: [(String, Int, Int, Bool)] = ([("👤 " + (state.profile.name ?? String(localized: "Ich")), me.weekQuests, me.weekXP, true)]
                        + friends.map { ($0.name, $0.weekQuests, $0.weekXP, false) })
                        .sorted { ($0.1, $0.2) > ($1.1, $1.2) }
                    ForEach(board.indices, id: \.self) { i in
                        HStack {
                            Text(["🥇", "🥈", "🥉"].indices.contains(i) ? ["🥇", "🥈", "🥉"][i] : "\(i + 1).")
                                .frame(width: 32)
                            Text(board[i].0).bold(board[i].3)
                            Spacer()
                            Text("\(board[i].1) Quests · \(board[i].2) XP").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Wochen-Challenge") } footer: {
                    Text("Wer schafft von Montag bis Sonntag die meisten Quests? Gleichstand entscheidet die XP.")
                }

                Section("Freunde") {
                    if friends.isEmpty && !busy { Text("Noch keine Freunde – lade jemanden mit einem Freundschaftslink ein.").foregroundStyle(.secondary) }
                    ForEach(friends) { f in
                        NavigationLink { FriendDetail(friend: f, remove: { remove(f) }) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(f.name).font(.headline)
                                    Text("Level \(f.level) · \(f.rank) · 🔥 \(f.streak)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !f.online { Image(systemName: "wifi.slash").foregroundStyle(.secondary) }
                                Text(f.server).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Freundschaftslink erstellen", systemImage: "link.badge.plus") { createLink() }
                    HStack {
                        TextField("Link eines Freundes einfügen", text: $input)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("QR", systemImage: "qrcode.viewfinder") { scanning = true }.labelStyle(.iconOnly)
                    }
                    Button("Freund hinzufügen") { add(input) }.disabled(input.isEmpty || busy)
                    if let error { Text(error).foregroundStyle(.red) }
                } header: { Text("Hinzufügen") } footer: {
                    Text("Funktioniert mit Freunden auf deinem Server und auf anderen Körperkompass-Servern. Ein Link gilt einmal und 7 Tage.")
                }

                Section {
                    Toggle("Meine Freunde meinen Freunden zeigen", isOn: Binding(
                        get: { state.profile.showFriends == true }, set: { state.profile.showFriends = $0; Task { await state.pushCard(context) } }))
                    Toggle("Für Freunde meiner Freunde sichtbar sein", isOn: Binding(
                        get: { state.profile.visible == true }, set: { state.profile.visible = $0; Task { await state.pushCard(context) } }))
                } header: { Text("Privatsphäre") } footer: {
                    Text("Geteilt werden nur Name, Level, Rang, Klasse, Serie, Erfolge und Wochenwerte – keine Gesundheitsdaten. Freunde von Freunden siehst du nur, wenn beide zugestimmt haben.")
                }
            }
        }
        .themed()
            .navigationTitle("Freunde")
        .refreshable { await load() }
        .task { await state.pushCard(context); await load() }
        .sheet(item: $link) { InviteView(link: $0.link, note: "Schick diesen Link einem Freund. Er fügt ihn in Körperkompass unter Abenteuer → Freunde ein. Einmalig, 7 Tage gültig.") }
        .sheet(isPresented: $scanning) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                QRScanner { text in scanning = false; add(text) }.ignoresSafeArea()
            } else {
                ContentUnavailableView("Scanner nicht verfügbar", systemImage: "camera")
            }
        }
    }

    private func load() async {
        guard !state.demo else { return }
        busy = true
        defer { busy = false }
        do {
            let data = try await state.api.call("GET", "/api/friends")
            friends = ((try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []).map(Friend.init)
        } catch { self.error = error.localizedDescription }
    }

    private func createLink() {
        Task {
            do {
                let r = try await state.api.object("POST", "/api/friends/link")
                if let l = r["link"] as? String { link = Invite(link: l) }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func add(_ text: String) {
        error = nil
        Task {
            do {
                _ = try await state.api.call("POST", "/api/friends", json: ["link": text.trimmingCharacters(in: .whitespacesAndNewlines)])
                input = ""
                await load()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func remove(_ f: Friend) {
        Task {
            _ = try? await state.api.call("DELETE", "/api/friends/\(f.id)")
            await load()
        }
    }
}

/// Spielerkarte eines Freundes, wie sein Server sie liefert
struct Friend: Identifiable {
    let id: Int
    let server: String
    let online: Bool
    let card: [String: Any]

    init(_ json: [String: Any]) {
        id = (json["id"] as? NSNumber)?.intValue ?? 0
        server = URL(string: json["url"] as? String ?? "")?.host ?? ""
        online = json["online"] as? Bool ?? false
        card = json["card"] as? [String: Any] ?? [:]
    }

    private func int(_ k: String, in d: [String: Any]? = nil) -> Int { ((d ?? card)[k] as? NSNumber)?.intValue ?? 0 }
    var name: String { (card["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Ohne Namen") }
    var level: Int { max(int("level"), 1) }
    var streak: Int { int("streak") }
    var rank: String { card["rank"] as? String ?? "" }
    var characterClass: String { card["class"] as? String ?? "" }
    var badges: Int { int("badges") }
    var workouts: Int { int("workouts") }
    /// Wochenwerte zählen nur, wenn sie aus der aktuellen Woche stammen
    private var week: [String: Any]? {
        let w = card["week"] as? [String: Any]
        return w?["start"] as? String == Day.weekStart ? w : nil
    }
    var weekQuests: Int { week.map { int("quests", in: $0) } ?? 0 }
    var weekXP: Int { week.map { int("xp", in: $0) } ?? 0 }
    var friendsOfFriend: [[String: Any]]? { card["friends"] as? [[String: Any]] }
}

private struct FriendDetail: View {
    let friend: Friend
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    var body: some View {
        List {
            Section {
                LabeledContent("Level", value: "\(friend.level)")
                LabeledContent("Rang", value: friend.rank)
                LabeledContent("Klasse", value: friend.characterClass)
                LabeledContent("Serie", value: "🔥 \(friend.streak)")
                LabeledContent("Workouts", value: "\(friend.workouts)")
                LabeledContent("Erfolge", value: "\(friend.badges)")
                LabeledContent("Diese Woche", value: "\(friend.weekQuests) Quests · \(friend.weekXP) XP")
                LabeledContent("Server", value: friend.server)
            } footer: {
                if !friend.online { Text("Server gerade nicht erreichbar – letzter bekannter Stand.") }
            }
            if let fof = friend.friendsOfFriend {
                Section {
                    if fof.isEmpty { Text("Keine sichtbaren Freunde").foregroundStyle(.secondary) }
                    ForEach(fof.indices, id: \.self) { i in
                        let f = fof[i]
                        HStack {
                            Text(f["name"] as? String ?? "–")
                            Spacer()
                            Text("Level \((f["level"] as? NSNumber)?.intValue ?? 1) · \(f["server"] as? String ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Freunde von \(friend.name)") } footer: {
                    Text("Möchtest du dich mit jemandem davon befreunden, bitte \(friend.name) um einen Kontakt – oder tauscht direkt einen Freundschaftslink aus.")
                }
            }
            Section {
                Button("Freundschaft beenden", role: .destructive) { confirm = true }
            }
        }
        .navigationTitle(friend.name)
        .confirmationDialog("Freundschaft beenden?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Beenden", role: .destructive) { remove(); dismiss() }
        } message: {
            Text("Beide Server löschen die gegenseitig gespeicherten Spielwerte.")
        }
    }
}
