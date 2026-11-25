import CryptoKit
import SwiftData
import SwiftUI

/// Claude-Connector: Körperkompass in der Claude-App (eigenes Abo) nutzen – siehe server/mcp.go.
/// Die App erzeugt einen Freigabe-Schlüssel, verschlüsselt damit eine Kurzfassung der Daten und lädt sie hoch;
/// der Schlüssel geht nur einmal (beim Verbinden) an den Server weiter, der ihn in Claudes Zugangstoken packt und
/// nicht speichert. Von Claude eingetragene Vorschläge holt die App beim Abgleich aus dem Eingangskorb.
enum ClaudeShare {
    static var key: SymmetricKey? {
        get { Keychain.get("claudeShareKey").flatMap { Data(base64Encoded: $0) }.map { SymmetricKey(data: $0) } }
        set { Keychain.set("claudeShareKey", newValue.map { $0.withUnsafeBytes { Data($0) }.base64EncodedString() }, sync: true) }
    }
    static var connected: Bool { key != nil }

    /// Kurzfassung für Claude: dieselben Angaben wie für den Coach (heute, 7 Tage, Ziele, Rezepte)
    @MainActor static func snapshot(_ state: AppState, _ context: ModelContext) -> String {
        "Stand: \(Date().formatted(date: .complete, time: .shortened))\n"
            + coachContext(context.allEntries(), state.profile, healthUpload: state.healthUpload)
    }

    static func seal(_ text: String, _ key: SymmetricKey) -> String {
        (try? AES.GCM.seal(Data(text.utf8), using: key).combined?.base64EncodedString()) ?? ""
    }

    /// Verbinden: Code von der Claude-Anmeldeseite bestätigen
    @MainActor static func approve(_ code: String, _ state: AppState, _ context: ModelContext) async throws {
        let key = SymmetricKey(size: .bits256)
        _ = try await state.api.call("POST", "/api/claude/approve", json: [
            "req": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "key": key.withUnsafeBytes { Data($0) }.base64EncodedString(),
            "blob": seal(snapshot(state, context), key),
        ])
        self.key = key
        state.aiConsent = true  // ausdrückliche Freigabe an Claude
    }

    @MainActor static func disconnect(_ state: AppState) async {
        _ = try? await state.api.call("DELETE", "/api/claude/share")
        key = nil
    }

    /// Beim Abgleich: Kurzfassung erneuern und Einträge aus Claude übernehmen
    @MainActor static func sync(_ state: AppState, _ context: ModelContext) async {
        guard let key, state.aiConsent else { return }
        _ = try? await state.api.call("PUT", "/api/claude/share", json: ["blob": seal(snapshot(state, context), key)])
        guard let data = try? await state.api.call("GET", "/api/claude/inbox"),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
        for item in list {
            guard let id = item["id"], let blob = item["blob"] else { continue }
            if let d = Data(base64Encoded: blob), let box = try? AES.GCM.SealedBox(combined: d),
               let raw = try? AES.GCM.open(box, using: key), let p = try? JSONDecoder().decode(CoachView.Proposal.self, from: raw) {
                p.apply(context, state)
                AppLog.add("Claude-Connector: Eintrag übernommen")
            }
            _ = try? await state.api.call("DELETE", "/api/claude/inbox/\(id)")
        }
    }
}

/// Einstellungen → Claude-Connector
struct ClaudeConnectView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State var code = ""
    @State private var busy = false
    @State private var message: String?
    @State private var connected = ClaudeShare.connected

    private var url: String { state.server.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/mcp" }

    var body: some View {
        Form {
            if connected {
                Section {
                    Label("Mit Claude verbunden", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Button("Verbindung trennen", role: .destructive) {
                        Task { await ClaudeShare.disconnect(state); connected = false }
                    }
                } footer: {
                    Text("Claude sieht eine Kurzfassung deiner Daten (heute, letzte 7 Tage, Ziele) und kann Essen, Getränke, Gewicht, Stimmung und Beschwerden eintragen. Trennen löscht die Freigabe auf dem Server.")
                }
            }
            Section {
                LabeledContent("Adresse") { Text(url).font(.caption.monospaced()).textSelection(.enabled) }
                Button("Adresse kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = url }
            } header: { Text("1. In Claude hinzufügen") } footer: {
                Text("Claude-App oder claude.ai → Einstellungen → Connectors → Benutzerdefinierten Connector hinzufügen → Name „Körperkompass“ und diese Adresse. Danach „Verbinden“ tippen.")
            }
            Section {
                TextField("Code von der Anmeldeseite", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button(busy ? LocalizedStringKey("Wird verbunden …") : "Freigeben", systemImage: "checkmark.shield") {
                    busy = true
                    message = nil
                    Task {
                        defer { busy = false }
                        do {
                            try await ClaudeShare.approve(code, state, context)
                            connected = true
                            code = ""
                            message = String(localized: "Verbunden – zurück zu Claude, die Seite leitet gleich weiter.")
                        } catch { message = error.localizedDescription }
                    }
                }
                .disabled(code.count < 8 || busy)
                if let message { Text(message).font(.caption) }
            } header: { Text("2. Freigeben") } footer: {
                Text("Mit der Freigabe geht eine Kurzfassung deiner Daten verschlüsselt an deinen Server; den Schlüssel bekommt nur Claude. Gelesen wird sie nur, wenn Claude in deinem Auftrag fragt – dabei gehen die Daten an Anthropic. Keine ärztliche Beratung.")
            }
        }
        .themed()
        .navigationTitle("Claude-Connector")
    }
}
