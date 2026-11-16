# 🧭 Körperkompass

**Ernährung, Gewicht, Aktivität und Schlaf an einem Ort – deine Daten auf deinem eigenen Server.**

Körperkompass besteht aus zwei Teilen:

- **iOS-App** (`app/`) – eine App für alle im App Store. SwiftUI, iOS 17+, keine externen Abhängigkeiten.
- **Server** (`server/`) – den **jeder Nutzer selbst betreibt**: eine Go-Binary mit SQLite, als Docker-Image verfügbar.

Es gibt keinen zentralen Dienst: Die Entwickler betreiben keinen Server und sehen keine Daten. Jeder ist für seine eigenen Gesundheitsdaten verantwortlich.

[English version](README.en.md) · [Datenschutz / Privacy](PRIVACY.md)

> ⚠️ **Alle Werte (Kalorienbedarf, Nährwert-Schätzungen, Auswertungen) sind nur Schätzungen und ersetzen keine ärztliche oder ernährungsfachliche Beratung.**

---

## Was die App kann

| | |
|---|---|
| 🍽 **Ernährung** | Tagesziele, Ringe für Eiweiß/Kohlenhydrate/Fett, 7-Tage-Diagramm, Tagebuch (Frühstück, Mittag, Abend, Snack), optional Foto-Eintrag mit Nährwert-Schätzung |
| ⚖️ **Gewicht & Maße** | Gewicht, Körperfett, Taille, Hüfte, Brust – mit Verlauf und Wunschgewicht |
| 🚶 **Aktivität & Schlaf** | Schritte, aktive Energie, Schlaf, Ruhepuls und Trainings aus Apple Health |
| 🗺 **Mein Plan** | Überblick: Gewichtsverlauf bis zum Ziel, BMI-Skala, Tagesziele, Wasser und Training |
| 🏁 **Abenteuer** | Gamification: Charakterkarte (Level, Workouts, Serie, Klasse, Rang), teilbare Spielerkarte mit eigenem Foto, Erfolge, Wochenleiste und 🔥-Serie, tägliche Quests, eigene Quests (z. B. Lesen, Meditieren), XP, Level, Ränge (Wanderer → Legende), Attribute (Kraft, Ausdauer, Erholung, Disziplin, Balance) |
| 📈 **Übungen** | Sätze mit Wiederholungen und Gewicht, Verlauf pro Übung, Stufen Bronze → Silber → Gold → Platin |
| 🏋️ **Trainingsprogramme** | 4-Wochen-Programme mit Trainings- und Ruhetagen, XP pro Einheit, Vorlagen oder persönlich von Claude erstellt; optional Strafpunkte für verpasste Einheiten |
| 💧 **Getränke** | Wasser, Kaffee, Tee, Bier, Wein, Softdrinks … mit einem Tipp; Trinkziel, Koffein, Alkohol, Kalorien zählen in die Ernährung; **Trinkerinnerung**, direkt in der Mitteilung abhakbar |
| 🏋️ **Training** | eigener Tab: heutige Einheit, Empfehlungen passend zu Ziel und Aktivität, neun fertige Programme. **Rückmeldung nach jeder Einheit** (zu leicht / genau richtig / zu schwer) passt die nächste Einheit an – mit Claude konkret auf Basis von Verlauf und eingetragenen Sätzen |
| 🔔 **Erinnerungen** | Motivierende Sprüche morgens (und optional abends) – jeden Tag ein anderer, persönlich mit Name, Serie und Ziel; Trinkerinnerung mit wechselnden Texten; tägliche Coach-Erinnerung |
| 🎙 **Trainings-Coach (Sprache)** | Im Training sprechen („10 Wiederholungen mit 60 Kilo, war schwer“): Satz wird eingetragen, Antwort vorgelesen, Pause runtergezählt, „Feuer mich an!“ – Stil wählbar: 🎖 Drill Sergeant, 💀 Drill Sergeant – Hardcore (derb, nur nach Rückfrage), 🤜 Kumpel, 📣 Cheerleader, 🧘 Ruhig & sachlich. Mit Apple Intelligence auf dem iPhone, kostenlos und offline. Dazu Siri: „Wasser in Körperkompass eintragen“ |
| 💬 **Gesundheitscoach** | Persönlicher Coach (Claude) im Chat **oder per Sprache** (Mikrofon, Antworten werden vorgelesen): kennt Profil, Ziele, Essen, Getränke, Gewicht und Training, gibt ein Tagesbriefing und konkrete nächste Schritte. Tägliche Erinnerung, Verlauf bleibt auf dem iPhone. Braucht `ANTHROPIC_API_KEY` |
| 🧭 **Kompass** | Auswertung über 7/30/90 Tage: Durchschnitte, Trends, Zielerreichung, Zusammenhänge (z. B. Schlaf ↔ Kalorien). Optional ausführliche Auswertung mit Claude |
| 🤝 **Freunde (dezentral)** | Freundschaften mit Nutzern auf deinem oder **anderen Körperkompass-Servern** – ohne zentralen Dienst. Freundesliste mit Spielerkarten, Wochen-Challenge mit Bestenliste, optional Freunde von Freunden. Geteilt werden nur Spielwerte, nie Gesundheitsdaten |
| 👥 **Mehrere Nutzer** | weitere Personen einladen – jede mit eigenem Konto, eigenen Zugängen und eigenen Daten |
| ✈️ **Offline** | lokaler Zwischenspeicher, Abgleich sobald der Server erreichbar ist |
| 🎮 **Demo-Modus** | mit Beispieldaten, ganz ohne Server |

