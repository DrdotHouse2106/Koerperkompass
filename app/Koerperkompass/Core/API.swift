import Foundation
import Security

/// Minimaler Client für den eigenen Körperkompass-Server.
struct API {
    let server: String
    var token: String?

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Status: Decodable {
        let name: String
        let version: String
        let ai: Bool
    }

    func call(_ method: String = "GET", _ path: String, json: Any? = nil) async throws -> Data {
        guard let url = URL(string: server + path) else { throw Failure(message: String(localized: "Ungültige Server-Adresse")) }
        var req = URLRequest(url: url, timeoutInterval: path.hasPrefix("/api/ai") ? 300 : 15)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json { req.httpBody = try JSONSerialization.data(withJSONObject: json) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: text.isEmpty ? "HTTP \(code)" : text)
        }
        return data
    }

    func object(_ method: String = "GET", _ path: String, json: Any? = nil) async throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: try await call(method, path, json: json)) as? [String: Any] ?? [:]
    }

    func status() async throws -> Status {
        let s = try JSONDecoder().decode(Status.self, from: try await call("GET", "/api/status"))
        guard s.name == "koerperkompass" else { throw Failure(message: String(localized: "Unter dieser Adresse läuft kein Körperkompass-Server")) }
        return s
    }

    /// „kompass.example.de“ → „https://kompass.example.de“, ohne Schrägstrich am Ende
    static func normalize(_ s: String) -> String {
        var s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

/// Das Token liegt im Schlüsselbund, nicht in den UserDefaults.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value else { return }
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
