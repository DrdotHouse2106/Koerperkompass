import Foundation
import SwiftData
import UIKit

/// Zentraler Zustand: Verbindung, Profil, Zustimmungen und Abgleich mit dem Server.
@Observable @MainActor final class AppState {
    private let defaults = UserDefaults.standard

    var server: String { didSet { defaults.set(server, forKey: "server") } }
    var token: String? { didSet { Keychain.set("token", token) } }
    var demo: Bool { didSet { defaults.set(demo, forKey: "demo") } }
    var profile: Profile {
        didSet {
            defaults.set(try? JSONEncoder().encode(profile), forKey: "profile")
            profileDirty = true
            if !syncing { Task { await pushProfile() } }
        }
    }
    /// Zustimmung 1: Health-Daten dürfen an den eigenen Server gehen
    var healthUpload: Bool { didSet { defaults.set(healthUpload, forKey: "healthUpload") } }
    /// Zustimmung 2: Daten dürfen zur Analyse an die Claude API gehen (über den eigenen Server)
    var aiConsent: Bool { didSet { defaults.set(aiConsent, forKey: "aiConsent") } }
    /// Apple Health wurde verbunden (Freigabe-Dialog wurde gezeigt)
    var healthEnabled: Bool { didSet { defaults.set(healthEnabled, forKey: "healthEnabled") } }

    var aiAvailable = false
    var ttsAvailable = false
    var serverVersion = ""
    var syncError: String?
    var pendingLink: URL?
    private var lastRev: Int64 { didSet { defaults.set(lastRev, forKey: "lastRev") } }
    private var profileDirty = false
    private var syncing = false

    init() {
        server = defaults.string(forKey: "server") ?? ""
        token = Keychain.get("token")
        demo = defaults.bool(forKey: "demo")
        profile = (defaults.data(forKey: "profile")).flatMap { try? JSONDecoder().decode(Profile.self, from: $0) } ?? Profile()
        healthUpload = defaults.bool(forKey: "healthUpload")
        aiConsent = defaults.bool(forKey: "aiConsent")
        healthEnabled = defaults.bool(forKey: "healthEnabled")
        lastRev = Int64(defaults.integer(forKey: "lastRev"))
        profileDirty = defaults.bool(forKey: "profileDirty")
    }

    var isConnected: Bool { demo || token != nil }
    var api: API { API(server: server, token: token) }
    var activeModules: [any AppModule] { allModules.filter { profile.modules.contains($0.id) } }

    // MARK: Verbindung

    /// Koppelt die App mit dem Server und übernimmt ein eventuell vorhandenes Profil.
    func connect(server: String, code: String, context: ModelContext) async throws {
        let api = API(server: API.normalize(server))
        let status = try await api.status()
        let res = try await api.object("POST", "/api/pair", json: ["code": code, "name": "", "device": UIDevice.current.name])
        guard let token = res["token"] as? String else { throw API.Failure(message: String(localized: "Kopplung fehlgeschlagen")) }
        reset(context)
        self.server = api.server
        self.token = token
        aiAvailable = status.ai
            ttsAvailable = status.tts ?? false
        serverVersion = status.version
        if let data = try? await self.api.call("GET", "/api/profile"), let p = try? JSONDecoder().decode(Profile.self, from: data) {
            syncing = true
            profile = p
            syncing = false
            profileDirty = false
        }
        await sync(context)
    }

    func startDemo(_ context: ModelContext) {
        reset(context)
        demo = true
        Demo.fill(context, state: self)
    }

    /// Trennt die Verbindung und löscht alle lokalen Daten (die Daten auf dem Server bleiben erhalten).
    func reset(_ context: ModelContext) {
        try? context.delete(model: Entry.self)
        try? context.save()
        token = nil
        demo = false
        lastRev = 0
        syncing = true
        profile = Profile()
        syncing = false
        profileDirty = false
        aiAvailable = false
        healthUpload = false
        aiConsent = false
    }

    // MARK: Abgleich