Sprachen: Deutsch (Standard) und Englisch.

### Screenshots

| Heute | Ernährung | Kompass | Einstellungen |
|---|---|---|---|
| _Platzhalter_ | _Platzhalter_ | _Platzhalter_ | _Platzhalter_ |

<!-- Screenshots unter docs/screenshots/ ablegen und hier einbinden, z. B. ![Heute](docs/screenshots/heute.png) -->

---

## Server einrichten

### Mit Docker Compose

```bash
mkdir koerperkompass && cd koerperkompass
curl -O https://raw.githubusercontent.com/DrdotHouse2106/Koerperkompass/main/server/docker-compose.yml
docker compose up -d
docker compose logs        # zeigt den Kopplungscode
```

Danach `http://<server-ip>:8080` im Browser öffnen: Dort steht der Kopplungscode auch als QR-Code.

**Umgebungsvariablen** (alle optional):

| Variable | Bedeutung |
|---|---|
| `ANTHROPIC_API_KEY` | eigener Claude-API-Key ([console.anthropic.com](https://console.anthropic.com)) für Foto-Erkennung und ausführliche Analyse. Ohne Key gibt es nur die lokale Auswertung. |
| `KK_PUBLIC_URL` | öffentliche Adresse, z. B. `https://kompass.example.de` (für den QR-Code hinter einem Reverse Proxy) |
| `KK_MODEL` | Claude-Modell für Coach, Fotos, Analyse und Training (Standard: `claude-opus-5-5`; günstiger: `claude-sonnet-5-5` oder `claude-haiku-5-5`) |
| `KK_MODEL_SMALL` | kleines Modell für die täglichen Motivationssprüche (Standard: `claude-haiku-5-5`) |
| `KK_TELEMETRY` | `off` schaltet das Weiterleiten anonymer Verbesserungsdaten an die Entwickler ab (nur relevant, wenn Nutzer es in der App freiwillig einschalten) |
| `KK_TELEMETRY_URL` | Ziel für anonyme Verbesserungsdaten (Standard: Hauptserver des Projekts) |
| `KK_COLLECT`, `KK_COLLECT_TOKEN` | nur für den Hauptserver: `KK_COLLECT=1` nimmt anonyme Daten an, Abruf mit `GET /api/collect` und `Authorization: Bearer <KK_COLLECT_TOKEN>` |
| `KK_TRUSTED_PROXY`, `KK_COLLECT_LIMIT` | Hauptserver: IP des eigenen Reverse Proxys (dann zählt dessen `X-Forwarded-For`) und Anfragen pro Absender-IP und Stunde für `/api/collect` (Standard 30). Zusätzlich: höchstens 1 MB pro Anfrage, nur bekannte Felder |
| `PORT` | Port (Standard: `8080`) |
| `KK_DB` | Pfad der SQLite-Datei (im Image: `/data/koerperkompass.db`) |

Anfragen an Claude nutzen den serverseitigen Fallback der API: Lehnt das Modell eine Anfrage ab, beantwortet ein Ersatzmodell sie.

### Apple Intelligence und Claude – wer macht was?

| Funktion | Läuft mit | Kosten |
|---|---|---|
| Sprach-Coach im Training, „Einheit für mich anpassen“, tägliche persönliche Sprüche | 🍏 Apple Intelligence **auf dem iPhone** (iOS 26, iPhone 15 Pro oder neuer) – offline, Daten verlassen das Gerät nicht | 0 € |
| Siri: „Wasser in Körperkompass eintragen“ | 🍏 Kurzbefehle | 0 € |
| Coach-Chat, Auswertungen, neue Trainingsprogramme, Foto-Nährwerte | ☁️ Claude über deinen Server (`ANTHROPIC_API_KEY`) | siehe unten |

Ohne Apple Intelligence (ältere iPhones) übernimmt **Claude Haiku** (`KK_MODEL_SMALL`) alles rund ums Training – Trainings-Coach,
Einheit anpassen, Sprüche – für Bruchteile eines Cents pro Antwort. Ohne Claude-Key erkennt der Trainings-Coach nur Wiederholungen und Gewicht.

### Was kostet die Claude API?

Abgerechnet wird über dein eigenes Konto bei Anthropic, nach verbrauchten Tokens. Grobe Richtwerte pro Aufruf (Stand November 2026,
inklusive der Denk-Tokens; tatsächliche Kosten schwanken je nach Datenmenge):

| Funktion | Opus 5.5 (Standard) | Sonnet 5.5 | Haiku 5.5 |
|---|---|---|---|
| Coach-Nachricht | ca. 3–6 ct | ca. 1,5–3 ct | ca. 0,1 ct |
| Foto-Schätzung | ca. 1–2 ct | ca. 0,5–1 ct | < 0,1 ct |
| Nächste Einheit anpassen / Programm erstellen | ca. 3–10 ct | ca. 1,5–5 ct | ca. 0,2 ct |
| Analyse (Kompass) | ca. 3–6 ct | ca. 1,5–3 ct | ca. 0,1 ct |
| Motivationssprüche (1× täglich, immer Haiku) | – | – | ca. 0,05 ct |

Beispiel: 3 Fotos, 5 Coach-Nachrichten und 1 Trainingsanpassung pro Tag ≈ 30 ct/Tag mit Opus (≈ 9 €/Monat),
≈ 15 ct/Tag mit Sonnet (≈ 4–5 €/Monat), < 1 ct/Tag mit Haiku. Mit `KK_MODEL=claude-sonnet-5-5` halbierst du die Kosten bei
kaum spürbarem Qualitätsunterschied. In der Anthropic Console kannst du ein monatliches Ausgabenlimit setzen.

### Auf Proxmox (LXC)

**Variante A – Docker im LXC:** Debian-12-Container anlegen (unprivilegiert, Option *Nesting* aktivieren), dann:

```bash
apt update && apt install -y docker.io docker-compose-plugin curl
```

und weiter wie bei Docker Compose.

**Variante B – ohne Docker:** Debian-12-Container anlegen, dann:

```bash
apt update && apt install -y golang git
git clone https://github.com/DrdotHouse2106/Koerperkompass.git /opt/kk-src
cd /opt/kk-src/server
# Wenig RAM (z. B. LXC mit 4 GB, /tmp im RAM): Zwischendateien auf die Platte legen und nur einen Kern nutzen
export GOCACHE=/var/tmp/go-cache GOTMPDIR=/var/tmp GOMAXPROCS=1
CGO_ENABLED=0 go build -p 1 -trimpath -ldflags "-s -w -X main.version=$(git rev-parse --short=7 HEAD)" -o /usr/local/bin/koerperkompass .
mkdir -p /var/lib/koerperkompass
cat > /etc/systemd/system/koerperkompass.service <<'EOF'
[Unit]
Description=Körperkompass-Server
After=network.target

[Service]
Environment=KK_DB=/var/lib/koerperkompass/koerperkompass.db
# Environment=ANTHROPIC_API_KEY=...
ExecStart=/usr/local/bin/koerperkompass
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now koerperkompass
journalctl -u koerperkompass   # Kopplungscode
```

> Braucht der Server eine neuere Go-Version als Debian mitbringt, Go von [go.dev/dl](https://go.dev/dl/) installieren.
>
> **Häufiges Problem – Build bricht ab („killed“/OOM):** Der Compiler braucht für das Claude-SDK etwa 2,5 GB RAM, und im LXC liegt `/tmp`
> oft als tmpfs im Arbeitsspeicher. Deshalb oben `GOCACHE`/`GOTMPDIR` auf die Platte legen und mit `GOMAXPROCS=1` bzw. `-p 1` bauen –
> oder dem Container vorübergehend mehr RAM geben bzw. die Docker-Variante nutzen.
>
> **Update:** `cd /opt/kk-src && git pull`, Build-Befehl wiederholen, `systemctl restart koerperkompass`. Die Datenbank wird beim Start automatisch ergänzt.

### HTTPS über Reverse Proxy

Die App verlangt HTTPS (Ausnahme: `http://` im lokalen Netz zum Testen). Den Server **nicht ungeschützt** ins Internet stellen, sondern hinter einen Reverse Proxy mit Zertifikat.

**Caddy** (`Caddyfile`, Zertifikat kommt automatisch):

```
kompass.example.de {
    reverse_proxy 192.168.1.20:8080
}
```

**Nginx Proxy Manager:**

1. *Hosts → Proxy Hosts → Add Proxy Host*
2. Domain: `kompass.example.de`, Scheme `http`, Forward Hostname/IP: IP des Servers, Port `8080`
3. Tab *SSL*: „Request a new SSL Certificate“, *Force SSL* und *HTTP/2* aktivieren
4. Tab *Advanced* (für Fotos): `client_max_body_size 20m;`

Danach `KK_PUBLIC_URL=https://kompass.example.de` setzen, damit der QR-Code die richtige Adresse enthält.

Alternativ ohne offenen Port: VPN (WireGuard, Tailscale) und die Adresse im VPN verwenden.

### Backup

Alle Daten liegen in **einer SQLite-Datei** (`data/koerperkompass.db`, dazu ggf. `-wal`/`-shm`).

- **Einfach:** Container kurz stoppen und den Ordner `data/` kopieren:
  `docker compose stop && cp -a data backup-$(date +%F) && docker compose start`
- **Im laufenden Betrieb:** `sqlite3 data/koerperkompass.db ".backup backup.db"`
- **Pro Nutzer als JSON:** in der App unter *Einstellungen → Daten → Export*, oder per API `GET /api/export`.

---

## App koppeln

1. App öffnen → **„QR-Code scannen“** und den Code auf der Weboberfläche des Servers scannen
   (oder Adresse und Kopplungscode von Hand eingeben, **„Verbindung testen“**, **„Koppeln“**).
2. Einrichtungsassistent: Ziel, Gewicht, Wunschgewicht, Größe, Alter, Geschlecht, Aktivität und gewünschte Module.
   Die Tagesziele werden nach **Mifflin-St-Jeor** berechnet (mit aktiver Energie aus Apple Health, falls vorhanden) und lassen sich später ändern.
3. Optional Apple Health verbinden.

### Weitere Personen und Geräte

- **Weitere Person einladen** (*Einstellungen → Server*): Name eingeben → QR-Code bzw. Link (einmalig, 24 Stunden gültig).
  Die Person bekommt ein **eigenes Konto mit eigenem Zugang**; ihre Daten sind von deinen getrennt, keiner sieht die Daten des anderen.
- **Weiteres eigenes Gerät koppeln** (z. B. iPad): gleiches Konto, gleiche Daten.
- **Meine Geräte:** gekoppelte Geräte ansehen und einzelnen den Zugang entziehen (z. B. bei Verlust).
- Auf dem Server: `docker exec koerperkompass /koerperkompass invite "Name"`.

**Ohne Server ausprobieren:** „Demo ausprobieren“ auf dem Startbildschirm.

---

## App auf dein iPhone bringen

Solange die App noch nicht im App Store ist, gibt es zwei Wege:

**A) TestFlight (empfohlen, ohne Mac)** – braucht einen Apple-Developer-Account (99 €/Jahr):

1. In [App Store Connect](https://appstoreconnect.apple.com) unter *Apps → +* eine neue App anlegen: Bundle-ID `de.drdothouse.koerperkompass`
   (falls nicht auswählbar: vorher unter [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers) anlegen, Fähigkeit **HealthKit** anhaken).
2. *Benutzer und Zugriff → Integrationen → App Store Connect API*: Schlüssel mit Rolle *App Manager* erzeugen, `.p8` herunterladen, Key-ID und Issuer-ID notieren.
3. Im GitHub-Repo unter *Settings → Secrets and variables → Actions* anlegen:
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (kompletter Inhalt der `.p8`).
4. *Actions → „TestFlight (iOS)“ → Run workflow*. Nach ca. 10–20 Minuten erscheint der Build in App Store Connect.
5. In App Store Connect unter *TestFlight* dich als **interne Testerin/internen Tester** eintragen, auf dem iPhone die App **TestFlight** installieren und Körperkompass dort installieren.

Danach lädt jeder Push mit Änderungen in `app/` automatisch eine neue Version hoch.

**B) Direkt aus Xcode (Mac nötig):** iPhone per Kabel anschließen, `cd app && xcodegen generate && open Koerperkompass.xcodeproj`,
Team-ID in `app/Local.xcconfig` eintragen, oben das iPhone als Ziel wählen und ▶︎ drücken. Auf dem iPhone den Entwicklermodus aktivieren
(*Einstellungen → Datenschutz & Sicherheit → Entwicklermodus*).

---

## Module

| Modul | id | Felder | Quelle |
|---|---|---|---|
| Abenteuer | `quests` | – (berechnet aus allen anderen Modulen) | Quests, XP, Level |
| Ernährung | `nutrition` | kcal, protein, carbs, fat (+ meal, name, photo) | Eingabe, Foto |
| Gewicht & Maße | `body` | weight, bodyFat, waist, hip, chest | Eingabe, Apple Health (Gewicht) |
| Aktivität & Schlaf | `activity` | steps, activeEnergy, sleepHours, restingHR, workoutMinutes | Apple Health |
| Übungen | `exercises` | reps, weight (+ exercise) | Eingabe |
| Getränke | `water` | hydration, kcal, caffeine, alcohol (+ drink, name, ml) | Eingabe, Schnell-Buttons, Trinkerinnerung |
| Training | `training` | minutes (+ name) | Eingabe (Beispielmodul) |

Module lassen sich in den Einstellungen ein- und ausschalten. Ein neues Modul ist eine neue Datei in App und Server plus ein Listeneintrag – siehe [CLAUDE.md](CLAUDE.md).

---

## Datenschutz

- Alle Daten liegen **nur auf deinem eigenen Server** und lokal auf deinem iPhone. Es gibt keine Analyse-, Werbe- oder Tracking-Dienste.
- **Apple Health:** Die App liest Health-Daten nur nach deiner Freigabe. An deinen Server gehen sie erst nach einer **ausdrücklichen Zustimmung** in der App.
- **Anonyme Verbesserungsdaten (freiwillig, standardmäßig aus):** Nur nach Zustimmung leitet dein Server anonyme Angaben zu Coach-Gesprächen (Stil, Modell, Antwortzeit; Texte nur mit zusätzlicher Freigabe und bereinigt) an die Entwickler weiter – ohne Kennung und ohne Gesundheitswerte.
- **Claude API (optional):** Nur wenn auf deinem Server ein eigener API-Key hinterlegt ist **und** du in der App **zugestimmt** hast, werden Fotos bzw. zusammengefasste Werte über deinen Server an Anthropic gesendet.
- Ausführlich: [PRIVACY.md](PRIVACY.md)

---

## API (kurz)

Alle Endpunkte außer `status`, `modules` und `pair` brauchen `Authorization: Bearer <token>`.

| Methode | Pfad | Zweck |
|---|---|---|
| GET | `/api/status` | Version, ob Claude aktiv ist |
| GET | `/api/modules` | Modul-Schema |
| POST | `/api/pair` | `{code, device}` → `{token}` |
| POST | `/api/invite` | `{sameUser}` → `{code}` |
| GET/PUT | `/api/profile` | Profil und Ziele |
| GET | `/api/entries?since=<rev>` | Einträge seit Revision (Abgleich) |
| POST | `/api/entries` | Einträge anlegen/ändern/löschen (`deleted: true`) |
| GET/POST | `/api/export`, `/api/import` | alles als JSON |
| POST | `/api/ai/photo`, `/api/ai/analysis`, `/api/ai/plan`, `/api/ai/next`, `/api/ai/coach`, `/api/ai/motivation`, `/api/ai/voice` | nur mit `ANTHROPIC_API_KEY` |
| PUT | `/api/card` | eigene Spielerkarte (nur Spielwerte) |
| POST/GET/DELETE | `/api/friends/link`, `/api/friends`, `/api/friends/{id}` | Freundschaftslink, Freund hinzufügen, Freunde abrufen, beenden |
| POST/GET | `/api/fed/accept`, `/api/fed/card`, `/api/fed/remove` | **Server-zu-Server** (Föderation), abgesichert mit einem Schlüssel pro Freundschaft |

### Freundschaften zwischen Servern

Damit Freundschaften funktionieren, muss `KK_PUBLIC_URL` gesetzt und der Server **per HTTPS** von außen erreichbar sein.
Beim Annehmen eines Freundschaftslinks tauschen die beiden Server einen gemeinsamen Schlüssel aus; danach holt jeder Server
die Spielerkarte des Freundes direkt beim anderen Server ab. Es werden nur Spielwerte übertragen (Name, Level, Rang, Klasse,
Serie, Anzahl Erfolge/Workouts, Wochenwerte). Freunde von Freunden erscheinen nur, wenn der Freund „Meine Freunde zeigen“
und die dritte Person „Für Freunde meiner Freunde sichtbar“ eingeschaltet hat.

---

## Entwicklung

```bash
# Server
cd server && go run .

# App (macOS mit Xcode 26)
brew install xcodegen
cd app && xcodegen generate && open Koerperkompass.xcodeproj
```

Team-ID für die Signierung in `app/Local.xcconfig` eintragen (`DEVELOPMENT_TEAM = ABCDE12345`, wird nicht eingecheckt).

GitHub Actions: `server.yml` baut bei Änderungen in `server/` das Docker-Image (`ghcr.io/drdothouse2106/koerperkompass`), `testflight.yml` baut bei Änderungen in `app/` die App und lädt sie zu TestFlight hoch.

## Lizenz

[MIT](LICENSE)
