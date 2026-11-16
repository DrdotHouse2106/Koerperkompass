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
        "Heute ist kein Tag für Ausreden, sondern für kleine Siege. 🏅",
        "Du bist nicht im Rückstand. Du bist genau da, wo dein Weg gerade ist.",
        "Ein Spaziergang nach dem Essen wirkt Wunder. Probier’s heute aus! 🚶",
        "Nimm die Treppe. Deine Beine freuen sich (spätestens morgen). 😄",
        "Iss heute eine Portion Gemüse mehr als gestern. 🥕",
        "Dein Körper hört alles, was du denkst. Sag ihm heute was Nettes.",
        "Kleine Gewohnheit für heute: ein Glas Wasser direkt nach dem Aufstehen. 💧",
        "Eiweiß zum Frühstück hält länger satt – Eier, Quark, Joghurt? 🥚",
        "Du trainierst nicht für den Spiegel, sondern für dein Leben.",
        "Heute zählt: einmal mehr aufstehen als hinfallen.",
        "Mach heute den ersten Satz. Der Rest kommt von allein.",
        "Deine Muskeln wachsen in der Pause. Gönn sie dir. 😴",
        "Hunger oder Langeweile? Erst mal ein Glas Wasser – dann entscheiden.",
        "Nicht perfekt essen – bewusster essen. Das reicht.",
        "Mit {serie} Tagen Serie bist du schon weiter als die meisten. 🔥",
        "Heute einfach eine Quest mehr als gestern.",
        "Gute Laune ist auch Training – für den Kopf. 😊",
        "Lieber langsam vorankommen als schnell aufgeben.",
        "Dein Ziel {ziel} ist kein Traum, sondern ein Plan. 🧭",
        "Kaffee ist gut, Wasser dazu ist besser. ☕️💧",
        "Heute Abend früher ins Bett? Dein Morgen-Ich sagt Danke. 🌙",
        "Atme einmal tief durch. Fertig? Super, das war schon die erste Erholung.",
        "Gewicht schwankt – Gewohnheiten bleiben. Schau auf den Trend, nicht auf den Tag.",
        "Die Waage misst Gewicht, nicht deinen Wert.",
        "Du musst nicht motiviert sein, um anzufangen. Fang an, dann kommt die Motivation.",
        "Zehn Kniebeugen beim Zähneputzen? Klingt komisch, wirkt aber. 🪥",
        "Ein bisschen Sonne, ein bisschen Bewegung – perfekte Mischung. ☀️",
        "Plan dein Essen, bevor der Hunger plant. 🍽️",
        "Du bist {serie} Tage dabei – das nennt man Charakter.",
        "Training verpasst? Kein Drama. Morgen ist der nächste Kompasspunkt.",
        "Heute ist Tag 1 vom Rest deiner Serie. 🔥",
        "Ein Lächeln beim Training macht es leichter. Ehrlich! 😁",
        "Gesund ist, was du regelmäßig tust – nicht, was du einmal übertreibst.",
        "Bleib neugierig: Was kann dein Körper heute, was er vor einem Monat nicht konnte?",
        "Schreib dir heute einen Erfolg auf. Auch kleine zählen.",
        "Iss bunt! Je mehr Farben auf dem Teller, desto besser. 🌈",
        "Bewegung ist das beste Mittel gegen schlechte Laune.",
        "Heute schon gestreckt? Zwei Minuten Dehnen tun gut. 🧘",
        "Ein voller Wasserkrug auf dem Tisch erinnert besser als jede App. 😉",
        "Der härteste Teil ist das Anziehen der Sportschuhe. Schaffst du! 👟",
        "Erfolg riecht nach Schweiß und ein bisschen nach Stolz.",
        "Mach’s wie ein Kompass: kurz ausrichten, dann losgehen. 🧭",
        "Du bist kein Projekt, das fertig werden muss. Du bist auf dem Weg.",
        "Heute ein bisschen besser essen, morgen ein bisschen besser schlafen. So geht’s.",
        "Dein Körper ist kein Gegner, sondern dein Team.",
        "Jede Wiederholung zählt – auch die wackeligen.",
        "Zwischendurch Hunger? Obst, Nüsse oder Joghurt statt Süßigkeiten. 🍎",
        "Abends noch einen kleinen Spaziergang? Perfekt zum Runterkommen. 🌆",
        "Heute keine Lust auf Training? Dann wenigstens 15 Minuten gehen.",
        "Du hast heute schon mehr geschafft, als du denkst.",
        "Disziplin heißt: Du hältst dein Versprechen an dich selbst.",
        "Der Tag ist noch jung – und du bist voller Möglichkeiten. ✨",
        "Wochenende ist kein Urlaub von dir selbst. 😉",
        "Montag? Neuer Start. Du kannst das! 💪",
        "Freitag! Belohn dich – zum Beispiel mit einer schönen Runde draußen. 🌳",
        "Am Sonntag schon an die neue Woche gedacht? Plan dein erstes Training ein.",
        "Wer heute trinkt, hat morgen weniger Kopfweh. 💧",
        "Wenn’s schwer wird, wirst du stärker. 🏋️",
        "Kleine Portionen, großer Genuss. Iss langsam und bewusst.",
        "Du darfst stolz sein. Jeden einzelnen Tag.",
        "Fortschritt ist kein Sprint. Fortschritt ist Spazierengehen mit Ziel.",
        "Gönn dir heute was Gutes: Bewegung, Wasser, ein gutes Essen.",
        "Schon gewusst? Schon 7.000 Schritte am Tag machen einen Unterschied. 🚶",
        "Deine Gesundheit ist das beste Investment. Zinsen gibt’s jeden Tag.",
        "Wenn du heute nur eine Sache schaffst: Trink genug. 💧",
        "Mach heute was, worauf dein zukünftiges Ich stolz ist.",
        "Nicht aufgeben – umplanen. Der Kompass hat immer eine Richtung.",
        "Bewegung muss nicht weh tun, um zu wirken.",
        "Heute ist ein guter Tag für einen neuen Rekord. Oder für einen gemütlichen. Beides zählt.",
        "Eiweiß ist dein Freund beim Muskelaufbau. Hast du heute genug?",
        "Eine gute Mahlzeit ist Selbstfürsorge, kein Verzicht.",
        "Lass dich heute nicht von einer Zahl stressen. Du machst das gut.",
        "Ein Glas Wasser vor jeder Mahlzeit – einfacher Trick, große Wirkung. 💧",
        "Zieh heute dein Lieblings-Sportshirt an. Motivation fängt beim Outfit an. 👕",
        "Nur wer losgeht, kommt an. 🧭",
        "Gönn dir heute fünf Minuten nur für dich. 🧘",
        "Dein Herz freut sich über jede Treppe. ❤️",
        "Mach’s einfach: Wasser, Gemüse, Bewegung, Schlaf. Wiederholen.",
        "Erinnerung: Du bist großartig. Das war’s. 😊",
        "Heute nicht zu streng mit dir sein – aber auch nicht zu bequem.",
        "Jede Mahlzeit ist eine neue Chance. Die nächste wird gut!",
        "Fühlst du dich schlapp? Manchmal hilft schon Wasser und frische Luft.",
        "Du bist die Person, die heute entscheidet. Und du entscheidest dich für dich.",
        "Wer schwitzt, gewinnt – mindestens ein gutes Gefühl. 💦",
        "Rekorde kommen später. Heute zählt Regelmäßigkeit.",
        "Kleiner Tipp: Leg die Sportsachen schon abends bereit. 🎒",
        "Starke Menschen machen auch Pausen.",
        "Du bist auf Kurs. Kurskorrekturen sind erlaubt. 🧭",
        "Heute ein Schritt, morgen ein Schritt – in einem Jahr ein ganzer Weg.",
        "Glaub an dich. Dein Körper tut es schon.",
        "Wenn du heute einen Snack brauchst: Eiweiß + Obst = Volltreffer.",
        "Noch {ziel}? Dann heute: ein Training, genug Wasser, gutes Essen. Fertig.",
        "Mach weiter – die Version von dir in drei Monaten feiert dich. 🎉",
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
    /// `personal`: von Claude geschriebene Sprüche – sie ersetzen die nächsten fälligen Sprüche aus dem Vorrat.
    static func schedule(hours: [Int], profile: Profile, streak: Int, personal: [String] = []) async {
        var personal = personal
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
                let fromCoach = !personal.isEmpty
                let text = fromCoach ? personal.removeFirst() : pool[order[(dayNumber * hours.count + slot) % order.count]]
                    .replacingOccurrences(of: "{name}", with: name)
                    .replacingOccurrences(of: "{serie}", with: "\(max(streak, 1))")
                    .replacingOccurrences(of: "{ziel}", with: goal)
                let content = UNMutableNotificationContent()
                content.title = fromCoach ? String(localized: "Von deinem Coach 💬") : titles.randomElement()!
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
