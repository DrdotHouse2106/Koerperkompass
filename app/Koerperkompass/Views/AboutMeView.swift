import SwiftUI

/// Über mich: vorhandene Trainingsgeräte und was der Coach im Gespräch erfahren hat.
/// Beides fließt in Trainingsplan, Anpassungen und Coach-Gespräche ein.
struct AboutMeView: View {
    @Environment(AppState.self) private var state
    @State private var newFact = ""

    var body: some View {
        List {
            Section {
                Toggle("Keine Geräte (nur Körpergewicht)", isOn: Binding(
                    get: { state.profile.equipment == [] },
                    set: { state.profile.equipment = $0 ? [] : nil }))
                ForEach(Profile.equipmentOptions) { e in
                    Toggle(isOn: Binding(
                        get: { state.profile.equipment?.contains(e.id) == true },
                        set: { on in
                            var list = state.profile.equipment ?? []
                            list.removeAll { $0 == e.id }
                            if on { list.append(e.id) }
                            state.profile.equipment = list
                        })) { Text(e.name) }
                }
            } header: { Text("Meine Trainingsgeräte") } footer: {
                Text("Trainingsplan und Coach schlagen nur Übungen vor, die du damit machen kannst. Dein Coach fragt auch im Gespräch danach.")
            }
            Section {
                ForEach(Array((state.profile.facts ?? []).enumerated()), id: \.offset) { _, f in Text(f) }
                    .onDelete { state.profile.facts?.remove(atOffsets: $0) }
                HStack {
                    TextField("z. B. Knie macht beim Joggen Probleme", text: $newFact)
                    Button("Hinzufügen", systemImage: "plus.circle.fill") {
                        state.profile.learn([newFact.trimmingCharacters(in: .whitespaces)])
                        newFact = ""
                    }
                    .labelStyle(.iconOnly)
                    .disabled(newFact.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Was dein Coach über dich weiß") } footer: {
                Text("Merkt sich dein Coach im Gespräch etwas (z. B. Beschwerden, Zeit, Vorlieben), steht es hier. Zum Löschen nach links wischen. Gespeichert im Profil auf deinem Server; an Claude geht es nur mit deiner Zustimmung.")
            }
        }
        .themed()
        .navigationTitle("Über mich")
    }
}
