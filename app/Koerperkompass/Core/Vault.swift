import CommonCrypto
import CryptoKit
import Foundation

/// Ende-zu-Ende-Verschlüsselung („Tresor“): Einträge und Profil werden auf dem iPhone mit einem zufälligen
/// Datenschlüssel verschlüsselt (AES-GCM), bevor sie zum Server gehen. Der Server sieht nur Modul, Datum und
/// Zeitstempel der Einträge, nie die Inhalte.
///
/// Der Datenschlüssel liegt im iCloud-Schlüsselbund (von Apple Ende-zu-Ende-verschlüsselt) und ist so auf allen
/// eigenen Geräten mit derselben Apple-ID da – ohne Passwort. Auf dem Server liegt er nur verschlüsselt: mit dem
/// Wiederherstellungsschlüssel und, falls gesetzt, mit einem eigenen Passwort (je PBKDF2-SHA256) – ohne Hintertür.
/// Neue Nutzer bekommen die Verschlüsselung automatisch (AppState.sync).
enum Vault {
    /// Auf dem Server gespeicherte Angaben (alles ohne Passwort wertlos)
    struct Box: Codable {
        var v = 1
        var rounds: Int
        var salt: String       // für das Passwort
        var wrapped: String    // Datenschlüssel, mit Passwort verschlüsselt
        var rsalt: String      // für den Wiederherstellungsschlüssel
        var rwrapped: String   // Datenschlüssel, mit Wiederherstellungsschlüssel verschlüsselt
    }

    static let prefix = "enc:v1:"
    static let rounds = 600_000

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "vaultOn") }
        set { UserDefaults.standard.set(newValue, forKey: "vaultOn") }
    }

    /// Datenschlüssel aus dem Schlüsselbund (nil = gesperrt)
    static var key: SymmetricKey? {
        get { Keychain.get("vaultKey").flatMap { Data(base64Encoded: $0) }.map { SymmetricKey(data: $0) } }
        set { Keychain.set("vaultKey", newValue.map { $0.withUnsafeBytes { Data($0) }.base64EncodedString() }, sync: true) }
    }

    static var locked: Bool { enabled && key == nil }

    // MARK: Schlüssel

    static func derive(_ secret: String, salt: Data, rounds: Int) -> SymmetricKey {
        var out = [UInt8](repeating: 0, count: 32)
        let pw = Array(secret.precomposedStringWithCanonicalMapping.utf8)
        _ = salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                 s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds), &out, out.count)
        }
        return SymmetricKey(data: out)
    }

    static func random(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }

    /// Wiederherstellungsschlüssel: 24 gut lesbare Zeichen in Sechsergruppen
    static func recoveryCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let raw = String((0..<24).map { _ in chars.randomElement()! })
        return stride(from: 0, to: 24, by: 6).map { i in String(raw.dropFirst(i).prefix(6)) }.joined(separator: "-")
    }

    static func normalize(_ code: String) -> String { code.uppercased().filter { $0.isLetter || $0.isNumber } }

    private static func wrap(_ key: SymmetricKey, with k: SymmetricKey) -> String {
        (try? AES.GCM.seal(key.withUnsafeBytes { Data($0) }, using: k).combined?.base64EncodedString()) ?? ""
    }

    private static func unwrap(_ s: String, with k: SymmetricKey) -> SymmetricKey? {
        guard let d = Data(base64Encoded: s), let box = try? AES.GCM.SealedBox(combined: d),
              let raw = try? AES.GCM.open(box, using: k) else { return nil }
        return SymmetricKey(data: raw)
    }

    /// Neuer Tresor: Datenschlüssel, Box für den Server und Wiederherstellungsschlüssel
    /// Ohne Passwort hilft auf neuen Geräten der iCloud-Schlüsselbund oder der Wiederherstellungsschlüssel.
    static func create(password: String?) -> (box: Box, key: SymmetricKey, recovery: String) {
        let key = SymmetricKey(size: .bits256), code = recoveryCode()
        let salt = random(16), rsalt = random(16)
        let box = Box(rounds: rounds, salt: salt.base64EncodedString(),
                      wrapped: password.map { wrap(key, with: derive($0, salt: salt, rounds: rounds)) } ?? "",
                      rsalt: rsalt.base64EncodedString(),
                      rwrapped: wrap(key, with: derive(normalize(code), salt: rsalt, rounds: rounds)))
        return (box, key, code)
    }

    static func unlock(_ box: Box, password: String) -> SymmetricKey? {
        guard let salt = Data(base64Encoded: box.salt) else { return nil }
        return unwrap(box.wrapped, with: derive(password, salt: salt, rounds: box.rounds))
    }

    static func unlock(_ box: Box, recovery: String) -> SymmetricKey? {
        guard let salt = Data(base64Encoded: box.rsalt) else { return nil }
        return unwrap(box.rwrapped, with: derive(normalize(recovery), salt: salt, rounds: box.rounds))
    }

    /// Neues Passwort für denselben Datenschlüssel (Wiederherstellungsschlüssel bleibt gültig)
    static func rewrap(_ box: Box, key: SymmetricKey, password: String) -> Box {
        var b = box
        let salt = random(16)
        b.salt = salt.base64EncodedString()
        b.rounds = rounds
        b.wrapped = wrap(key, with: derive(password, salt: salt, rounds: rounds))
        return b
    }

    // MARK: Daten

    /// Für den Server: JSON-Wert verschlüsseln, wenn der Tresor aktiv ist (sonst unverändert)
    static func seal(_ value: Any) -> Any {
        guard enabled, let key, let data = try? JSONSerialization.data(withJSONObject: value),
              let box = try? AES.GCM.seal(data, using: key).combined else { return value }
        return prefix + box.base64EncodedString()
    }

    /// Vom Server: verschlüsselte Werte entschlüsseln; Klartext (ältere Einträge) bleibt, wie er ist
    static func open(_ value: Any?) -> Any? {
        guard let s = value as? String, s.hasPrefix(prefix) else { return value }
        guard let key, let d = Data(base64Encoded: String(s.dropFirst(prefix.count))),
              let box = try? AES.GCM.SealedBox(combined: d), let raw = try? AES.GCM.open(box, using: key) else { return nil }
        return try? JSONSerialization.jsonObject(with: raw)
    }

    /// Eintrag zum Hochladen: Inhalt verschlüsselt, Modul/Datum/Zeitstempel bleiben lesbar (für den Abgleich)
    static func sealEntry(_ json: [String: Any]) -> [String: Any] {
        var j = json
        if let data = j["data"] { j["data"] = seal(data) }
        return j
    }
}
