import CryptoKit
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
    /// Nur auf diesem iPhone speichern: keine Einträge, kein Profil, keine Protokolle auf dem Server.
    /// Der Server dient dann nur noch als Durchgang zu Claude und für die Stimme.
    var localOnly: Bool { didSet { defaults.set(localOnly, forKey: "localOnly") } }
    /// Apple Health wurde verbunden (Freigabe-Dialog wurde gezeigt)
    var healthEnabled: Bool { didSet { defaults.set(healthEnabled, forKey: "healthEnabled") } }

    var aiAvailable = false
    var ttsAvailable = false
    var reelkochAvailable = false
    var serverVersion = ""
    var syncError: String?
    var pendingLink: URL?
    /// Ende-zu-Ende-Verschlüsselung aktiv, aber Schlüssel fehlt (z. B. neues Gerät) → Passwort abfragen
    var vaultLocked = Vault.locked
    private var pendingProfile: Data?  // verschlüsseltes Profil vom Server, bis der Tresor entsperrt ist
    private var lastRev: Int64 { didSet { defaults.set(lastRev, forKey: "lastRev") } }
    private var profileDirty = false
    private var syncing = false
    private var syncAgain = false  // Änderung während eines laufenden Abgleichs → danach erneut abgleichen

    init() {
        server = defaults.string(forKey: "server") ?? ""
        token = Keychain.get("token")
        demo = defaults.bool(forKey: "demo")
        profile = (defaults.data(forKey: "profile")).flatMap { try? JSONDecoder().decode(Profile.self, from: $0) } ?? Profile()
        healthUpload = defaults.bool(forKey: "healthUpload")
        aiConsent = defaults.bool(forKey: "aiConsent")
        healthEnabled = defaults.bool(forKey: "healthEnabled")
        localOnly = defaults.bool(forKey: "localOnly")
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
            ttsAvailable = status.tts ?? false; reelkochAvailable = status.reelkoch ?? false
        serverVersion = status.version
        // Tresor auf dem Server? Dann braucht dieses Gerät das Passwort, bevor es Daten lesen kann
        if let data = try? await self.api.call("GET", "/api/vault"), (try? JSONDecoder().decode(Vault.Box.self, from: data)) != nil {
            Vault.enabled = true
            vaultLocked = Vault.locked
        }
        if let data = try? await self.api.call("GET", "/api/profile") {
            if let p = decodeProfile(data) { applyServerProfile(p) } else { pendingProfile = data }
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
        Vault.enabled = false
        Vault.key = nil
        vaultLocked = false
        pendingProfile = nil
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
        guard !demo, token != nil else { return }
        guard !syncing else { syncAgain = true; AppLog.add("Abgleich läuft schon – wird danach wiederholt"); return }
        syncing = true
        defer {
            syncing = false
            if syncAgain { syncAgain = false; Task { await sync(context) } }
            Task { await AppLog.flush(api) }
        }
        do {
            let status = try await api.status()
            aiAvailable = status.ai
            ttsAvailable = status.tts ?? false; reelkochAvailable = status.reelkoch ?? false
            serverVersion = status.version
            if localOnly { syncError = nil; return }  // Daten bleiben auf dem iPhone
            if Vault.locked { vaultLocked = true; syncError = String(localized: "Verschlüsselt – bitte Passwort eingeben"); return }

            let dirty = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.dirty }))
            AppLog.add("Abgleich: \(dirty.count) zu senden, seit rev \(lastRev)" + dirty.prefix(20).map { "\n  ↑ " + AppLog.describe($0) }.joined())
            if !dirty.isEmpty {
                let sent = dirty.map { ($0, $0.updated) }
                _ = try await api.call("POST", "/api/entries", json: dirty.map { Vault.sealEntry($0.json) })
                for (e, updated) in sent where e.updated == updated { e.dirty = false }
            }

            let data = try await api.call("GET", "/api/entries?since=\(lastRev)")
            let pulled = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            AppLog.add("Abgleich: \(pulled.count) vom Server" + pulled.prefix(20).map { r in
                "\n  ↓ \(r["module"] ?? "")/\(String(describing: r["id"] ?? "").prefix(8)) upd=\(r["updated"] ?? "-") rev=\(r["rev"] ?? "-")\((r["deleted"] as? Bool) == true ? " gelöscht" : "")"
            }.joined())
            for r in pulled {
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
                // Verschlüsselte Inhalte entschlüsseln; lässt sich etwas nicht öffnen, bleibt der lokale Stand
                let values = Vault.open(r["data"]) as? [String: Any]
                if values == nil && r["data"] is String {
                    // Verschlüsselt, aber hier noch kein Schlüssel (Tresor auf einem anderen Gerät eingeschaltet) → Passwort abfragen
                    if !Vault.enabled { Vault.enabled = true }
                    vaultLocked = Vault.locked
                    AppLog.add("Abgleich: Eintrag nicht entschlüsselbar")
                    continue
                }
                e.module = module
                e.date = r["date"] as? String ?? e.date
                e.values = values ?? [:]
                e.deleted = r["deleted"] as? Bool ?? false
                e.updated = updated
                e.dirty = false
            }
            try context.save()
            await pushProfile()
            await pushCard(context)
            await Telemetry.send(context, api: api, profileName: profile.name)  // nur wenn freiwillig eingeschaltet
            syncError = nil
            AppLog.add("Abgleich fertig")
        } catch {
            syncError = error.localizedDescription
            AppLog.add("Abgleich FEHLER: \(error.localizedDescription)")
        }
    }

    /// Spielerkarte für Freunde hochladen – nur Spielwerte, keine Gesundheitsdaten
    func pushCard(_ context: ModelContext) async {
        guard !demo, !localOnly, token != nil else { return }
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
        guard profileDirty, !demo, !localOnly, token != nil, let data = try? JSONEncoder().encode(profile),
              let plain = try? JSONSerialization.jsonObject(with: data) else { return }
        let json: Any = Vault.enabled ? ["enc": Vault.seal(plain)] : plain  // mit Tresor nur verschlüsselt
        if Vault.locked { return }
        if (try? await api.call("PUT", "/api/profile", json: json)) != nil {
            profileDirty = false
            defaults.set(false, forKey: "profileDirty")
        }
    }

    /// Nach jeder Änderung: lokal speichern und im Hintergrund abgleichen.
    func changed(_ context: ModelContext) {
        for e in context.insertedModelsArray.compactMap({ $0 as? Entry }) { AppLog.add("neu " + AppLog.describe(e)) }
        for e in context.changedModelsArray.compactMap({ $0 as? Entry }) { AppLog.add("geändert " + AppLog.describe(e)) }
        do { try context.save() } catch { AppLog.add("Speichern FEHLER: \(error.localizedDescription)") }
        Task { await sync(context) }
    }

    /// Speicherort umschalten. An: gespeicherte Daten auf dem Server löschen. Aus: alles wieder hochladen.
    func setLocalOnly(_ on: Bool, _ context: ModelContext) async throws {
        if on {
            if !demo { _ = try await api.call("DELETE", "/api/data") }
            localOnly = true
        } else {
            localOnly = false
            for e in context.allEntries() where e.module != "coachlog" || CoachLog.enabled { e.dirty = true }
            lastRev = 0
            profileDirty = true
            changed(context)
        }
    }

    // MARK: Verschlüsselung (Tresor)

    /// Profil vom Server lesen – auch verschlüsselt ({"enc": "…"})
    private func decodeProfile(_ data: Data) -> Profile? {
        if let p = try? JSONDecoder().decode(Profile.self, from: data) { return p }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], obj["enc"] != nil,
              let plain = Vault.open(obj["enc"]), let d = try? JSONSerialization.data(withJSONObject: plain) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: d)
    }

    private func applyServerProfile(_ p: Profile) {
        syncing = true
        profile = p
        syncing = false
        profileDirty = false
    }

    private func vaultBox() async throws -> Vault.Box {
        try JSONDecoder().decode(Vault.Box.self, from: try await api.call("GET", "/api/vault"))
    }

    /// Entsperren mit Passwort oder Wiederherstellungsschlüssel (z. B. auf einem neuen Gerät)
    func unlockVault(password: String? = nil, recovery: String? = nil, _ context: ModelContext) async throws {
        let box = try await vaultBox()
        var key: SymmetricKey?
        if let password { key = Vault.unlock(box, password: password) }
        if let recovery { key = Vault.unlock(box, recovery: recovery) }
        guard let key else {
            throw API.Failure(message: password != nil ? String(localized: "Passwort falsch") : String(localized: "Wiederherstellungsschlüssel falsch"))
        }
        Vault.key = key
        vaultLocked = false
        lastRev = 0  // alles noch einmal holen und entschlüsseln
        if pendingProfile == nil { pendingProfile = try? await api.call("GET", "/api/profile") }
        if !profileDirty, let data = pendingProfile, let p = decodeProfile(data) { applyServerProfile(p) }
        pendingProfile = nil
        await sync(context)
    }

    /// Verschlüsselung einschalten: neuer Schlüssel, alles einmal verschlüsselt neu hochladen. Gibt den Wiederherstellungsschlüssel zurück.
    func enableVault(password: String, _ context: ModelContext) async throws -> String {
        let (box, key, recovery) = Vault.create(password: password)
        if !demo && !localOnly { _ = try await api.call("PUT", "/api/vault", json: try JSONSerialization.jsonObject(with: JSONEncoder().encode(box))) }
        Vault.key = key
        Vault.enabled = true
        reupload(context)
        return recovery
    }

    /// Neues Passwort (das alte wird nicht gebraucht – dieses Gerät hat den Schlüssel)
    func changeVaultPassword(_ password: String) async throws {
        guard let key = Vault.key else { return }
        let box = Vault.rewrap(try await vaultBox(), key: key, password: password)
        _ = try await api.call("PUT", "/api/vault", json: try JSONSerialization.jsonObject(with: JSONEncoder().encode(box)))
    }

    /// Verschlüsselung ausschalten: alles wieder im Klartext hochladen
    func disableVault(_ context: ModelContext) async throws {
        if !demo && !localOnly { _ = try await api.call("DELETE", "/api/vault") }
        Vault.enabled = false
        reupload(context)
        Vault.key = nil
    }

    private func reupload(_ context: ModelContext) {
        for e in context.allEntries() { e.dirty = true }
        profileDirty = true
        defaults.set(true, forKey: "profileDirty")
        changed(context)
    }

    func delete(_ entry: Entry, _ context: ModelContext) {
        entry.deleted = true
        entry.touch()
        AppLog.add("löschen " + AppLog.describe(entry))
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
        for m in await Health.bodyMeasurements(days: days) {
            context.upsert(id: m.id, module: "body", date: m.date, values: m.values, dirty: healthUpload)
        }
        for m in await Health.symptoms(days: days) {
            context.upsert(id: m.id, module: "symptoms", date: m.date, values: m.values, dirty: healthUpload)
        }
        for m in await Health.moods(days: days) {
            context.upsert(id: m.id, module: "mood", date: m.date, values: m.values, dirty: healthUpload)
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
