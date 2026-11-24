import SwiftUI

/// Einstellungen → Verschlüsselung: Ende-zu-Ende-Verschlüsselung (Pflicht – der Server nimmt nur Verschlüsseltes an),
/// Wiederherstellungsschlüssel sichern, zusätzliches Passwort festlegen
struct VaultView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var password = ""
    @State private var repeated = ""
    @State private var recovery: String?
    @State private var saved = false
    @State private var busy = false
    @State private var message: String?

    private var valid: Bool { password.count >= 8 && password == repeated }

    var body: some View {
        Form {
            if let recovery = recovery ?? state.pendingRecovery {
                Section {
                    Text(recovery).font(.title3.monospaced().bold()).textSelection(.enabled).frame(maxWidth: .infinity)
                    Button("Kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = recovery }
                    ShareLink("Sichern (z. B. in Passwörtern oder Notizen)", item: String(localized: "Körperkompass-Wiederherstellungsschlüssel: \(recovery)"))
                    Toggle("Ich habe den Schlüssel sicher aufbewahrt", isOn: $saved)
                    Button("Fertig") { self.recovery = nil; state.pendingRecovery = nil }.disabled(!saved)
                } header: { Text("Dein Wiederherstellungsschlüssel") } footer: {
                    Text("Dein Schlüssel liegt im iCloud-Schlüsselbund und ist auf deinen Geräten mit derselben Apple-ID automatisch da. Ist der Schlüsselbund aus oder weg, öffnest du deine Daten nur mit diesem Wiederherstellungsschlüssel – bewahre ihn sicher auf. Niemand sonst kann deine Daten wiederherstellen, auch nicht der Betreiber des Servers.")
                }
            } else if Vault.enabled {
                Section {
                    Label("Deine Daten sind Ende-zu-Ende-verschlüsselt", systemImage: "lock.fill").foregroundStyle(.green)
                } footer: {
                    Text("Einträge und Profil werden auf dem iPhone verschlüsselt. Der Server sieht nur Modul, Datum und Zeitpunkt der Einträge, nie die Inhalte. Der Schlüssel liegt in deinem iCloud-Schlüsselbund – auf einem neuen iPhone mit derselben Apple-ID sind deine Daten so ohne Passwort wieder da.")
                }
                Section {
                    SecureField("Neues Passwort (mind. 8 Zeichen)", text: $password).textContentType(.newPassword)
                    SecureField("Wiederholen", text: $repeated).textContentType(.newPassword)
                    Button("Passwort festlegen") { run { try await state.changeVaultPassword(password); password = ""; repeated = ""; message = String(localized: "Passwort gespeichert.") } }
                        .disabled(!valid || busy)
                } header: { Text("Zusätzliches Passwort (optional)") } footer: {
                    Text("Nur nötig, wenn du ohne iCloud-Schlüsselbund auf weitere Geräte willst. Das alte Passwort brauchst du hier nicht.")
                }
            } else {
                Section {
                    SecureField("Passwort (mind. 8 Zeichen)", text: $password).textContentType(.newPassword)
                    SecureField("Wiederholen", text: $repeated).textContentType(.newPassword)
                    Button(busy ? LocalizedStringKey("Wird eingerichtet …") : "Verschlüsselung einrichten", systemImage: "lock") {
                        run { recovery = try await state.enableVault(password: password, context); password = ""; repeated = "" }
                    }
                    .disabled(!valid || busy)
                } header: { Text("Ende-zu-Ende-Verschlüsselung") } footer: {
                    Text("Deine Einträge und dein Profil werden mit deinem Passwort verschlüsselt, bevor sie das iPhone verlassen – der Server und sein Betreiber können sie nicht lesen. Du bekommst einen Wiederherstellungsschlüssel für den Fall, dass du das Passwort vergisst. Vergisst du beides, sind die Daten auf dem Server verloren. Freiwillige Protokolle und anonyme Verbesserungsdaten kannst du weiterhin getrennt einschalten.")
                }
            }
            if let message { Text(message).font(.caption) }
        }
        .themed()
        .navigationTitle("Verschlüsselung")
    }

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do { try await action() } catch { message = error.localizedDescription }
        }
    }
}

/// Neues Gerät oder Schlüssel fehlt: Passwort oder Wiederherstellungsschlüssel eingeben
struct VaultUnlockView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var password = ""
    @State private var recovery = ""
    @State private var useRecovery = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if useRecovery {
                        TextField("XXXXXX-XXXXXX-XXXXXX-XXXXXX", text: $recovery).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    } else {
                        SecureField("Passwort", text: $password).textContentType(.password)
                    }
                    Button(busy ? LocalizedStringKey("Wird entsperrt …") : "Entsperren", systemImage: "lock.open") { unlock() }
                        .disabled(busy || (useRecovery ? recovery.isEmpty : password.isEmpty))
                    if let error { Text(error).foregroundStyle(.red) }
                } footer: {
                    Text("Deine Daten sind Ende-zu-Ende-verschlüsselt, der Schlüssel ist auf diesem Gerät nicht da (iCloud-Schlüsselbund aus oder andere Apple-ID). Gib dein Passwort oder den Wiederherstellungsschlüssel ein.")
                }
                Section {
                    Button(useRecovery ? LocalizedStringKey("Doch mit Passwort") : "Passwort vergessen?") { useRecovery.toggle(); error = nil }
                } footer: {
                    if useRecovery { Text("Mit dem Wiederherstellungsschlüssel entsperrst du deine Daten. Danach kannst du unter Einstellungen → Verschlüsselung ein neues Passwort setzen.") }
                }
            }
            .themed()
            .navigationTitle("Verschlüsselt")
        }
    }

    private func unlock() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await state.unlockVault(password: useRecovery ? nil : password, recovery: useRecovery ? recovery : nil, context)
            } catch { self.error = error.localizedDescription }
        }
    }
}
