# Datenschutzerklärung – Körperkompass

*Stand: November 2026* · [English version below](#privacy-policy--körperkompass)

## Kurz gesagt

Körperkompass speichert deine Daten **nur auf deinem iPhone und auf einem Server, den du selbst betreibst**. Die Entwickler der App betreiben keinen Server, erhalten keine Daten und nutzen keine Analyse-, Werbe- oder Tracking-Dienste.

## Verantwortlichkeit

Die App ist eine Software, die sich mit einem **von dir selbst betriebenen Server** verbindet. Für die dort gespeicherten Daten bist du selbst verantwortlich (bzw. die Person, die den Server betreibt, z. B. in der Familie).

## Welche Daten verarbeitet werden

- **Eingaben in der App:** Mahlzeiten mit Nährwerten und optional Fotos, Gewicht und Körpermaße, Wasser, Trainings, Profilangaben (Ziel, Gewicht, Größe, Alter, Geschlecht, Aktivität) und Tagesziele.
- **Apple Health (optional):** Mit deiner Freigabe liest die App Schritte, aktive Energie, Schlaf, Ruhepuls, Gewicht und Trainings und schreibt Gewicht und Mahlzeiten. Health-Daten werden **erst nach einer gesonderten, ausdrücklichen Zustimmung** in der App an deinen Server übertragen. Ohne diese Zustimmung bleiben sie auf dem Gerät. Health-Daten werden nie für Werbung genutzt und nie an Dritte verkauft.
- **Kopplung:** Server-Adresse und ein Zugangs-Token (im Schlüsselbund des iPhones). Der Server speichert den Gerätenamen.
- **Kamera/Fotos:** nur zum Scannen des Kopplungscodes, für Fotos von Mahlzeiten und für das Foto der Spielerkarte (bleibt nur auf dem iPhone).

## Claude API (optional)

Ist auf deinem Server ein eigener Claude-API-Key hinterlegt, kannst du Fotos von Mahlzeiten schätzen lassen und eine ausführliche Auswertung erstellen. **Erst nach deiner ausdrücklichen Zustimmung** in der App sendet dein Server dafür das Foto bzw. dein Profil und zusammengefasste Werte (Durchschnitte, Trends) an die Claude API der Anthropic PBC. Health-Daten werden dabei nur einbezogen, wenn du auch ihrem Hochladen zugestimmt hast. Es gelten die Bedingungen des API-Kontos des Server-Betreibers bei Anthropic ([anthropic.com/legal/privacy](https://www.anthropic.com/legal/privacy)). Die Zustimmung kann jederzeit in den Einstellungen widerrufen werden.

## Freunde (optional)

Wenn du Freundschaften schließt, gibt dein Server deine **Spielerkarte** an die Server deiner Freunde weiter: Name, Level, Rang, Klasse, Serie, Anzahl der Erfolge und Workouts sowie Wochenwerte der Challenge. **Gesundheitsdaten werden nie geteilt.** Deine Freunde siehst nur du – außer du schaltest „Meine Freunde meinen Freunden zeigen“ ein; Freunde von Freunden erscheinen nur, wenn diese selbst zugestimmt haben. Beendest du eine Freundschaft, löschen beide Server die gespeicherten Werte.

## Speicherung und Löschung

- Lokal: SwiftData-Zwischenspeicher auf dem iPhone. „Verbindung trennen“ bzw. Löschen der App entfernt ihn.
- Server: eine SQLite-Datei auf deinem Server. Einträge löschst du in der App; den ganzen Bestand löschst du, indem du die Datei auf dem Server entfernst.
- Export und Import als JSON sind jederzeit möglich.

## Übertragung

Die Verbindung zu deinem Server sollte über HTTPS laufen (siehe README). Die App kontaktiert keine anderen Server; die Claude API wird nur von deinem Server aus angesprochen.

## Hinweis

Alle Werte sind Schätzungen. Die App ersetzt keine ärztliche Beratung, Diagnose oder Behandlung.

## Kontakt

Fragen zur App: [GitHub Issues](https://github.com/DrdotHouse2106/Koerperkompass/issues).

---

# Privacy Policy – Körperkompass

*Last updated: November 2026*

## In short

Körperkompass stores your data **only on your iPhone and on a server you run yourself**. The app's developers run no server, receive no data and use no analytics, advertising or tracking services.

## Responsibility

The app is software that connects to a **server operated by you**. You (or whoever runs the server, e.g. in your family) are responsible for the data stored there.

## Data processed

- **Your entries:** meals with nutrients and optional photos, weight and body measurements, water, workouts, profile (goal, weight, height, age, sex, activity) and daily goals.
- **Apple Health (optional):** with your permission the app reads steps, active energy, sleep, resting heart rate, weight and workouts, and writes weight and meals. Health data is sent to your server **only after separate, explicit consent** in the app; otherwise it stays on the device. Health data is never used for advertising and never sold.
- **Pairing:** server address and an access token (stored in the iPhone keychain). The server stores the device name.
- **Camera/photos:** only for scanning the pairing code, meal photos and the player card photo (stays on the iPhone).

## Claude API (optional)

If your server is configured with its own Claude API key, you can have meal photos estimated and get a detailed analysis. **Only after your explicit consent** in the app does your server send the photo, or your profile and summarised values (averages, trends), to the Claude API of Anthropic PBC. Health data is only included if you also agreed to upload it. The terms of the server operator's Anthropic API account apply ([anthropic.com/legal/privacy](https://www.anthropic.com/legal/privacy)). You can withdraw consent in Settings at any time.

## Friends (optional)

If you make friends, your server shares your **player card** with your friends’ servers: name, level, rank, class, streak, number of achievements and workouts, and weekly challenge values. **Health data is never shared.** Only you see your friends – unless you turn on “Show my friends to my friends”; friends of friends only appear if they agreed themselves. Ending a friendship deletes the stored values on both servers.

## Storage and deletion

- Local: SwiftData cache on the iPhone, removed by “Disconnect” or deleting the app.
- Server: one SQLite file on your server. Delete entries in the app, or delete the file on the server to remove everything.
- JSON export and import are available at any time.

## Transmission

Connect to your server via HTTPS (see README). The app contacts no other servers; the Claude API is only called from your server.

## Note

All values are estimates. The app is no substitute for medical advice, diagnosis or treatment.

## Contact

Questions about the app: [GitHub Issues](https://github.com/DrdotHouse2106/Koerperkompass/issues).
