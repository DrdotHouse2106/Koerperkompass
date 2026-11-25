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

Ist auf deinem Server ein eigener Claude-API-Key hinterlegt, kannst du Fotos von Mahlzeiten schätzen lassen und eine ausführliche Auswertung erstellen. **Erst nach deiner ausdrücklichen Zustimmung** in der App sendet dein Server dafür das Foto bzw. dein Profil und zusammengefasste Werte (Durchschnitte, Trends) an die Claude API der Anthropic PBC. Health-Daten werden dabei nur einbezogen, wenn du auch ihrem Hochladen zugestimmt hast. Für den **Coach** gehen deine Nachrichten und eine Zusammenfassung deiner Daten (Ernährung, Getränke, Gewicht, Training) auf demselben Weg an Claude; der Gesprächsverlauf wird nur auf deinem iPhone gespeichert. Es gelten die Bedingungen des API-Kontos des Server-Betreibers bei Anthropic ([anthropic.com/legal/privacy](https://www.anthropic.com/legal/privacy)). Die Zustimmung kann jederzeit in den Einstellungen widerrufen werden.

## Freunde (optional)

Wenn du Freundschaften schließt, gibt dein Server deine **Spielerkarte** an die Server deiner Freunde weiter: Name, Level, Rang, Klasse, Serie, Anzahl der Erfolge und Workouts sowie Wochenwerte der Challenge. **Gesundheitsdaten werden nie geteilt.** Deine Freunde siehst nur du – außer du schaltest „Meine Freunde meinen Freunden zeigen“ ein; Freunde von Freunden erscheinen nur, wenn diese selbst zugestimmt haben. Beendest du eine Freundschaft, löschen beide Server die gespeicherten Werte.

## Stimmung

Im Modul „Stimmung“ trägst du deine Stimmung, Gefühle und Lebensbereiche ein. Sie werden wie andere Einträge auf deinem iPhone und deinem Server gespeichert (mit Ende-zu-Ende-Verschlüsselung nur verschlüsselt) und – mit Health-Freigabe – auch in Apple Health („Gemütszustand“). Stimmungen, die du in Apple Health oder anderen Apps einträgst, liest die App mit deiner Freigabe; zum Server gehen sie wie alle Health-Daten nur mit deiner Zustimmung zum Hochladen. An Claude geht – nur mit deiner Zustimmung – höchstens eine Zusammenfassung (z. B. Durchschnitt der letzten 7 Tage).

## Beschwerden

Beschwerden und Krankheitssymptome (z. B. verstopfte Nase, Fieber) werden wie andere Einträge auf deinem iPhone und deinem Server gespeichert (mit Ende-zu-Ende-Verschlüsselung nur verschlüsselt) und – mit Health-Freigabe – auch in Apple Health („Symptome“). Symptome aus Apple Health liest die App mit deiner Freigabe; zum Server gehen sie nur mit deiner Zustimmung zum Hochladen. Der Coach erhält – nur mit deiner Zustimmung – eine Kurzliste der Beschwerden der letzten 7 Tage, damit er Training und Tipps anpasst. Erwähnst du Beschwerden im Gespräch, schlägt er einen Eintrag vor; gespeichert wird erst nach deiner Bestätigung.

## Über mich: Geräte und was der Coach weiß

Deine Trainingsgeräte, dein Tagesablauf („Mein Alltag“) und die Tatsachen, die sich der Gesundheitscoach im Gespräch merkt (z. B. Beschwerden, verfügbare Zeit, Vorlieben), stehen in deinem Profil – auf deinem iPhone und deinem eigenen Server. An Claude gehen sie nur mit deiner Zustimmung, als Teil des Profils. Du siehst und löschst sie unter Einstellungen → Über mich.

## Apple Intelligence (auf dem Gerät)

Sprach-Coach, Anpassung der nächsten Trainingseinheit und persönliche Motivationssprüche nutzen – wenn verfügbar – das Sprachmodell von Apple Intelligence **direkt auf deinem iPhone**. Dabei werden keine Daten an deinen Server, an Anthropic oder an Apple übertragen. Für den Sprach-Coach verwendet die App Mikrofon und Spracherkennung (nach Möglichkeit ebenfalls auf dem Gerät).

## Gesprächsprotokoll (Testphase)

Auf Wunsch protokolliert die App während der Testphase die Gespräche mit den Coaches (erkannter Text, Antwort, Stil, verwendetes Modell, Antwortzeit), um sie verbessern zu können. Das Protokoll liegt nur auf deinem iPhone und deinem eigenen Server, ist in den Coach-Ansichten sichtbar gekennzeichnet und ist **standardmäßig aus** und lässt sich jederzeit ein- und ausschalten und löschen (Einstellungen → Gesprächsprotokoll). Weitergegeben wird es nur, wenn du es selbst teilst.

## Erweitertes Protokoll (Testphase)

Auf Wunsch meldet die App während der Testphase Abläufe an **deinen eigenen Server**, damit Fehler gefunden werden können: gewechselte Tabs, angelegte, geänderte und gelöschte Einträge (nur Modul, Kennung, Datum, Zeitstempel – keine Werte), Abgleiche, Server-Aufrufe mit Antwortcode und Dauer sowie Fehlermeldungen. Gesundheitswerte sind nicht enthalten. Der Server behält die letzten 5000 Zeilen und gibt sie nie weiter, auch nicht mit den anonymen Verbesserungsdaten. **Standardmäßig aus**, einschaltbar unter Einstellungen → Erweitertes Protokoll.

## Anonyme Verbesserungsdaten (freiwillig)

Nur wenn du in den Einstellungen „Anonyme Daten teilen“ einschaltest und bestätigst, leitet dein Server Angaben zu den Coach-Gesprächen an den Server der Entwickler von Körperkompass weiter: Art des Gesprächs, Coach-Stil, verwendetes Modell, Antwortzeit, ob ein Satz erkannt wurde, App-Version, iOS-Hauptversion, Sprache. **Ohne Nutzerkennung und ohne Gesundheitswerte.** Gesprächstexte werden nur übertragen, wenn du „Gesprächstexte mitsenden“ zusätzlich einschaltest; Namen aus deinem Profil, E-Mail-Adressen, Telefonnummern und Links werden vorher entfernt. Der Server der Entwickler speichert keine IP-Adressen und nutzt die Daten ausschließlich zur Verbesserung der App. Du kannst das jederzeit ausschalten; Server-Betreiber können die Weiterleitung ganz abschalten (`KK_TELEMETRY=off`). Verantwortlich für diese Daten: die Entwickler von Körperkompass (Kontakt über GitHub Issues).

## Rezepte (optional)

Fügst du einen Link zu einer Rezeptseite ein, ruft dein Server diese Seite ab und übernimmt die eingebetteten Rezeptdaten; nur wenn diese fehlen, geht der Seitentext mit deiner Zustimmung an Claude. Fügst du einen Reel- oder Video-Link ein, gibt dein Server ihn an deine eigene Reelkoch-Installation weiter; die lädt das öffentliche Reel und lässt das Rezept mit ihrem eigenen Claude-Zugang erstellen. Eingefügter Rezepttext und – nur mit deiner Zustimmung – das fertige Rezept zur Nährwertschätzung gehen über deinen Server an Claude. Deine Rezepte liegen wie alle Einträge auf deinem iPhone und deinem Server; der Coach bekommt eine Liste der Rezepttitel mit Nährwerten (bei erwähnten Rezepten auch die Zutaten). Bei „Mit dem Coach kochen“ gehen – nur mit deiner Zustimmung – das Rezept und deine Fragen über deinen Server an Claude, keine Gesundheitsdaten; das Gespräch wird nicht gespeichert.

## Kalender (optional)

Schaltest du „Kalender für den Coach“ ein, liest die App deine Termine von heute und morgen (nur lesen) und gibt sie dem Coach mit – standardmäßig nur als „belegt“ mit Uhrzeit, Titel nur, wenn du das zusätzlich einschaltest. Die Termine gehen wie alle Coach-Daten nur mit deiner Zustimmung an Claude und werden nicht gespeichert.

## Claude-Connector (optional)

Verbindest du Körperkompass mit deiner Claude-App, lädt die App eine Kurzfassung deiner Daten (heute, letzte 7 Tage, Ziele) **verschlüsselt** auf deinen Server. Den Schlüssel bekommt nur Claude als Teil des Zugangstokens; dein Server speichert ihn nicht. Fragt Claude in deinem Auftrag, entschlüsselt der Server die Kurzfassung kurz im Arbeitsspeicher und gibt sie an Claude (Anthropic) weiter – dabei gelten deine Vereinbarungen mit Anthropic für dein Claude-Konto. Einträge, die Claude für dich anlegt, liegen verschlüsselt auf dem Server, bis die App sie übernimmt. „Verbindung trennen“ löscht Kurzfassung, Zugang und Eingangskorb.

## KI-Relais

Nutzt dein Server statt eines eigenen Claude-Schlüssels ein KI-Relais, laufen die Anfragen an Claude zusätzlich über dieses Relais. Das Relais leitet sie nur weiter und speichert keine Inhalte – nur Relais-Schlüssel, Guthaben und Tokenzahlen pro Tag und Modell.

## KI-Verbrauch

Dein Server zählt bei jeder Claude-Anfrage nur die Anzahl der Tokens (pro Tag und Modell), keine Inhalte. Du siehst den Verbrauch in den Einstellungen unter „KI-Verbrauch“.

## Ende-zu-Ende-Verschlüsselung (immer an)

Einträge und Profil werden **auf dem iPhone verschlüsselt** (AES-GCM mit einem zufälligen 256-Bit-Schlüssel), bevor sie an den Server gehen. Die App richtet das beim ersten Abgleich automatisch ein. Der Server – und wer ihn betreibt – sieht nur Modul, Datum und Zeitpunkt der Einträge, nicht deren Inhalt. Der Schlüssel liegt in deinem **iCloud-Schlüsselbund** (von Apple Ende-zu-Ende-verschlüsselt), damit deine Daten auf einem neuen iPhone mit derselben Apple-ID ohne Passwort wieder da sind; in iCloud liegt dabei nur der Schlüssel, keine Gesundheitsdaten. Auf dem Server liegt der Schlüssel nur verschlüsselt – mit deinem Wiederherstellungsschlüssel und, falls du eins festlegst, mit einem zusätzlichen Passwort (je PBKDF2). Verlierst du Schlüsselbund, Wiederherstellungsschlüssel und Passwort, sind die Daten auf dem Server nicht wiederherstellbar. Nicht verschlüsselt sind die Spielerkarte für Freunde sowie Daten, die du ausdrücklich an Claude, die Sprachausgabe oder als freiwillige Protokolle bzw. anonyme Verbesserungsdaten sendest. Der Server nimmt Einträge und Profil nur verschlüsselt an.

## Nur auf dem iPhone (optional)

Unter Einstellungen → Speicherort kannst du „Nur auf diesem iPhone speichern“ einschalten. Dann löscht dein Server alle gespeicherten Einträge, dein Profil, deine Spielerkarte und das Protokoll und speichert nichts mehr davon; auch gesprochene Antworten werden dort nicht zwischengespeichert. Er leitet nur noch Anfragen an Claude (mit deiner Zustimmung) und an die Sprachausgabe weiter. Sicherungen des Servers (falls der Betreiber welche anlegt) enthalten die Daten noch, bis sie überschrieben werden; für eine sofortige Löschung auch dort wende dich an den Betreiber deines Servers. Deine Daten liegen dann nur auf dem iPhone (und in dessen Backup). Schaltest du es wieder aus, wird alles erneut hochgeladen.

## Speicherung und Löschung

- Lokal: SwiftData-Zwischenspeicher auf dem iPhone. „Verbindung trennen“ bzw. Löschen der App entfernt ihn.
- Server: eine SQLite-Datei auf deinem Server. Einträge löschst du in der App; den ganzen Bestand löschst du, indem du die Datei auf dem Server entfernst.
- Einträge und Profil liegen auf dem Server nur Ende-zu-Ende-verschlüsselt (siehe oben). Lesbar sind für den Betreiber nur Konto, Geräte, Spielerkarte, KI-Verbrauch (Tokenzahlen) und – falls eingeschaltet – das App-Protokoll ohne Inhalte.
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

If your server is configured with its own Claude API key, you can have meal photos estimated and get a detailed analysis. **Only after your explicit consent** in the app does your server send the photo, or your profile and summarised values (averages, trends), to the Claude API of Anthropic PBC. Health data is only included if you also agreed to upload it. For the **coach**, your messages and a summary of your data (nutrition, drinks, weight, training) are sent the same way; the conversation history is stored only on your iPhone. The terms of the server operator's Anthropic API account apply ([anthropic.com/legal/privacy](https://www.anthropic.com/legal/privacy)). You can withdraw consent in Settings at any time.

## Friends (optional)

If you make friends, your server shares your **player card** with your friends’ servers: name, level, rank, class, streak, number of achievements and workouts, and weekly challenge values. **Health data is never shared.** Only you see your friends – unless you turn on “Show my friends to my friends”; friends of friends only appear if they agreed themselves. Ending a friendship deletes the stored values on both servers.

## Mood

In the “Mood” module you log your mood, feelings and areas of life. They are stored like other entries on your iPhone and your server (only encrypted with end-to-end encryption) and – with Health permission – in Apple Health (“State of Mind”). Moods you log in Apple Health or other apps are read with your permission; like all Health data they only go to the server if you agreed to uploading. Claude receives – only with your consent – at most a summary (e.g. the 7-day average).

## Symptoms

Symptoms (e.g. stuffy nose, fever) are stored like other entries on your iPhone and your server (only encrypted with end-to-end encryption) and – with Health permission – in Apple Health (“Symptoms”). Symptoms from Apple Health are read with your permission; they only go to the server if you agreed to uploading. With your consent the coach receives a short list of symptoms from the last 7 days to adapt training and tips. If you mention symptoms in a chat, it proposes an entry; nothing is saved until you confirm.

## About me: equipment and what the coach knows

Your training equipment, your daily routine (“My daily routine”) and the facts the health coach remembers from conversations (e.g. complaints, available time, preferences) are stored in your profile – on your iPhone and your own server. They are only sent to Claude with your consent, as part of the profile. You can view and delete them under Settings → About me.

## Apple Intelligence (on device)

The voice coach, next-session adjustment and personal motivational messages use – when available – the Apple Intelligence language model **directly on your iPhone**. No data is sent to your server, to Anthropic or to Apple. The voice coach uses the microphone and speech recognition (on device whenever possible).

## Conversation log (test phase)

During the test phase the app logs conversations with the coaches (recognised text, reply, style, model used, response time) to improve them. The log is stored only on your iPhone and your own server, is clearly marked in the coach views and is **off by default** and can be switched on, off and deleted at any time (Settings → Conversation log). It is only shared if you share it yourself.

## Extended log (test phase)

During the test phase the app reports activity to **your own server** to help find bugs: tab changes, created, changed and deleted entries (only module, ID, date, timestamp – no values), syncs, server calls with status code and duration, and error messages. No health values are included. The server keeps the last 5000 lines and never forwards them, not even with the anonymous improvement data. **Off by default**, can be switched on under Settings → Extended log.

## Anonymous improvement data (optional)

Only if you turn on “Share anonymous data” in Settings and confirm it, your server forwards information about coach conversations to the Körperkompass developers’ server: type of conversation, coach style, model used, response time, whether a set was recognised, app version, major iOS version, language. **No user identifier and no health values.** Conversation texts are only sent if you also enable “Include conversation texts”; names from your profile, email addresses, phone numbers and links are removed first. The developers’ server stores no IP addresses and uses the data solely to improve the app. You can turn this off at any time; server operators can disable forwarding entirely (`KK_TELEMETRY=off`). Responsible for this data: the Körperkompass developers (contact via GitHub Issues).

## Recipes (optional)

If you paste a link to a recipe website, your server fetches the page and takes over the embedded recipe data; only if there is none, the page text is sent to Claude with your consent. If you paste a reel or video link, your server passes it to your own Reelkoch installation, which downloads the public reel and creates the recipe with its own Claude access. Pasted recipe text and – only with your consent – the finished recipe for nutrition estimates are sent via your server to Claude. Your recipes are stored like all entries on your iPhone and your server; the coach receives a list of recipe titles with nutrition values (ingredients for recipes you mention). With “Cook with the coach” – only with your consent – the recipe and your questions go to Claude via your server, no health data; the conversation is not stored.

## Calendar (optional)

If you turn on “Calendar for the coach”, the app reads your events for today and tomorrow (read-only) and passes them to the coach – by default only as “busy” with times, titles only if you enable that as well. Like all coach data they only go to Claude with your consent and are not stored.

## Claude connector (optional)

If you connect Körperkompass to your Claude app, the app uploads an **encrypted** summary of your data (today, last 7 days, goals) to your server. Only Claude receives the key, as part of its access token; your server does not store it. When Claude asks on your behalf, the server decrypts the summary briefly in memory and passes it to Claude (Anthropic) under the terms of your Claude account. Entries Claude creates for you are stored encrypted until the app picks them up. “Disconnect” deletes the summary, access and inbox.

## AI relay

If your server uses an AI relay instead of its own Claude key, Claude requests additionally pass through that relay. It only forwards them and stores no content – only relay keys, credit and token counts per day and model.

## AI usage

For every Claude request your server counts only the number of tokens (per day and model), no content. You can see it in Settings under “AI usage”.

## End-to-end encryption (always on)

Entries and profile are **encrypted on the iPhone** (AES-GCM with a random 256-bit key) before they are sent to the server; the app sets this up automatically on the first sync. The server – and whoever operates it – only sees module, date and time of entries, not their content. The key is stored in your **iCloud Keychain** (end-to-end encrypted by Apple), so your data is back on a new iPhone with the same Apple ID without a password; only the key is in iCloud, no health data. On the server the key is only stored encrypted – with your recovery key and, if you set one, an additional password (PBKDF2 each). If you lose Keychain, recovery key and password, the data on the server cannot be recovered. Not encrypted are the player card for friends and data you explicitly send to Claude, speech output, or as optional logs or anonymous improvement data. The server only accepts encrypted entries and profiles.

## iPhone only (optional)

Under Settings → Storage you can turn on “Store only on this iPhone”. Your server then deletes all stored entries, your profile, your player card and the log, and stores none of it any more; spoken replies are not cached there either. It only forwards requests to Claude (with your consent) and to speech output. Server backups (if the operator makes any) still contain the data until they are overwritten; for immediate deletion there too, contact your server's operator. Your data then lives only on the iPhone (and its backup). If you turn it off again, everything is uploaded again.

## Storage and deletion

- Local: SwiftData cache on the iPhone, removed by “Disconnect” or deleting the app.
- Server: one SQLite file on your server. Delete entries in the app, or delete the file on the server to remove everything.
- Entries and profile are stored on the server only end-to-end encrypted (see above). The operator can only read account, devices, player card, AI usage (token counts) and – if enabled – the app log without content.
- JSON export and import are available at any time.

## Transmission

Connect to your server via HTTPS (see README). The app contacts no other servers; the Claude API is only called from your server.

## Note

All values are estimates. The app is no substitute for medical advice, diagnosis or treatment.

## Contact

Questions about the app: [GitHub Issues](https://github.com/DrdotHouse2106/Koerperkompass/issues).
