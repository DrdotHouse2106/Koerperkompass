import SwiftUI

/// Gestaltung: dunkler Hintergrund mit Verlauf, kräftige Farbe pro Modul, Karten mit leichtem Leuchtrand.
enum Theme {
    static let petrol = Color(red: 0.08, green: 0.55, blue: 0.55)
    static let orange = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let card = Color.white.opacity(0.06)

    static let background = LinearGradient(
        colors: [Color(red: 0.05, green: 0.09, blue: 0.13), Color(red: 0.02, green: 0.03, blue: 0.05)],
        startPoint: .top, endPoint: .bottom)

    /// Farbe je Modul
    static func color(_ module: String) -> Color {
        switch module {
        case "nutrition": .orange
        case "body": .pink
        case "activity": .green
        case "water": .cyan
        case "training", "exercises": .purple
        case "quests": orange
        default: petrol
        }
    }

    static func gradient(_ module: String) -> LinearGradient {
        let c = color(module)
        return LinearGradient(colors: [c, c.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// Listen und Formulare auf den dunklen Hintergrund setzen
    func themed() -> some View {
        scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
    }

    /// Karte mit leichtem Rand in der Modulfarbe
    func card(_ tint: Color = .white) -> some View {
        padding()
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

/// Großes rundes Symbol mit Verlauf (für Kacheln und Karten)
struct IconBadge: View {
    let symbol: String
    let module: String
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.gradient(module), in: RoundedRectangle(cornerRadius: size * 0.3))
            .shadow(color: Theme.color(module).opacity(0.5), radius: 6)
    }
}
