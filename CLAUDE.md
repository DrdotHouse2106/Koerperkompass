# CLAUDE.md – Körperkompass

Hinweise für die Arbeit an diesem Repository (auch für KI-Assistenten).

## Aufbau

```
app/                     iOS-App (SwiftUI, iOS 17+, keine externen Abhängigkeiten)
  project.yml            XcodeGen-Projekt → `xcodegen generate`
  Config.xcconfig        Team-ID (lokal über Local.xcconfig, in CI über Secret)
  Koerperkompass/
    App.swift            Einstieg, RootView (Verbinden → Einrichtung → App), Übersicht
    Core/                Entry (SwiftData), API, AppState (Abgleich, Zustimmungen), Health, Profile (Ziele), Demo
    Modules/             Module.swift (Schema + Liste) und ein File pro Modul
    Views/               Connect, Setup, Compass (Analyse), Settings
    Localizable.xcstrings  Texte: Schlüssel = Deutsch, Übersetzung Englisch
server/                  Go-Server, eine Binary, SQLite (modernc.org/sqlite, ohne CGO)
  main.go                Start, Konfiguration, Datenbankschema
  auth.go                Kopplungscodes, Tokens, Middleware
  api.go                 REST-Endpunkte, Export/Import, Weboberfläche (index.html)
  ai.go                  Claude API (optional, nur mit ANTHROPIC_API_KEY)
  applog.go              Erweitertes Protokoll der Testphase (POST/GET /api/log, nie weitergeleitet)
  friends.go             Freundschaften, auch zwischen Servern (Föderation über /api/fed/*)
  modules.go             Modul-Schema + Liste, generische Zusammenfassung
  exercises.go           Übungsbibliothek (exercises.json aus free-exercise-db, Unlicense; Übersetzungen in exercise_de, Bilder-Zwischenspeicher)
  relay.go               KI-Relais (`koerperkompass relay`, `relay-key …`): zentraler Claude-Zugang mit Guthaben, speichert keine Inhalte
  usage.go               KI-Verbrauch: Tokens pro Nutzer/Tag/Modell (ai_usage), Kostenschätzung, GET /api/usage
  module_*.go            ein File pro Modul (module_recipes.go: Rezepte, Reel-Links über Reelkoch)
.github/workflows/       server.yml (Docker → ghcr.io), testflight.yml (iOS → TestFlight)
```

## Datenmodell

Alle Module teilen sich **eine** Tabelle bzw. ein SwiftData-Modell `Entry`:
`id`, `module`, `date` (JJJJ-MM-TT), `data` (JSON mit den Feldern), `updated` (ms, neuere gewinnt), `deleted`.
Der Server vergibt pro Schreibvorgang eine `rev`; die App holt mit `GET /api/entries?since=<rev>` nur Neues.
Geänderte Einträge sind lokal `dirty` und werden beim nächsten Abgleich übertragen (offline-fähig).

## Modul-Schema

Jedes Modul hat auf **beiden Seiten** dieselben Angaben:

| Angabe | App (`AppModule`) | Server (`Module`) |
|---|---|---|
| id | `id` | `ID` |
| Name | `name` (LocalizedStringResource) | `Name` |
| SF-Symbol | `symbol` | `Symbol` |
| Datenfelder | `fields: [Field]` | `Fields []Field` |
| Kachel | `tile(_:)` | – |
| Eingabe-/Detailansicht | `detail(_:)` | – |
| Zusammenfassung für die Analyse | `summary(_:days:)` (generisch aus `fields`) | `Summary()` (generisch aus `Fields`) |

Module ohne Felder (z. B. `quests`, Gamification) berechnen ihre Anzeige aus den Einträgen der anderen Module (`@Query` in der Ansicht) und speichern nichts Eigenes. Neue Quests: Eintrag in `Quest.all` (`QuestModule.swift`). Trainingsprogramme und Vorlagen: `Core/Training.swift` (Programm liegt im Profil, absolvierte Einheiten sind Training-Einträge mit id `plan-<Tag>`, eigene Quests sind Einträge im Modul `quests` mit id `habit-<Tag>-<Name>`).

`Field.agg` bestimmt die Zusammenfassung: `sum` (pro Tag addieren, z. B. kcal), `avg` (Durchschnitt, z. B. Ruhepuls), `last` (Verlauf, z. B. Gewicht).

