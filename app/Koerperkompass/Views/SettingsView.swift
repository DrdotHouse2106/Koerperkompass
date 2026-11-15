import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var askHealthUpload = false
    @State private var invite: Invite?
    @State private var exportFile: URL?
    @State private var importing = false
    @State private var confirmReset = false
    @State private var message: String?

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Profil & Ziele") { SetupView(editing: true) }
                }
                Section("Module") {
                    ForEach(allModules, id: \.id) { m in
                        Toggle(isOn: Binding(
                            get: { state.profile.modules.contains(m.id) },
                            set: { on in state.profile.modules = allModules.map(\.id).filter { $0 == m.id ? on : state.profile.modules.contains($0) } }
                        )) { Label { Text(m.name) } icon: { Image(systemName: m.symbol) } }
                    }
                }
                if Health.available && !state.demo {
                    Section {
                        Button(state.healthEnabled ? LocalizedStringKey("Health-Freigaben erneut anfragen") : "Apple Health verbinden", systemImage: "heart") {
                            Task { await state.connectHealth(); await state.importHealth(context) }
                        }
                        Toggle("Health-Daten an meinen Server senden", isOn: Binding(
                            get: { state.healthUpload },
                            set: { if $0 { askHealthUpload = true } else { state.setHealthUpload(false, context) } }
                        ))
                    } header: { Text("Apple Health") } footer: {
                        Text("Ohne Zustimmung bleiben Health-Daten nur auf diesem Gerät. Einzelne Freigaben änderst du in der Health-App.")
                    }
                }
                if state.aiAvailable {
                    Section {
                        Toggle("Daten zur Analyse an Claude senden", isOn: $state.aiConsent)
                    } header: { Text("Claude API") } footer: {
                        Text("Fotos und zusammengefasste Werte gehen nur nach deiner Zustimmung über deinen Server an Anthropic. Keine ärztliche Beratung.")
                    }
                }
                if state.demo {
                    Section {
                        Button("Demo beenden und Server verbinden", role: .destructive) { state.reset(context) }
                    } footer: { Text("Alle Beispieldaten werden gelöscht.") }
                } else {
                    Section {
                        LabeledContent("Adresse", value: state.server)
                        LabeledContent("Version", value: state.serverVersion)
                        if let error = state.syncError { Text(error).foregroundStyle(.orange) }
                        Button("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath") { Task { await state.sync(context) } }
                        Button("Weiteres eigenes Gerät koppeln", systemImage: "iphone") { createInvite(sameUser: true) }
                        Button("Familienmitglied einladen", systemImage: "person.badge.plus") { createInvite(sameUser: false) }
                    } header: { Text("Server") } footer: {
                        Text("Familienmitglieder bekommen ein eigenes Konto auf deinem Server und sehen nur ihre eigenen Daten.")
                    }
                }
                Section("Daten") {
                    Button("Export erstellen (JSON)", systemImage: "square.and.arrow.up") { exportFile = makeExport() }
                    if let exportFile { ShareLink("Export teilen", item: exportFile) }
                    Button("Import (JSON)", systemImage: "square.and.arrow.down") { importing = true }
                    if let message { Text(message).foregroundStyle(.secondary) }
                    if !state.demo {
                        Button("Verbindung trennen", role: .destructive) { confirmReset = true }
                    }
                }
                Section {
                    Link("Datenschutz", destination: URL(string: "https://github.com/DrdotHouse2106/K-rperkompass/blob/main/PRIVACY.md")!)
                    Link("Anleitung & Quellcode", destination: URL(string: "https://github.com/DrdotHouse2106/K-rperkompass")!)
                } footer: {
                    Text("Version \(appVersion) · Alle Werte sind Schätzungen und keine ärztliche Beratung.")
                }
            }
            .navigationTitle("Einstellungen")
            .alert("Health-Daten hochladen?", isPresented: $askHealthUpload) {
                Button("Zustimmen") { state.setHealthUpload(true, context) }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Schritte, aktive Energie, Schlaf, Ruhepuls, Trainings und Gewicht aus Apple Health werden an deinen eigenen Server übertragen und dort gespeichert. Du kannst das jederzeit wieder ausschalten.")
            }
            .confirmationDialog("Verbindung trennen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Trennen und lokale Daten löschen", role: .destructive) { state.reset(context) }
            } message: {
                Text("Die Daten auf deinem Server bleiben erhalten.")
            }
            .sheet(item: $invite) { InviteView(link: $0.link) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { importFile(url) }
            }
        }
    }

    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    private func createInvite(sameUser: Bool) {
        Task {
            do {
                let r = try await state.api.object("POST", "/api/invite", json: ["sameUser": sameUser])
                if let code = r["code"] as? String {
                    var c = URLComponents()
                    c.scheme = "koerperkompass"
                    c.host = "pair"
                    c.queryItems = [URLQueryItem(name: "server", value: state.server), URLQueryItem(name: "code", value: code)]
                    invite = c.string.map { Invite(link: $0) }
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// Export im selben Format wie GET /api/export des Servers
    private func makeExport() -> URL? {
        let profile = (try? JSONEncoder().encode(state.profile)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]
        let json: [String: Any] = [
            "version": 1, "exported": ISO8601DateFormatter().string(from: Date()), "profile": profile,
            "entries": context.allEntries().filter { !$0.deleted }.map(\.json),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("koerperkompass-export.json")
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            message = String(localized: "Datei konnte nicht gelesen werden")
            return
        }
        let entries = json["entries"] as? [[String: Any]] ?? []
        for e in entries {
            guard let id = e["id"] as? String, let module = e["module"] as? String, let date = e["date"] as? String else { continue }
            context.upsert(id: id, module: module, date: date, values: e["data"] as? [String: Any] ?? [:], dirty: !state.demo)
        }
        if let p = json["profile"], let pd = try? JSONSerialization.data(withJSONObject: p), let profile = try? JSONDecoder().decode(Profile.self, from: pd) {
            state.profile = profile
        }
        state.changed(context)
        message = String(localized: "\(entries.count) Einträge importiert")
    }
}

struct Invite: Identifiable {
    let link: String
    var id: String { link }
}

/// Zeigt einen Kopplungslink als QR-Code
struct InviteView: View {
    let link: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = qr(link) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 260, height: 260)
                }
                Text("Mit der Kamera oder in der Körperkompass-App scannen. Der Code ist einmalig und 24 Stunden gültig.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                ShareLink("Link teilen", item: link)
            }
            .padding()
            .toolbar { Button("Fertig") { dismiss() } }
        }
    }

    private func qr(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
