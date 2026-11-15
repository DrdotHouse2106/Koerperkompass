import SwiftData
import SwiftUI

@main
struct KoerperkompassApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView().environment(state)
        }
        .modelContainer(for: Entry.self)
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
            } else if !state.profile.isSetUp {
                NavigationStack { SetupView() }
            } else {
                MainView()
            }
        }
        .onOpenURL { state.pendingLink = $0 }
        .onChange(of: phase) {
            if phase == .active {
                Task {
                    await state.importHealth(context)
                    await state.sync(context)
                }
            }
        }
    }
}

struct MainView: View {
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Heute", systemImage: "square.grid.2x2") }
            CompassView().tabItem { Label("Kompass", systemImage: "safari") }
            SettingsView().tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
    }
}

/// Übersicht: eine Kachel pro aktivem Modul
struct DashboardView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.date) private var entries: [Entry]

    var body: some View {
        NavigationStack {
            ScrollView {
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
                        let list = entries.filter { $0.module == m.id && !$0.deleted }
                        NavigationLink {
                            m.detail(list).navigationTitle(Text(m.name))
                        } label: {
                            m.tile(list)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Heute")
            .refreshable {
                await state.importHealth(context)
                await state.sync(context)
            }
        }
    }
}
