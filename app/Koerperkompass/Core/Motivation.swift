import Foundation
import UserNotifications

/// Motivierende Erinnerungen: jeden Tag ein anderer Spruch – reihum durch einen großen Vorrat, damit sich lange nichts wiederholt.
/// Platzhalter: {name}, {serie}, {ziel}. Die Mitteilungen werden 14 Tage im Voraus geplant und bei jedem Öffnen der App aufgefüllt.
enum Motivation {
    static let prefix = "motivation-"

    static let de = [
        "Guten Morgen{name}! Heute zählt jeder kleine Schritt – fang mit einem Glas Wasser an. 💧",
        "Deine Serie steht bei {serie} Tagen. Lass sie heute nicht reißen! 🔥",
        "Du musst nicht perfekt sein, nur dranbleiben. Eine Quest reicht für heute schon.",
        "Kleiner Schubs: 10 Minuten Bewegung sind besser als keine. Los geht’s! 🚶",
        "Dein Ziel: {ziel}. Jeder Tag bringt dich ein Stück näher.",
        "Stark ist, wer weitermacht, wenn’s keiner sieht. 💪",
        "Heute schon Eiweiß getankt? Dein Körper sagt Danke.",
        "Disziplin ist, sich daran zu erinnern, was man eigentlich will. Du willst {ziel}.",
        "Fortschritt ist leise. Aber er passiert – auch heute.",
        "Ein Training, das du machst, schlägt das perfekte, das du nicht machst.",
        "Trink was! Dein Kopf denkt klarer, wenn du genug Wasser hast. 💧",
        "Du bist {serie} Tage dran. Das ist kein Zufall, das bist du. 🧭",
        "Heute ist ein guter Tag, um stolz auf dich zu sein.",
        "Müde? Dann geh heute locker spazieren. Erholung zählt auch.",
        "Erst kommt die Gewohnheit, dann das Ergebnis. Bleib bei deinen Quests.",
        "Kleine Schritte, große Wirkung: Trag heute dein Frühstück ein.",
        "Du hast schon so viel geschafft{name}. Weiter so!",
        "Der beste Zeitpunkt für Bewegung war gestern. Der zweitbeste ist jetzt.",
        "Dein zukünftiges Ich wird dir für heute danken.",
        "Gemüse, Wasser, Bewegung – drei einfache Siege für heute. 🥦",
        "Nicht zählen, wie oft du gefallen bist – sondern wie oft du aufgestanden bist.",
        "Schlaf ist Training für den Kopf. Gönn dir heute genug davon. 😴",
        "Eine Einheit nach der anderen. Heute ist nur heute.",
        "Du bist stärker, als du heute Morgen dachtest. 💪",
        "Motivation bringt dich los, Gewohnheit bringt dich weiter.",
        "Hast du heute schon {serie} Gründe gesammelt, stolz zu sein? Einen pro Serien-Tag!",
        "Kurzer Check: Wasser getrunken? Gegessen? Bewegt? Dann bist du auf Kurs. 🧭",
        "Rückschläge gehören dazu. Der Kompass zeigt trotzdem nach vorn.",
        "Heute einfach 1 % besser als gestern. Mehr braucht’s nicht.",
        "Deine Freunde sammeln schon Quests – zeig ihnen, was du draufhast! 🏆",
        "Das Level kommt nicht von allein – aber es kommt. Eine Quest nach der anderen.",
        "Pausen sind kein Aufgeben. Sie sind Teil des Plans.",
        "Bewegung ist ein Geschenk an deinen Körper, keine Strafe.",
        "Was du heute isst, ist der Treibstoff für morgen. Tank gut! ⛽️",
        "Du hast angefangen – das schaffen die wenigsten. Jetzt dranbleiben!",
        "Ein Glas Wasser, ein tiefer Atemzug, ein Lächeln. Guter Start! 😊",
        "Heute zählt nicht, wie schnell du bist, sondern dass du losgehst.",
        "Dein Körper kann viel. Dein Kopf muss nur mitmachen.",
        "Neue Woche, neue Chance auf die Wochen-Challenge! 🥇",
        "Schritt für Schritt Richtung {ziel}. Du bist auf dem Weg.",
        "Bier ist okay, Wasser danach ist klüger. 😉🍺💧",
        "Trag ein, was du isst – nicht zum Schämen, sondern zum Verstehen.",
        "Dein Coach wartet auf dich: Hol dir dein Tagesbriefing. 💬",
        "Jeder Tag mit einer erledigten Quest ist ein gewonnener Tag.",
        "Erfolg ist die Summe kleiner Dinge, die du jeden Tag tust.",
        "Heute ist dein Tag{name}. Mach was draus! ✨",
        "Kein Bock? Dann nur 5 Minuten. Meistens werden es mehr.",
        "Durchhalten ist auch eine Superkraft. 🦸",
        "Achte heute auf dich – dein Körper ist dein Zuhause.",
        "Der Kompass zeigt: Weiter so! 🧭",
    ]

