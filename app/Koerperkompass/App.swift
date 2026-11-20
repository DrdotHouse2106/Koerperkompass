import SwiftData
import SwiftUI

@main
struct KoerperkompassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
        }
        .modelContainer(sharedContainer)
    }
}

/// Erster Start → Verbinden, danach Einrichtung, danach die App.
struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if !state.isConnected {
                ConnectView()
            } else if state.vaultLocked {
                VaultUnlockView()
            } else if !state.profile.isSetUp {
                NavigationStack { SetupView() }
            } else {
                MainView()
            }
        }
        .onOpenURL { state.pendingLink = $0 }
        .onChange(of: phase) {
            AppLog.add("App \(phase == .active ? "aktiv" : phase == .background ? "im Hintergrund" : "inaktiv")")
            if phase == .background { Task { await AppLog.flush(state.api) } }
            if phase == .active {
                Task {
                    await state.importHealth(context)
                    await state.sync(context)
                    await refreshMotivation(state, context)  // Sprüche für die nächsten 14 Tage auffüllen
                    await Reminders.refresh()  // Trinkerinnerungen für die nächsten Tage nachfüllen
                }
            }
        }
    }
}

struct MainView: View {
    @State private var tab = "heute"
    var body: some View {
        TabView(selection: Binding(get: { tab }, set: { tab = $0; AppLog.add("Tab \($0)") })) {
            DashboardView().tag("heute").tabItem { Label("Heute", systemImage: "square.grid.2x2.fill") }
            TrainingView().tag("training").tabItem { Label("Training", systemImage: "dumbbell.fill") }
            NavigationStack { QuestModule().detail([]).navigationTitle("Abenteuer").themed() }
                .tabItem { Label("Abenteuer", systemImage: "flag.checkered") }.tag("abenteuer")
            CoachView().tag("coach").tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right.fill") }
            SettingsView().tag("einstellungen").tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
    }
}

/// Übersicht: Begrüßung, Schnell-Buttons für Getränke und eine Kachel pro aktivem Modul
struct DashboardView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.date) private var entries: [Entry]

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let base = h < 11 ? String(localized: "Guten Morgen") : h < 18 ? String(localized: "Hallo") : String(localized: "Guten Abend")
        return state.profile.name.map { "\(base), \($0)" } ?? base
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.subheadline).foregroundStyle(.secondary)
                    Text(greeting).font(.largeTitle.bold())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                NavigationLink { MotivationView() } label: {
                    Label("Motivation – Sprüche ohne Ende", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(LinearGradient(colors: [Theme.petrol.opacity(0.5), Theme.orange.opacity(0.4)], startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                if state.profile.modules.contains("water") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schnell eintragen").font(.caption.bold()).foregroundStyle(.secondary)
                        QuickDrinks()
                    }
                    .padding(.horizontal)
                }
                if state.demo {
                    Label("Demo-Modus mit Beispieldaten", systemImage: "play.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = state.syncError {
                    Label("Offline – Änderungen werden später übertragen (\(error))", systemImage: "wifi.slash")
                        .font(.footnote).foregroundStyle(.orange).padding(.horizontal)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(state.activeModules, id: \.id) { m in
                        // Ernährung bekommt zusätzlich Getränke mit Kalorien (Bier, Saft …)
                        let list = entries.filter {
                            !$0.deleted && ($0.module == m.id || (m.id == "nutrition" && $0.module == "water" && ($0.num("kcal") ?? 0) > 0))
                        }
                        NavigationLink {
                            m.detail(list).navigationTitle(Text(m.name)).themed()
                        } label: {
                            m.tile(list)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await state.importHealth(context)
                await state.sync(context)
            }
        }
    }
}
