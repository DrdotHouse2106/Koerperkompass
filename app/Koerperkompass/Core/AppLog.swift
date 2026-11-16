import Foundation

/// Erweitertes Protokoll für die Testphase: Abläufe (Tippen, Abgleich, Server-Aufrufe, Fehler) gehen an den
/// eigenen Server (`POST /api/log`) – nur Kennungen und Zeitstempel, keine Gesundheitswerte. Nie weitergeleitet.
/// Abschaltbar in den Einstellungen.
enum AppLog {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "appLogOn") as? Bool ?? true }
    private static var buffer: [[String: Any]] = []
    private static let lock = NSLock()

    static func add(_ msg: String) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        buffer.append(["ts": Int64(Date().timeIntervalSince1970 * 1000), "msg": msg])
        if buffer.count > 1000 { buffer.removeFirst(buffer.count - 1000) }
    }

    /// Gesammelte Zeilen senden; ohne Netz bleiben sie bis zum nächsten Mal liegen.
    static func flush(_ api: API) async {
        lock.lock(); let lines = buffer; buffer = []; lock.unlock()
        guard enabled, api.token != nil, !lines.isEmpty else { return }
        if (try? await api.call("POST", "/api/log", json: lines)) == nil {
            lock.lock(); buffer = lines + buffer; lock.unlock()
        }
    }

    /// Kurzbeschreibung eines Eintrags ohne Werte
    static func describe(_ e: Entry) -> String {
        "\(e.module)/\(e.id.prefix(8)) \(e.date) upd=\(e.updated)\(e.deleted ? " gelöscht" : "")\(e.dirty ? " dirty" : "")"
    }
}
