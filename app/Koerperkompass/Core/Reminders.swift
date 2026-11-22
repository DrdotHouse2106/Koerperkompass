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

    /// Sprüche für die Trinkerinnerung (Titel, Text)
    static let texts: [(LocalizedStringResource, LocalizedStringResource)] = [
        ("Zeit für ein Glas Wasser 💧", "Halte die Mitteilung gedrückt und hake ab, was du getrunken hast."),
        ("Schluck für Schluck 🚰", "Dein Körper besteht zu rund 60 Prozent aus Wasser – füll nach!"),
        ("Trinkpause! 💦", "Ein Glas jetzt, und dein Kopf bleibt klar."),
        ("Durst ist schon zu spät 😉", "Trink ein Glas, bevor du es merkst – und hak es direkt hier ab."),
        ("Wasser marsch! 🌊", "Ein kleiner Schritt Richtung Trinkziel."),
        ("Kurz trinken? ☕️💧", "Kaffee, Tee oder Wasser – alles zählt (nur Alkohol nicht)."),
        ("Dein Gehirn ruft an 🧠", "Es möchte Wasser. Schon ein Glas hilft gegen das Nachmittagstief."),
        ("Kleine Erinnerung 🥤", "Wann hast du zuletzt etwas getrunken? Genau."),
        ("Plopp! Wasserzeit 🫧", "Ein Glas Wasser – und schon ein Haken mehr für heute."),
        ("Glas statt Gähnen 🥱", "Müdigkeit ist oft einfach Durst. Probier’s aus."),
        ("Hydration Check ✅", "Ein paar Schlucke jetzt halten dich frisch."),
        ("Deine Zellen sagen danke 🙏", "Ein Glas Wasser, und sie arbeiten wieder auf Hochtouren."),
        ("Hunger oder Durst? 🤔", "Oft ist es Durst. Erst ein Glas Wasser, dann entscheiden."),
        ("Auffüllen, bitte ⛽️", "Dein Tank braucht Nachschub – am besten Wasser."),
        ("Wasserstand prüfen 📏", "Ein Glas bringt dich deinem Trinkziel ein gutes Stück näher."),
        ("Prost! 🥂", "Diesmal mit Wasser. Deine Nieren stoßen mit an."),
        ("Haut, Kopf, Konzentration 💡", "Alle profitieren von einem Glas Wasser. Jetzt?"),
        ("Mini-Pause 🕐", "Aufstehen, Glas füllen, trinken. 30 Sekunden."),
        ("Die Flasche schaut dich an 👀", "Sie ist noch voll. Ändere das!"),
        ("Wasser ist der beste Snack 🍏", "Null Kalorien, volle Wirkung."),
        ("Du machst das gut 💪", "Und mit einem Glas Wasser gleich noch besser."),
        ("Wie eine Pflanze 🌱", "Ohne Wasser lässt du den Kopf hängen. Gießen!"),
        ("Trinken nicht vergessen 📝", "Ein Glas – und hier direkt abhaken."),
        ("Wasser vor Kaffee ☕️", "Erst ein Glas Wasser, dann darf der Kaffee kommen."),
        ("Kopfschmerzen vorbeugen 💆", "Zu wenig trinken ist ein häufiger Grund. Ein Glas, bitte."),
        ("Halbzeit? ⏱️", "Schau mal, wie weit du beim Trinkziel bist – und leg nach."),
        ("Ein Glas, ein Lächeln 😊", "Kleine Gewohnheit, große Wirkung."),
        ("Training läuft besser 🏃", "Mit genug Wasser hast du mehr Kraft und Ausdauer."),
        ("Abnehmen leicht gemacht 🎯", "Ein Glas Wasser vor dem Essen macht schneller satt."),
        ("Ding dong, Wasser 🔔", "Dein Körper hat bestellt. Lieferung bitte jetzt."),
        ("Schon getrunken? 🧐", "Wenn ja: abhaken. Wenn nein: jetzt!"),
        ("Tee-Zeit 🍵", "Auch Tee zählt fürs Trinkziel. Gönn dir eine Tasse."),
        ("Konzentration im Keller? 📉", "Schon leichter Wassermangel macht unkonzentriert. Glas holen!"),
        ("Wasser marsch, Teil 2 🚒", "Die nächste Runde fürs Trinkziel wartet."),
        ("Dein Trinkziel winkt 👋", "Jedes Glas bringt dich näher. Los geht’s!"),
        ("Erfrischung gefällig? 🧊", "Ein kühles Glas Wasser wirkt Wunder."),
        ("Kurzer Check-in 📲", "Trinken, abhaken, weitermachen."),
        ("Wasser ist Leben 🌍", "Klingt pathetisch, stimmt aber. Ein Glas, bitte."),
        ("Lieber jetzt als später ⏰", "Wer gleichmäßig trinkt, muss abends nicht nachholen."),
        ("Glas leer? Gut so! 🥛", "Dann füll es gleich wieder auf."),
        ("Kleine Schlucke zählen auch 🐦", "Ein halbes Glas ist besser als keins."),
        ("Trinkpause mit Aussicht 🪟", "Glas Wasser, kurz aus dem Fenster schauen, durchatmen."),
        ("Für die Haut ✨", "Gut versorgt sieht man frischer aus. Ein Glas, bitte."),
        ("Streak-Gefahr! 🔥", "Trinkziel schaffen hält deine Serie am Leben."),
        ("Psst … 🤫", "Wasser. Jetzt. Danke."),
        ("Deine Nieren melden sich 🫘", "Sie arbeiten am besten mit genug Wasser."),
        ("Wasser schlägt Limo 🥇", "Gleicher Durstlöscher, null Zucker."),
        ("Ein Glas für den Fokus 🎧", "Trinken, durchatmen, weiter geht’s."),
    ]

    /// Plant Erinnerungen von `from` bis `to` Uhr alle `every` Stunden für die nächsten Tage (ersetzt bisherige).
    /// Jede Mitteilung bekommt einen eigenen Spruch, durchgemischt – derselbe kommt erst wieder, wenn alle dran waren.
    /// iOS erlaubt höchstens 64 geplante Mitteilungen; Platz bleibt für Motivation und Coach. Beim Öffnen der App wird nachgefüllt.
    static func schedule(every: Int, from: Int, to: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        cancel()
        let hours = Array(stride(from: from, through: to, by: max(every, 1)))
        let days = max(1, min(7, 34 / max(hours.count, 1)))
        var order = UserDefaults.standard.array(forKey: "drinkTextOrder") as? [Int] ?? []
        let cal = Calendar.current
        for day in 0..<days {
            for hour in hours {
                guard let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: day, to: Date())!),
                      date > Date() else { continue }
                if order.isEmpty { order = Array(texts.indices).shuffled() }
                let t = texts[order.removeFirst() % texts.count]
                let content = UNMutableNotificationContent()
                content.title = String(localized: t.0)
                content.body = String(localized: t.1)
                content.sound = .default
                content.categoryIdentifier = category
                let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: prefix + "\(day)-\(hour)", content: content, trigger: trigger))
            }
        }
        UserDefaults.standard.set(order, forKey: "drinkTextOrder")
        return true
    }

    /// Beim Öffnen der App: Erinnerungen für die nächsten Tage nachfüllen, falls eingeschaltet
    static func refresh() async {
        let d = UserDefaults.standard
        guard d.bool(forKey: "reminderOn") else { return }
        _ = await schedule(every: d.object(forKey: "reminderEvery") as? Int ?? 2, from: d.object(forKey: "reminderFrom") as? Int ?? 9,
                           to: d.object(forKey: "reminderTo") as? Int ?? 21)
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
        let center = UNUserNotificationCenter.current()
        // alte Kennungen (je Stunde) und neue (je Tag und Stunde)
        center.removePendingNotificationRequests(withIdentifiers: (0..<24).map { prefix + "\($0)" }
            + (0..<7).flatMap { d in (0..<24).map { prefix + "\(d)-\($0)" } })
    }
}

/// Ziel nach dem Tippen auf eine Mitteilung („water“, „motivation“, „coach“)
@Observable @MainActor final class Router {
    static let shared = Router()
    var route: String?
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
        // Tipp auf die Mitteilung selbst → passende Stelle in der App öffnen
        if id == UNNotificationDefaultActionIdentifier {
            let req = response.notification.request
            Router.shared.route = req.content.categoryIdentifier == Reminders.category ? "water"
                : req.identifier.hasPrefix(Motivation.prefix) ? "motivation"
                : req.identifier == "coach-daily" ? "coach" : nil
            return
        }
        guard id.hasPrefix("drink."), let drink = Drink.all.first(where: { "drink." + $0.id == id }) else { return }
        let context = ModelContext(sharedContainer)
        context.insert(drink.entry())
        try? context.save()
    }
}