## Neues Modul anlegen – Schritt für Schritt

Beispiel: Modul „Stimmung“ mit Feld `mood` (1–5).

1. **Server:** `server/module_mood.go` anlegen:
   ```go
   package main

   // Stimmung: ein Eintrag pro Bewertung (1–5).
   var mood = Module{ID: "mood", Name: "Stimmung", Symbol: "face.smiling", Fields: []Field{
       {"mood", "Stimmung", "", "avg"},
   }}
   ```
2. **Server:** in `server/modules.go` die Liste ergänzen: `var modules = []Module{..., mood}`
3. **App:** `app/Koerperkompass/Modules/MoodModule.swift` anlegen – am einfachsten `WaterModule.swift` kopieren und anpassen:
   `id`, `name`, `symbol`, `fields` (gleiche Keys wie auf dem Server), `tile` und `detail`.
4. **App:** in `Modules/Module.swift` die Liste ergänzen: `let allModules: [any AppModule] = [..., MoodModule()]`
5. **Texte:** neue deutsche Texte in `Localizable.xcstrings` mit englischer Übersetzung ergänzen (Xcode legt die Schlüssel beim Bauen automatisch an).
6. **README:** Modul in die Tabelle „Module“ (README.md und README.en.md) eintragen.

Das Modul erscheint danach in den Einstellungen und im Einrichtungsassistenten und kann ein-/ausgeschaltet werden.
Kompass-Analyse, Abgleich, Export/Import und die Claude-Auswertung funktionieren automatisch über die Felder.

## Konventionen

- **Möglichst minimalistischer Code.** Keine externen Abhängigkeiten in der App; im Server nur SQLite, QR-Code und das Anthropic-SDK.
- **Deutsch** für Texte, Kommentare, Commit-Nachrichten und Doku; Englisch nur als Übersetzung (`*.en.md`, String Catalog).
- In der App sind deutsche Texte die Schlüssel im String Catalog (`sourceLanguage: de`).
- **Keine persönlichen Daten oder Zugangsdaten** im Repository: Team-ID in `app/Local.xcconfig`, Apple-/API-Schlüssel nur als GitHub-Secrets bzw. Umgebungsvariablen.
- Gesundheitsdaten: Health-Daten gehen nur mit Zustimmung (`healthUpload`) an den Server, Daten an Claude nur mit Zustimmung (`aiConsent`). Neue Funktionen müssen diese beiden Schalter respektieren.
- Freundschaften/Föderation: Über `/api/fed/*` gehen **nur** Werte der Spielerkarte (`PUT /api/card`) hinaus, nie Einträge oder Profil. Neue geteilte Werte nur mit Bedacht und Hinweis in PRIVACY.md.
- Anonyme Verbesserungsdaten (`Core/Telemetry.swift`, `server/telemetry.go`): nur Felder aus dem Gesprächsprotokoll, nie Gesundheitswerte oder Kennungen; standardmäßig aus, nur nach Zustimmung. Neue Felder nur mit Hinweis in PRIVACY.md.
- Hinweis „keine ärztliche Beratung“ überall dort, wo Werte bewertet werden.
- Profil-Felder neu immer optional anlegen (ältere gespeicherte Profile bleiben lesbar).
- Dark Motivation (`Core/DarkMotivation.swift`, `server/dark_style.md`): nur **eigene** Texte. Neue Vorbilder (Reels) werden ausgewertet, ihre Stilmerkmale in `dark_style.md` unter „Ausgewertete Vorbilder“ ergänzt (ohne Sätze zu übernehmen) und daraus neue Geschichten auf Deutsch und Englisch geschrieben. Die Stilvorlage ist per `go:embed` auch Anweisung für Claudes persönliche Geschichten.
- Ende-zu-Ende-Verschlüsselung (`Core/Vault.swift`): Eintragsinhalte (`data`) und Profil können beim Server verschlüsselt ankommen (`"enc:v1:…"` bzw. `{"enc": …}`). Der Server darf sich deshalb **nie** auf Eintragsinhalte verlassen – Auswertungen rechnet die App und schickt sie mit. Uploads immer über `Vault.sealEntry`, Downloads über `Vault.open`.

## Prüfen

```bash
cd server && go vet ./... && go build ./...
cd app && xcodegen generate && xcodebuild -scheme Koerperkompass -destination 'generic/platform=iOS Simulator' build
```
