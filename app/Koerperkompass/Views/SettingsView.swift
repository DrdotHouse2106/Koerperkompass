import SwiftData
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
    @State private var askName = false
    @State private var memberName = ""
    @Environment(\.modelContext) private var modelContext
    @AppStorage("motivationOn") private var motivationOn = false
    @AppStorage("motivationHour") private var motivationHour = 8
    @AppStorage("motivationEvening") private var motivationEvening = false
    @AppStorage("motivationEveningHour") private var motivationEveningHour = 19

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Mein Plan") { GoalsView() }
                    NavigationLink("Profil & Ziele") { SetupView(editing: true) }
                }
                Section {
                    Toggle("Motivierende Erinnerungen", isOn: $motivationOn)
                    if motivationOn {
                        Stepper("Morgens um \(motivationHour) Uhr", value: $motivationHour, in: 5...12)
                        Toggle("Zusätzlich abends", isOn: $motivationEvening)
                        if motivationEvening {
                            Stepper("Abends um \(motivationEveningHour) Uhr", value: $motivationEveningHour, in: 16...22)
                        }
                    }
                } header: { Text("Erinnerungen") } footer: {
                    Text("Jeden Tag ein anderer Spruch – persönlich mit deinem Namen, deiner Serie und deinem Ziel. Trinkerinnerung unter Getränke, Coach-Erinnerung im Coach.")
                }
                .onChange(of: [motivationOn ? 1 : 0, motivationHour, motivationEvening ? 1 : 0, motivationEveningHour]) {
                    Task { await refreshMotivation(state, modelContext) }
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
                        Button("Weitere Person einladen", systemImage: "person.badge.plus") { memberName = ""; askName = true }
                        NavigationLink("Meine Geräte") { DevicesView() }
                    } header: { Text("Server") } footer: {
                        Text("Eingeladene Personen bekommen ein eigenes Konto mit eigenem Zugang auf deinem Server und sehen nur ihre eigenen Daten.")
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
                    Link("Datenschutz", destination: URL(string: "https://github.com/DrdotHouse2106/Koerperkompass/blob/main/PRIVACY.md")!)
                    Link("Anleitung & Quellcode", destination: URL(string: "https://github.com/DrdotHouse2106/Koerperkompass")!)
                } footer: {
                    Text("Version \(appVersion) · Alle Werte sind Schätzungen und keine ärztliche Beratung.")
                }
            }
            .themed()
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
            .alert("Weitere Person einladen", isPresented: $askName) {
                TextField("Name", text: $memberName)
                Button("Einladen") { createInvite(sameUser: false, name: memberName) }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die Person bekommt ein eigenes Konto. Ihre Daten bleiben getrennt von deinen.")
            }
            .sheet(item: $invite) { InviteView(link: $0.link) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { importFile(url) }
            }
        }
    }

    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    private func createInvite(sameUser: Bool, name: String = "") {
        Task {
            do {
                let r = try await state.api.object("POST", "/api/invite", json: ["sameUser": sameUser, "name": name])
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
    var note: LocalizedStringKey = "Mit der Kamera oder in der Körperkompass-App scannen. Der Code ist einmalig und 24 Stunden gültig."
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = qr(link) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 260, height: 260)
                }
                Text(note)
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

/// Eigene gekoppelte Geräte – Zugang einzelner Geräte widerrufen (z. B. bei Verlust)
struct DevicesView: View {
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var devices: [[String: Any]] = []
    @State private var error: String?

    var body: some View {
        List {
            if !name.isEmpty { LabeledContent("Konto", value: name) }
            Section {
                ForEach(devices.indices, id: \.self) { i in
                    let d = devices[i]
                    HStack {
                        Text(d["device"] as? String ?? "–")
                        Spacer()
                        if d["current"] as? Bool == true { Text("Dieses Gerät").foregroundStyle(.secondary) }
                    }
                    .deleteDisabled(d["current"] as? Bool == true)
                }
                .onDelete { idx in idx.forEach { remove(devices[$0]) } }
            } footer: { Text("Zum Entfernen nach links wischen. Das Gerät muss danach neu gekoppelt werden.") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Meine Geräte")
        .task { await load() }
    }

    private func load() async {
        do {
            let r = try await state.api.object("GET", "/api/me")
            name = r["name"] as? String ?? ""
            devices = r["devices"] as? [[String: Any]] ?? []
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ d: [String: Any]) {
        guard let id = (d["id"] as? NSNumber)?.intValue else { return }
        Task {
            _ = try? await state.api.call("DELETE", "/api/devices/\(id)")
            await load()
        }
    }
}

/// Motivierende Erinnerungen nach den gespeicherten Einstellungen neu planen (auch beim Öffnen der App)
@MainActor func refreshMotivation(_ state: AppState, _ context: ModelContext) async {
    let d = UserDefaults.standard
    guard d.bool(forKey: "motivationOn") else { Motivation.cancel(); return }
    var hours = [d.object(forKey: "motivationHour") as? Int ?? 8]
    if d.bool(forKey: "motivationEvening") { hours.append(d.object(forKey: "motivationEveningHour") as? Int ?? 19) }
    await Motivation.schedule(hours: hours, profile: state.profile, streak: QuestProgress(context.allEntries(), state.profile).streak)
}
