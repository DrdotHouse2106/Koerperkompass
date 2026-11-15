import SwiftUI
import VisionKit

/// Erster Start: Server-Adresse eingeben oder QR-Code scannen, Verbindung testen, koppeln – oder Demo starten.
struct ConnectView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var server = ""
    @State private var code = ""
    @State private var message: String?
    @State private var error: String?
    @State private var busy = false
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "safari").font(.largeTitle).foregroundStyle(.tint)
                        Text("Willkommen beim Körperkompass").font(.title2.bold())
                        Text("Deine Daten liegen auf deinem eigenen Server. Starte ihn (siehe Anleitung auf GitHub) und kopple die App mit dem Code aus dem Server-Log oder der Weboberfläche.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section("Eigener Server") {
                    TextField("https://kompass.example.de", text: $server)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Kopplungscode", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("QR-Code scannen", systemImage: "qrcode.viewfinder") { scanning = true }
                }
                Section {
                    Button("Verbindung testen", action: test).disabled(server.isEmpty || busy)
                    Button("Koppeln", action: connect).disabled(server.isEmpty || code.isEmpty || busy)
                    if busy { ProgressView() }
                    if let message { Text(message).foregroundStyle(.green) }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button("Demo ausprobieren", systemImage: "play.circle") { state.startDemo(context) }
                } footer: {
                    Text("Mit Beispieldaten, ganz ohne Server. Es werden keine Daten übertragen.")
                }
            }
            .navigationTitle("Körperkompass")
            .sheet(isPresented: $scanning) {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScanner { text in
                        scanning = false
                        apply(text)
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView("Scanner nicht verfügbar", systemImage: "camera", description: Text("Bitte Adresse und Code von Hand eingeben."))
                }
            }
            .onAppear { if let link = state.pendingLink { apply(link.absoluteString) } }
            .onChange(of: state.pendingLink) { if let link = state.pendingLink { apply(link.absoluteString) } }
        }
    }

    private func apply(_ text: String) {
        state.pendingLink = nil
        guard let link = AppState.parse(text) else {
            error = String(localized: "Kein Körperkompass-QR-Code")
            return
        }
        server = link.server
        code = link.code
        connect()
    }

    private func test() {
        run {
            let s = try await API(server: API.normalize(server)).status()
            message = String(localized: "Verbunden mit Server-Version \(s.version)") + (s.ai ? " · Claude API aktiv" : "")
        }
    }

    private func connect() {
        run { try await state.connect(server: server, code: code, context: context) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        message = nil
        error = nil
        Task {
            defer { busy = false }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }
}

/// QR-Scanner mit VisionKit
struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        var done = false
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(b) in addedItems {
                if let text = b.payloadStringValue, !done {
                    done = true
                    found(text)
                }
            }
        }
    }
}
