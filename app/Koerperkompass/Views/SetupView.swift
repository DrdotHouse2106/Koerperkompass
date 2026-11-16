import SwiftUI

/// Einrichtungsassistent nach der Kopplung – später in den Einstellungen erneut aufrufbar.
/// Berechnet die Tagesziele (Mifflin-St-Jeor + Aktivität), die danach von Hand angepasst werden können.
struct SetupView: View {
    var editing = false
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var p = Profile()
    @State private var loaded = false

    var body: some View {
        Form {
            if !editing {
                Section {
                    Text("Ein paar Angaben, damit der Körperkompass passende Tagesziele vorschlagen kann.")
                }
            }
            Section("Ziel") {
                Picker("Ziel", selection: $p.goal) {
                    ForEach(Profile.Goal.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                number("Wunschgewicht", $p.targetWeight, "kg")
            }
            Section("Über dich") {
                TextField("Name (optional)", text: Binding(get: { p.name ?? "" }, set: { p.name = $0.isEmpty ? nil : $0 }))
                number("Gewicht", $p.weight, "kg")
                number("Größe", $p.height, "cm")
                Stepper(value: $p.age, in: 14...110) { Text("Alter: \(p.age)") }
                Picker("Geschlecht", selection: $p.sex) {
                    ForEach(Profile.Sex.allCases, id: \.self) { Text($0.title) }
                }
                Picker("Aktivität", selection: $p.activity) {
                    ForEach(0..<5) { Text(Profile.activityNames[$0]).tag($0) }
                }
            }
            Section {
                ForEach(allModules, id: \.id) { m in
                    Toggle(isOn: Binding(
                        get: { p.modules.contains(m.id) },
                        set: { on in p.modules = allModules.map(\.id).filter { $0 == m.id ? on : p.modules.contains($0) } }
                    )) { Label { Text(m.name) } icon: { Image(systemName: m.symbol) } }
                }
            } header: { Text("Module") }
            if Health.available && !state.demo {
                Section {
                    Button(state.healthEnabled ? LocalizedStringKey("Apple Health ist verbunden") : "Apple Health verbinden", systemImage: "heart") {
                        Task { await state.connectHealth() }
                    }
                } footer: {
                    Text("Optional. Die aktive Energie aus Health verbessert die Berechnung. Health-Daten bleiben auf dem Gerät, bis du dem Hochladen zustimmst.")
                }
            }
            Section {
                Button("Tagesziele berechnen", systemImage: "function") { Task { await compute() } }
                if p.isSetUp {
                    number("Kalorien", $p.kcal, "kcal")
                    number("Eiweiß", $p.protein, "g")
                    number("Kohlenhydrate", $p.carbs, "g")
                    number("Fett", $p.fat, "g")
                }
            } header: { Text("Tagesziele") } footer: {
                Text("Die Werte sind Schätzungen und ersetzen keine ärztliche oder ernährungsfachliche Beratung.")
            }
            Section {
                Button(editing ? LocalizedStringKey("Speichern") : "Los geht’s") {
                    Task {
                        if !p.isSetUp { await compute() }
                        state.profile = p
                        if editing { dismiss() }
                        await state.importHealth(context)
                    }
                }
                .bold()
            }
        }
        .themed()
        .navigationTitle(editing ? LocalizedStringKey("Profil & Ziele") : "Einrichtung")
        .onAppear {
            if !loaded { p = state.profile; loaded = true }
        }
    }

    private func compute() async {
        let active = state.healthEnabled ? await Health.averageActiveEnergy() : nil
        p.computeGoals(activeEnergy: active)
    }

    private func number(_ title: LocalizedStringResource, _ value: Binding<Double>, _ unit: String) -> some View {
        HStack {
            Text(title)
            TextField(unit, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
