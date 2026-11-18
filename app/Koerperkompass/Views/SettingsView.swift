import SwiftData
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var askHealthUpload = false
    @State private var askLocalOnly = false
    @State private var localError: String?
    @State private var invite: Invite?
    @State private var exportFile: URL?
    @State private var importing = false
    @State private var confirmReset = false
    @State private var message: String?
    @State private var askName = false
    @State private var memberName = ""
    @Environment(\.modelContext) private var modelContext
    @AppStorage("anonShare") private var anonShare = false
    @AppStorage("anonTexts") private var anonTexts = false
    @State private var askAnon = false
    @AppStorage("motivationOn") private var motivationOn = false
    @AppStorage("motivationHour") private var motivationHour = 8
    @AppStorage("motivationEvening") private var motivationEvening = false
    @AppStorage("motivationEveningHour") private var motivationEveningHour = 19

    @AppStorage("appLogOn") private var appLogOn = false

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Mein Plan") { GoalsView() }
                    NavigationLink("Über mich – Geräte und was dein Coach weiß") { AboutMeView() }
                    if !state.demo {
                        NavigationLink { VaultView() } label: {
                            Label(Vault.enabled ? LocalizedStringKey("Verschlüsselung: an") : "Verschlüsselung mit Passwort", systemImage: Vault.enabled ? "lock.fill" : "lock.open")
                        }
                    }
                    NavigationLink("Gesprächsprotokoll (Testphase)") { CoachLogView() }
                    NavigationLink("Profil & Ziele") { SetupView(editing: true) }
                }
                Section {
                    Toggle("Erweitertes Protokoll (Testphase)", isOn: $appLogOn)
                } footer: {
                    Text("Meldet Abläufe wie Tippen, Abgleich, Server-Aufrufe und Fehler an deinen eigenen Server, damit Fehler gefunden werden können – nur Kennungen und Zeitstempel, keine Gesundheitswerte. Wird nicht weitergegeben.")
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
                    Text("Jeden Tag ein anderer Spruch – persönlich mit deinem Namen, deiner Serie und deinem Ziel. Mit Claude auf dem Server (und deiner Zustimmung) schreibt dir dein Coach einmal am Tag eigene Sprüche passend zu deinen Daten. Trinkerinnerung unter Getränke, Coach-Erinnerung im Coach.")
                }
                .onChange(of: [motivationOn ? 1 : 0, motivationHour, motivationEvening ? 1 : 0, motivationEveningHour]) {
                    Task { await refreshMotivation(state, modelContext) }
                }
                Section {
                    NavigationLink { VoiceSettingsView() } label: {
                        LabeledContent("Stimme der Coaches", value: Speaker.voice().map { "\($0.name) (\(Speaker.qualityName($0)))" } ?? "–")
                    }
                }
                Section("Module") {
                    ForEach(allModules, id: \.id) { m in
                        Toggle(isOn: Binding(
                            get: { state.profile.modules.contains(m.id) },
                            set: { on in state.profile.modules = allModules.map(\.id).filter { $0 == m.id ? on : state.profile.modules.contains($0) } }
                        )) { Label { Text(m.name) } icon: { Image(systemName: m.symbol) } }
                    }
                }
                if !state.demo {
                    Section {
                        Toggle("Nur auf diesem iPhone speichern", isOn: Binding(
                            get: { state.localOnly },
                            set: { on in
                                if on { askLocalOnly = true } else { Task { try? await state.setLocalOnly(false, context) } }
                            }))
                        if let localError { Text(localError).foregroundStyle(.red) }
                    } header: { Text("Speicherort") } footer: {
                        Text(state.localOnly
                             ? LocalizedStringKey("Deine Daten liegen nur auf diesem iPhone. Dein Server leitet nur noch Anfragen an Claude und die Stimme weiter und speichert nichts. Sichere deine Daten ab und zu über „Export erstellen“.")
                             : "Deine Daten werden auf deinem eigenen Server gespeichert und abgeglichen – so bleiben sie auch bei Verlust des iPhones erhalten und sind auf weiteren Geräten verfügbar.")
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
                if !state.demo {
                    Section {
                        Toggle("Anonyme Daten teilen", isOn: Binding(get: { anonShare }, set: { if $0 { askAnon = true } else { anonShare = false; anonTexts = false } }))
                        if anonShare {
                            Toggle("Gesprächstexte mitsenden", isOn: $anonTexts)
                        }
                    } header: { Text("App verbessern (freiwillig)") } footer: {
                        Text("Schickt anonym, wie gut die Coaches funktionieren (Stil, Modell, Antwortzeit, ob ein Satz erkannt wurde) über deinen Server an die Entwickler. Keine Kennung, keine Gesundheitswerte. Gesprächstexte nur, wenn du sie zusätzlich freigibst – Namen, E-Mail-Adressen, Telefonnummern und Links werden vorher entfernt.")
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
            .alert("Anonyme Daten teilen?", isPresented: $askAnon) {
                Button("Ja, teilen") { anonShare = true }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Dein Server leitet anonyme Angaben zu den Coach-Gesprächen an die Entwickler von Körperkompass weiter, damit die App besser wird. Es werden keine Gesundheitswerte und keine Kennung übertragen. Du kannst das jederzeit wieder ausschalten.")
            }
            .alert("Nur auf diesem iPhone speichern?", isPresented: $askLocalOnly) {
                Button("Server-Daten löschen", role: .destructive) {
                    Task {
                        do { try await state.setLocalOnly(true, context); localError = nil } catch { localError = error.localizedDescription }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle auf deinem Server gespeicherten Einträge, dein Profil, deine Spielerkarte und das Protokoll werden dort gelöscht. In Sicherungen des Servers (falls vorhanden) bleiben sie, bis diese überschrieben werden. Danach bleibt alles nur auf diesem iPhone. Geht das iPhone verloren, sind die Daten weg – außer in einem iPhone-Backup oder einem Export. Freunde sehen deine Spielerkarte nicht mehr. Du kannst es jederzeit wieder ausschalten; dann wird alles erneut hochgeladen.")
            }
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
    let streak = QuestProgress(context.allEntries(), state.profile).streak
    // Einmal am Tag persönliche Sprüche für heute und morgen: auf dem iPhone mit Apple Intelligence (kostenlos),
    // sonst – mit Key und Zustimmung – Claude Haiku über den Server
    var personal = d.stringArray(forKey: "aiMotivation") ?? []
    if d.string(forKey: "aiMotivationDay") != Day.today {
        let ctx = coachContext(context.allEntries(), state.profile, healthUpload: true)  // bleibt bei Apple Intelligence auf dem Gerät
        var list = await OnDevice.motivation(count: hours.count * 2, context: ctx) ?? []
        if list.isEmpty && state.aiAvailable && state.aiConsent,
           let r = try? await state.api.object("POST", "/api/ai/motivation", json: [
               "context": coachContext(context.allEntries(), state.profile, healthUpload: state.healthUpload),
               "count": hours.count * 2, "lang": Locale.current.language.languageCode?.identifier ?? "de",
           ]) {
            list = r["messages"] as? [String] ?? []
        }
        if !list.isEmpty {
            personal = list
            d.set(list, forKey: "aiMotivation")
            d.set(Day.today, forKey: "aiMotivationDay")
        }
    }
    if d.string(forKey: "aiMotivationDay") != Day.today { personal = [] }  // alte Sprüche nicht erneut verwenden
    await Motivation.schedule(hours: hours, profile: state.profile, streak: streak, personal: personal)
}

/// Stimme der Coaches wählen und probehören
struct VoiceSettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("voiceID") private var voiceID = ""
    @AppStorage("serverVoice") private var serverVoice = true
    @AppStorage("serverVoicePreset") private var preset = ""
    @State private var speaker = Speaker()

    var body: some View {
        List {
            if state.ttsAvailable {
                Section {
                    Toggle("Stimme von meinem Server", isOn: $serverVoice)
                    if serverVoice {
                        Picker("Stimme vom Server", selection: $preset) {
                            Text("Passend zum Coach-Stil").tag("")
                            ForEach(Speaker.serverVoices) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.inline)
                        .onChange(of: preset) {
                            if !preset.isEmpty { probe(preset, String(localized: "Hallo! Ich bin dein Coach. Auf geht’s – noch zwei Wiederholungen, du schaffst das!")) }
                        }
                        if preset.isEmpty {
                            ForEach(Persona.allCases) { p in
                                Button("\(p.emoji) \(String(localized: p.title)) probehören") { probe(p.rawValue, String(localized: p.cheers.first!)) }
                            }
                        }
                    }
                } footer: {
                    Text("Dein Server erzeugt natürlichere Stimmen (Kartoffelbox bzw. Piper) – je Coach-Stil mit eigenem Tonfall. Ohne Verbindung spricht die iPhone-Stimme unten.")
                }
            }
            Section {
                Picker("iPhone-Stimme", selection: $voiceID) {
                    Text("Automatisch (beste installierte)").tag("")
                    ForEach(Speaker.voices, id: \.identifier) { v in
                        Text("\(v.name) · \(Speaker.qualityName(v))").tag(v.identifier)
                    }
                }
                .pickerStyle(.inline)
                Button("Probehören", systemImage: "speaker.wave.2.fill") {
                    speaker.api = nil
                    speaker.speak(String(localized: "Hallo! Ich bin dein Coach. Auf geht’s – noch zwei Wiederholungen, du schaffst das!"))
                }
            } footer: {
                Text("Bessere Stimmen klingen deutlich natürlicher. So lädst du sie: iOS-Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen → Deutsch → eine Stimme mit „Premium“ oder „Erweitert“ wählen und laden (z. B. Anna, Petra, Markus oder Yannick). Danach hier auswählen. Die Siri-Stimme selbst steht Apps leider nicht zur Verfügung.")
            }
        }
        .themed()
        .navigationTitle("Stimme")
    }

    private func probe(_ persona: String, _ text: String) {
        speaker.api = state.api
        speaker.persona = persona
        speaker.speak(text)
    }
}