    static let en = [
        "Good morning{name}! Every small step counts today – start with a glass of water. 💧",
        "Your streak is at {serie} days. Don’t break it today! 🔥",
        "You don’t have to be perfect, just keep going. One quest is enough for today.",
        "Little nudge: 10 minutes of movement beat none. Let’s go! 🚶",
        "Your goal: {ziel}. Every day brings you a bit closer.",
        "Strong is who keeps going when nobody is watching. 💪",
        "Had your protein today? Your body says thanks.",
        "Progress is quiet. But it’s happening – today too.",
        "The workout you do beats the perfect one you skip.",
        "Drink something! Your head works better when you’re hydrated. 💧",
        "{serie} days in a row. That’s not luck, that’s you. 🧭",
        "Today is a good day to be proud of yourself.",
        "Tired? Take an easy walk today. Recovery counts too.",
        "Habits first, results follow. Stick with your quests.",
        "You’ve already achieved so much{name}. Keep it up!",
        "The best time to move was yesterday. The second best is now.",
        "Your future self will thank you for today.",
        "Veggies, water, movement – three easy wins for today. 🥦",
        "Sleep is training for your mind. Get enough tonight. 😴",
        "One session at a time. Today is just today.",
        "You’re stronger than you thought this morning. 💪",
        "Motivation gets you started, habit keeps you going.",
        "Quick check: water? food? movement? Then you’re on course. 🧭",
        "Setbacks are part of it. The compass still points forward.",
        "Just 1 % better than yesterday. That’s all it takes.",
        "Your friends are collecting quests – show them what you’ve got! 🏆",
        "Rest isn’t giving up. It’s part of the plan.",
        "Movement is a gift to your body, not a punishment.",
        "You started – most people never do. Now keep going!",
        "Step by step towards {ziel}. You’re on your way.",
        "Your coach is waiting: get your daily briefing. 💬",
        "Success is the sum of small things done every day.",
        "Today is your day{name}. Make it count! ✨",
        "Not in the mood? Just 5 minutes. It usually turns into more.",
        "Perseverance is a superpower too. 🦸",
        "The compass says: keep going! 🧭",
    ]

    static let titles = ["Körperkompass", "Kleiner Schubs 💪", "Dein Kompass 🧭", "Weiter so! ✨", "Hey 👋"]

    /// Plant die nächsten 14 Tage neu (ersetzt bisherige). `hours`: Uhrzeiten pro Tag.
    static func schedule(hours: [Int], profile: Profile, streak: Int) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        cancel()
        let english = Locale.current.language.languageCode?.identifier == "en"
        let pool = english ? en : de
        let defaults = UserDefaults.standard
        // Reihenfolge einmal mischen; jeder Kalendertag bekommt fest seinen Platz darin –
        // so wiederholt sich ein Spruch erst nach dem ganzen Vorrat, egal wie oft die App geöffnet wird
        var order = defaults.array(forKey: "motivationOrder") as? [Int] ?? []
        if order.count != pool.count {
            order = Array(pool.indices).shuffled()
            defaults.set(order, forKey: "motivationOrder")
        }
        let goal: String = switch profile.goal {
        case .lose: english ? "reach \(profile.targetWeight.short) kg" : "\(profile.targetWeight.short) kg erreichen"
        case .gain: english ? "build muscle" : "Muskeln aufbauen"
        case .maintain: english ? "stay fit" : "fit bleiben"
        }
        let name = profile.name.map { ", \($0)" } ?? ""
        let cal = Calendar.current
        for day in 0..<14 {
            for hour in hours {
                guard let date = cal.date(bySettingHour: hour, minute: Int.random(in: 0...20), second: 0,
                                          of: cal.date(byAdding: .day, value: day, to: Date())!), date > Date() else { continue }
                let dayNumber = cal.dateComponents([.day], from: Day.date("2026-01-01"), to: date).day ?? 0
                let slot = hours.firstIndex(of: hour) ?? 0
                let text = pool[order[(dayNumber * hours.count + slot) % order.count]]
                    .replacingOccurrences(of: "{name}", with: name)
                    .replacingOccurrences(of: "{serie}", with: "\(max(streak, 1))")
                    .replacingOccurrences(of: "{ziel}", with: goal)
                let content = UNMutableNotificationContent()
                content.title = titles.randomElement()!
                content.body = text
                content.sound = .default
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                try? await center.add(UNNotificationRequest(identifier: prefix + "\(day)-\(hour)", content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: (0..<14).flatMap { d in (0..<24).map { prefix + "\(d)-\($0)" } })
    }
}
