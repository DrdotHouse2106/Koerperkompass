import Foundation

/// „Dark Motivation“: kurze, ernste Geschichten (eigene Texte nach server/dark_style.md).
/// Eine Zeile = eine Einblendung; Wörter in GROSSBUCHSTABEN erscheinen rot und groß.
struct DarkStory: Codable, Hashable {
    var lang: String      // "de" oder "en"
    var lines: [String]
    var inner: Bool? = nil  // Form „innere Stimme“: drängende Fragen, schneller vorgelesen

    /// Sprache für den Motivationsbereich: "de", "en" oder "mix"
    static var language: String { UserDefaults.standard.string(forKey: "darkLang") ?? (Locale.current.language.languageCode?.identifier == "en" ? "en" : "de") }

    static func pool(_ lang: String) -> [DarkStory] { all.filter { lang == "mix" || $0.lang == lang } }

    static let all: [DarkStory] = [
        // Deutsch
        .init(lang: "de", lines: ["Es gab diesen einen Abend.", "Er stand vor dem Spiegel und erkannte sich nicht mehr.", "Kein Drama. Nur Stille.",
                                  "Am nächsten Morgen stand er auf. Um sechs. Im REGEN.", "Niemand hat zugesehen.", "Genau deshalb hat es GEZÄHLT."]),
        .init(lang: "de", lines: ["Du willst es leicht?", "Leicht hat dich hierher gebracht.", "Ab heute nimmst du den schweren Weg.",
                                  "Jeden Tag. Ohne Applaus.", "Bis der schwere Weg dein NORMAL ist."]),
        .init(lang: "de", lines: ["Sie haben gelacht.", "Sie haben gesagt, du hältst keine zwei Wochen durch.", "Lass sie reden.",
                                  "Wochen werden zu Monaten.", "Und eines Tages hören sie auf zu lachen.", "STILL. DISZIPLINIERT. UNAUFHALTSAM."]),
        .init(lang: "de", lines: ["Die Kälte fragt nicht, ob du müde bist.", "Der Asphalt fragt nicht nach deinem Tag.", "Du läufst trotzdem.",
                                  "Weil der alte du KEINE Stimme mehr hat.", "Nur noch der neue entscheidet."]),
        .init(lang: "de", lines: ["Jede Ausrede ist eine Kette.", "Zu spät. Zu müde. Morgen.", "Er hat sie alle gesprengt.", "Eine nach der anderen.",
                                  "KEINE KETTEN. KEINE GRENZEN. KEINE AUSREDEN."]),
        .init(lang: "de", lines: ["Motivation kommt und geht.", "Sie war nicht da, als es dunkel wurde.", "Was blieb, war DISZIPLIN.",
                                  "Der leise Teil in dir, der trotzdem aufsteht.", "Hör auf ihn."]),
        .init(lang: "de", lines: ["Er hat alles verloren, was ihn bequem gemacht hat.", "Die Ausreden. Die Abkürzungen. Das Sofa.", "Was übrig blieb, war hart.",
                                  "Und ehrlich.", "Er hat nichts mehr zu verlieren.", "Nur noch etwas zu GEWINNEN."]),
        .init(lang: "de", lines: ["Niemand kommt, um dich zu retten.", "Kein Plan. Kein Trainer. Kein perfekter Montag.", "Nur du.",
                                  "Und das ist die beste Nachricht.", "Denn DU reichst."]),
        .init(lang: "de", lines: ["Narben lügen nicht.", "Jede steht für einen Tag, an dem du nicht aufgegeben hast.", "Trag sie.",
                                  "Und mach heute eine NEUE."]),
        .init(lang: "de", lines: ["Es ist Nacht. Die Straßen sind leer.", "Nur dein Atem und deine Schritte.", "Kein Publikum.",
                                  "Hier wird nicht gewonnen, um gesehen zu werden.", "Hier wird gewonnen, weil du es WILLST."]),
        // Innere Stimme – Deutsch
        .init(lang: "de", lines: ["Sitzt du schon wieder?", "Worauf WARTEST du eigentlich?", "Auf den perfekten Tag?",
                                  "Der kommt nicht.", "Du gehst ihm ENTGEGEN."], inner: true),
        .init(lang: "de", lines: ["Schon wieder morgen?", "Wie oft willst du das noch SAGEN?", "Wie viele Morgen hast du schon VERSCHENKT?",
                                  "Jetzt.", "Nicht morgen. JETZT."], inner: true),
        .init(lang: "de", lines: ["Spürst du das?", "Diese Wut auf dich SELBST?", "Gut.", "Nimm sie mit.", "Jede Wiederholung gehört ihr."], inner: true),
        .init(lang: "de", lines: ["Wer hat dir gesagt, dass das deine GRENZE ist?", "Du selbst?", "Seit wann hörst du auf den SCHWACHEN Teil?",
                                  "Noch eine.", "Und dann NOCH eine."], inner: true),
        .init(lang: "de", lines: ["Müde?", "Und WEITER?", "Glaubst du, der alte du hätte jetzt aufgehört?", "Genau.", "Darum hörst du NICHT auf."], inner: true),
        .init(lang: "de", lines: ["Sie haben dich abgeschrieben, oder?", "Zu WEICH. Zu langsam. Zu spät.", "Lass sie.",
                                  "Lass sie zusehen, wie du ZURÜCKKOMMST."], inner: true),
        // English
        .init(lang: "en", lines: ["Something broke that night.", "Not his body. His excuses.", "He stood up in the dark.",
                                  "Laced his shoes. Stepped into the RAIN.", "Nobody saw it.", "That's why it MATTERED."]),
        .init(lang: "en", lines: ["They told you to be realistic.", "Realistic kept you small.", "So you stopped listening.",
                                  "Every morning. Every cold, empty morning.", "Until small was GONE."]),
        .init(lang: "en", lines: ["Comfort is a slow prison.", "Soft bed. Easy food. Tomorrow.", "He walked out.",
                                  "Into the cold. Into the work.", "NO CHAINS. NO LIMITS. NO EXCUSES."]),
        .init(lang: "en", lines: ["You don't need motivation.", "Motivation left the first time it rained.", "You need DISCIPLINE.",
                                  "The quiet voice that says: again.", "Listen to it."]),
        .init(lang: "en", lines: ["He lost the version of himself that quit.", "It hurt.", "It was supposed to.",
                                  "What came back was quieter. Harder.", "UNBREAKABLE."]),
        .init(lang: "en", lines: ["No one is coming.", "No perfect plan. No perfect Monday.", "Just you and the next rep.",
                                  "And that is ENOUGH."]),
        .init(lang: "en", lines: ["The street is empty at five a.m.", "No crowd. No applause.", "Only breath and footsteps.",
                                  "This is where the WORK happens.", "This is where you become someone else."]),
        .init(lang: "en", lines: ["Scars are receipts.", "Proof you paid for every inch.", "Wear them.", "Then earn a NEW one."]),
        .init(lang: "en", lines: ["They laughed when you started.", "They'll go quiet when you don't stop.", "Let them talk.",
                                  "You have work to do.", "SILENT. FOCUSED. RELENTLESS."]),
        .init(lang: "en", lines: ["Every excuse is a chain.", "Too tired. Too late. Too hard.", "Break one today.", "Then another.",
                                  "Until nothing holds you BACK."]),
        // Inner voice – English
        .init(lang: "en", lines: ["Sitting down again?", "What are you WAITING for?", "The perfect day?",
                                  "It's not coming.", "You go and TAKE it."], inner: true),
        .init(lang: "en", lines: ["Tomorrow again?", "How many times will you SAY that?", "How many tomorrows have you WASTED?",
                                  "Now.", "Not tomorrow. NOW."], inner: true),
        .init(lang: "en", lines: ["Do you feel that?", "That anger at YOURSELF?", "Good.", "Keep it.", "Every rep belongs to it."], inner: true),
        .init(lang: "en", lines: ["Who told you this is your LIMIT?", "You did?", "Since when do you listen to the WEAK part?",
                                  "One more.", "Then ONE more."], inner: true),
        .init(lang: "en", lines: ["Tired?", "So WHAT?", "You think the old you would stop here?", "Exactly.", "That's why you DON'T."], inner: true),
        .init(lang: "en", lines: ["They wrote you off, didn't they?", "Too SOFT. Too slow. Too late.", "Let them.",
                                  "Let them watch you COME BACK."], inner: true),
    ]
}
