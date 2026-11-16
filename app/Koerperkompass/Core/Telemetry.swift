import Foundation
import SwiftData
import UIKit

/// Anonyme Verbesserungsdaten (freiwillig, standardmäßig aus). Gesendet werden nur Einträge aus dem Gesprächsprotokoll –
/// ohne Kennung, ohne Gesundheitswerte; Gesprächstexte nur mit eigener Zustimmung und vorher bereinigt.
/// Weg: App → eigener Server (/api/telemetry) → Hauptserver des Projekts.
enum Telemetry {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "anonShare") }
    static var withTexts: Bool { UserDefaults.standard.bool(forKey: "anonTexts") }

    /// Entfernt Namen, E-Mail-Adressen, Telefonnummern und Links aus freiem Text
    static func scrub(_ text: String, name: String?) -> String {
        var t = text
        if let name, name.count > 1 { t = t.replacingOccurrences(of: name, with: "[Name]", options: .caseInsensitive) }
        let patterns = [
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,      // E-Mail
            #"https?://\S+|www\.\S+"#,                       // Links
            #"\+?\d[\d\s/()-]{7,}\d"#,                        // Telefonnummern
        ]
        for p in patterns {
            t = t.replacingOccurrences(of: p, with: "[entfernt]", options: [.regularExpression, .caseInsensitive])
        }
        return t
    }

    /// Schickt neue Protokolleinträge (höchstens 200 je Abgleich) über den eigenen Server
    @MainActor static func send(_ context: ModelContext, api: API, profileName: String?) async {
        guard enabled else { return }
        let d = UserDefaults.standard
        let sentUpTo = Int64(d.integer(forKey: "anonSentUpTo"))
        let new = context.allEntries().filter { $0.module == "coachlog" && !$0.deleted && $0.updated > sentUpTo }
            .sorted { $0.updated < $1.updated }.prefix(200)
        guard !new.isEmpty else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let items: [[String: Any]] = new.map { e in
            var it: [String: Any] = [
                "kind": e.text("kind") ?? "", "persona": e.text("persona") ?? "", "source": e.text("source") ?? "",
                "ms": e.num("ms") ?? 0, "setDetected": (e.num("reps") ?? 0) > 0, "rest": e.num("rest") ?? 0,
                "app": version, "ios": UIDevice.current.systemVersion.components(separatedBy: ".").first ?? "",
                "lang": Locale.current.language.languageCode?.identifier ?? "", "onDevice": OnDevice.available,
            ]
            if withTexts {
                // Längen wie vom Hauptserver erlaubt (sonst wird der Eintrag verworfen)
                it["heard"] = String(scrub(e.text("heard") ?? "", name: profileName).prefix(900))
                it["reply"] = String(scrub(e.text("reply") ?? "", name: profileName).prefix(2800))
                it["exercise"] = String((e.text("exercise") ?? "").prefix(70))
            }
            return it
        }
        if (try? await api.call("POST", "/api/telemetry", json: ["items": items])) != nil, let last = new.last {
            d.set(Int(last.updated), forKey: "anonSentUpTo")
        }
    }
}