    /// Überträgt geänderte Einträge und holt neue vom Server. Ohne Netz bleibt alles lokal und wird später nachgeholt.
    func sync(_ context: ModelContext) async {
        guard !demo, token != nil, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let status = try await api.status()
            aiAvailable = status.ai
            ttsAvailable = status.tts ?? false
            serverVersion = status.version

            let dirty = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.dirty }))
            if !dirty.isEmpty {
                let sent = dirty.map { ($0, $0.updated) }
                _ = try await api.call("POST", "/api/entries", json: dirty.map(\.json))
                for (e, updated) in sent where e.updated == updated { e.dirty = false }
            }

            let data = try await api.call("GET", "/api/entries?since=\(lastRev)")
            for r in (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? [] {
                guard let id = r["id"] as? String, let module = r["module"] as? String else { continue }
                let updated = (r["updated"] as? NSNumber)?.int64Value ?? 0
                lastRev = max(lastRev, (r["rev"] as? NSNumber)?.int64Value ?? 0)
                let e = context.entry(id) ?? {
                    let e = Entry(id: id, module: module, values: [:], dirty: false)
                    e.updated = 0
                    context.insert(e)
                    return e
                }()
                guard updated >= e.updated, !e.dirty else { continue }
                e.module = module
                e.date = r["date"] as? String ?? e.date
                e.values = r["data"] as? [String: Any] ?? [:]
                e.deleted = r["deleted"] as? Bool ?? false
                e.updated = updated
                e.dirty = false
            }
            try context.save()
            await pushProfile()
            await pushCard(context)
            await Telemetry.send(context, api: api, profileName: profile.name)  // nur wenn freiwillig eingeschaltet
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Spielerkarte für Freunde hochladen – nur Spielwerte, keine Gesundheitsdaten
    func pushCard(_ context: ModelContext) async {
        guard !demo, token != nil else { return }
        let p = QuestProgress(context.allEntries(), profile)
        let card: [String: Any] = [
            "name": profile.name ?? "", "level": p.level, "xp": p.xp, "streak": p.streak,
            "rank": String(localized: p.rank), "class": String(localized: p.characterClass),
            "workouts": p.workouts, "badges": p.badges(profile).filter(\.unlocked).count,
            "week": ["start": Day.weekStart, "quests": p.weekQuests, "xp": p.weekXP],
            "showFriends": profile.showFriends == true, "visible": profile.visible == true,
        ]
        _ = try? await api.call("PUT", "/api/card", json: card)
    }

    private func pushProfile() async {
        defaults.set(profileDirty, forKey: "profileDirty")
        guard profileDirty, !demo, token != nil, let data = try? JSONEncoder().encode(profile),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }
        if (try? await api.call("PUT", "/api/profile", json: json)) != nil {
            profileDirty = false
            defaults.set(false, forKey: "profileDirty")
        }
    }

    /// Nach jeder Änderung: lokal speichern und im Hintergrund abgleichen.
    func changed(_ context: ModelContext) {
        try? context.save()
        Task { await sync(context) }
    }

    func delete(_ entry: Entry, _ context: ModelContext) {
        entry.deleted = true
        entry.touch()
        changed(context)
    }

    // MARK: Apple Health

    func connectHealth() async {
        guard Health.available else { return }
        try? await Health.authorize()
        healthEnabled = true
    }

    /// Holt Aktivität, Schlaf und Gewicht aus Apple Health in den lokalen Speicher.
    /// Zum Server gehen sie nur mit Zustimmung (healthUpload).
    func importHealth(_ context: ModelContext, days: Int = 30) async {
        guard healthEnabled, !demo else { return }
        for (day, values) in await Health.activity(days: days) {
            context.upsert(id: "activity-" + day, module: "activity", date: day, values: values, dirty: healthUpload)
        }
        for w in await Health.weights(days: days) {
            context.upsert(id: w.id, module: "body", date: w.date, values: ["weight": w.kg], dirty: healthUpload)
        }
        changed(context)
    }

    /// Zustimmung geändert: bei Erteilung bereits gelesene Health-Daten zum Hochladen vormerken.
    func setHealthUpload(_ on: Bool, _ context: ModelContext) {
        healthUpload = on
        guard on else { return }
        for e in context.allEntries() where e.id.hasPrefix("activity-") || e.id.hasPrefix("health-") { e.dirty = true }
        changed(context)
    }

    /// Kopplungslink aus QR-Code oder Kamera-App: koerperkompass://pair?server=…&code=…
    static func parse(_ text: String) -> (server: String, code: String)? {
        guard let c = URLComponents(string: text), c.scheme == "koerperkompass",
              let server = c.queryItems?.first(where: { $0.name == "server" })?.value,
              let code = c.queryItems?.first(where: { $0.name == "code" })?.value else { return nil }
        return (server, code)
    }
}
