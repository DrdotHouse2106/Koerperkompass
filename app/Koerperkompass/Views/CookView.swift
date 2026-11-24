import SwiftUI

/// Kochhilfe: Der Coach begleitet Schritt für Schritt durch ein Rezept – per Text oder Sprache.
/// „Freihändig“ hört nach jeder Antwort wieder zu (Hände frei in der Küche). Der Bildschirm bleibt dabei an.
/// An Claude geht nur das Rezept und das Gespräch, keine Gesundheitsdaten. Der Verlauf wird nicht gespeichert.
struct CookView: View {
    let title: String
    let recipe: String
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [(role: String, text: String)] = []
    @State private var input = ""
    @State private var busy = false
    @State private var error: String?
    @State private var speech = SpeechInput()
    @State private var speaker = Speaker()
    @State private var handsFree = false
    @State private var loop: Task<Void, Never>?
    @State private var askConsent = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, m in
                            Text((try? AttributedString(markdown: m.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(m.text))
                                .padding(12)
                                .background(m.role == "user" ? Theme.orange.opacity(0.35) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                .frame(maxWidth: .infinity, alignment: m.role == "user" ? .trailing : .leading)
                        }
                        if busy { HStack { ProgressView(); Text("Dein Kochcoach überlegt …").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        if speech.listening { Text(speech.heard.isEmpty ? String(localized: "Ich höre zu …") : speech.heard).foregroundStyle(.secondary) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: speech.heard) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { bar }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: Binding(get: { handsFree }, set: { $0 ? startHandsFree() : stopHandsFree() })) {
                        Label("Freihändig", systemImage: handsFree ? "ear.fill" : "ear")
                    }
                    .toggleStyle(.button)
                }
            }
            .alert("Rezept an Claude senden?", isPresented: $askConsent) {
                Button("Zustimmen") { state.aiConsent = true; start() }
                Button("Abbrechen", role: .cancel) { dismiss() }
            } message: {
                Text("Für die Kochhilfe gehen das Rezept und deine Fragen über deinen Server an Claude (Anthropic). Gesundheitsdaten werden nicht gesendet.")
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true  // Bildschirm bleibt beim Kochen an
            if state.aiConsent { start() } else { askConsent = true }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            stopHandsFree()
        }
    }

    private var bar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                Task {
                    if speech.listening { let t = await speech.stop(); if !t.isEmpty { await send(t, speak: true) } }
                    else { speaker.stop(); await speech.start() }
                }
            } label: {
                Image(systemName: speech.listening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title).foregroundStyle(speech.listening ? .red : Theme.orange)
            }
            .disabled(handsFree)
            TextField("Frag beim Kochen …", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...4).focused($focused)
            Button { let t = input; input = ""; Task { await send(t) } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func start() {
        guard messages.isEmpty else { return }
        Task { await send(String(localized: "Ich möchte jetzt kochen. Was muss ich bereitlegen, und was ist der erste Schritt?")) }
    }

    /// speak: Antwort vorlesen und kurz halten (bei Spracheingabe)
    @discardableResult
    private func send(_ text: String, speak: Bool = false) async -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return nil }
        messages.append(("user", text))
        busy = true
        error = nil
        defer { busy = false }
        do {
            let r = try await state.api.object("POST", "/api/ai/coach", json: [
                "messages": messages.suffix(30).map { ["role": $0.role, "content": $0.text] },
                "context": "", "cook": recipe, "voice": speak,
                "lang": Locale.current.language.languageCode?.identifier ?? "de",
            ])
            let reply = r["text"] as? String ?? ""
            messages.append(("assistant", reply))
            if speak {
                speaker.api = state.ttsAvailable ? state.api : nil
                speaker.speak(reply)
            }
            AppLog.add("Kochhilfe: Antwort")
            return reply
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Freihändig: zuhören → fragen → vorlesen → wieder zuhören, bis ausgeschaltet
    private func startHandsFree() {
        focused = false
        handsFree = true
        loop = Task {
            while handsFree && !Task.isCancelled {
                await speaker.waitUntilDone()
                await speech.start()
                let text = await speech.waitForPause(timeout: 120)
                guard handsFree else { break }
                if !text.isEmpty { await send(text, speak: true) }
            }
        }
    }

    private func stopHandsFree() {
        handsFree = false
        loop?.cancel()
        speaker.stop()
        Task { _ = await speech.stop() }
    }
}
