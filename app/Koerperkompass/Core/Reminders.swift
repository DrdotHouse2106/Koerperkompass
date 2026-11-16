import SwiftData
import UIKit
import UserNotifications

/// Gemeinsamer Datenspeicher – auch für Aktionen aus Mitteilungen, wenn die App nicht offen ist.
let sharedContainer: ModelContainer = {
    do { return try ModelContainer(for: Entry.self) } catch { fatalError("Datenspeicher: \(error)") }
}()

/// Trinkerinnerungen: Mitteilungen im gewählten Abstand, direkt aus der Mitteilung abhakbar.
enum Reminders {
    static let category = "DRINK"
    static let prefix = "drink-reminder-"

    /// Aktionen in der Mitteilung („Wasser getrunken“, „Kaffee“, „Tee“)
    static func registerCategory() {
        let actions = ["water", "coffee", "tea"].compactMap { id in
            Drink.all.first { $0.id == id }.map {
                UNNotificationAction(identifier: "drink.\($0.id)", title: "\($0.emoji) \(String(localized: $0.name)) · \($0.ml.whole) ml")
            }
        }
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: []),
        ])
    }

    /// Plant tägliche Erinnerungen von `from` bis `to` Uhr alle `every` Stunden (ersetzt bisherige).
    static func schedule(every: Int, from: Int, to: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        cancel()
        for hour in stride(from: from, through: to, by: max(every, 1)) {
            let content = UNMutableNotificationContent()
            let texts: [(LocalizedStringResource, LocalizedStringResource)] = [
                ("Zeit für ein Glas Wasser 💧", "Halte die Mitteilung gedrückt und hake ab, was du getrunken hast."),
                ("Schluck für Schluck 🚰", "Dein Körper besteht zu rund 60 Prozent aus Wasser – füll nach!"),
                ("Trinkpause! 💦", "Ein Glas jetzt, und dein Kopf bleibt klar."),
                ("Durst ist schon zu spät 😉", "Trink ein Glas, bevor du es merkst – und hak es direkt hier ab."),
                ("Wasser marsch! 🌊", "Ein kleiner Schritt Richtung Trinkziel."),
                ("Kurz trinken? ☕️💧", "Kaffee, Tee oder Wasser – alles zählt (nur Alkohol nicht)."),
            ]
            let t = texts[hour % texts.count]
            content.title = String(localized: t.0)
            content.body = String(localized: t.1)
            content.sound = .default
            content.categoryIdentifier = category
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: prefix + "\(hour)", content: content, trigger: trigger))
        }
        return true
    }

    /// Tägliche Coach-Erinnerung
    static func scheduleCoach(hour: Int) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Dein Coach 💬")
        content.body = String(localized: "Wie geht’s dir heute? Hol dir dein Tagesbriefing im Coach.")
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "coach-daily", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)))
    }

    static func cancelCoach() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["coach-daily"]) }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0..<24).map { prefix + "\($0)" })
    }
}

/// Nimmt die Aktionen aus den Mitteilungen entgegen und trägt das Getränk ein.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategory()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.actionIdentifier
        guard id.hasPrefix("drink."), let drink = Drink.all.first(where: { "drink." + $0.id == id }) else { return }
        let context = ModelContext(sharedContainer)
        context.insert(drink.entry())
        try? context.save()
    }
}
