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
| 💧 **Wasser**, 🏋️ **Training** | einfache Beispielmodule – Vorlage für eigene Module |
| 🧭 **Kompass** | Auswertung über 7/30/90 Tage: Durchschnitte, Trends, Zielerreichung, Zusammenhänge (z. B. Schlaf ↔ Kalorien). Optional ausführliche Auswertung mit Claude |
| 👨‍👩‍👧 **Familie** | mehrere Nutzer pro Server, jeder sieht nur seine Daten |
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
curl -O https://raw.githubusercontent.com/DrdotHouse2106/K-rperkompass/main/server/docker-compose.yml
docker compose up -d
docker compose logs        # zeigt den Kopplungscode
```

Danach `http://<server-ip>:8080` im Browser öffnen: Dort steht der Kopplungscode auch als QR-Code.

**Umgebungsvariablen** (alle optional):

| Variable | Bedeutung |
|---|---|
| `ANTHROPIC_API_KEY` | eigener Claude-API-Key ([console.anthropic.com](https://console.anthropic.com)) für Foto-Erkennung und ausführliche Analyse. Ohne Key gibt es nur die lokale Auswertung. |
| `KK_PUBLIC_URL` | öffentliche Adresse, z. B. `https://kompass.example.de` (für den QR-Code hinter einem Reverse Proxy) |
| `KK_MODEL` | Claude-Modell (Standard: `claude-opus-5-5`) |
| `PORT` | Port (Standard: `8080`) |
| `KK_DB` | Pfad der SQLite-Datei (im Image: `/data/koerperkompass.db`) |

Anfragen an Claude nutzen den serverseitigen Fallback der API: Lehnt das Modell eine Anfrage ab, beantwortet ein Ersatzmodell sie.

### Auf Proxmox (LXC)

**Variante A – Docker im LXC:** Debian-12-Container anlegen (unprivilegiert, Option *Nesting* aktivieren), dann:

```bash
apt update && apt install -y docker.io docker-compose-plugin curl
```

und weiter wie bei Docker Compose.

**Variante B – ohne Docker:** Debian-12-Container anlegen, dann:

```bash
apt update && apt install -y golang git
git clone https://github.com/DrdotHouse2106/K-rperkompass.git /opt/kk-src
cd /opt/kk-src/server && CGO_ENABLED=0 go build -o /usr/local/bin/koerperkompass .
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

**Weitere Geräte und Familienmitglieder:** *Einstellungen → Server → „Weiteres eigenes Gerät koppeln“* bzw. *„Familienmitglied einladen“* zeigt einen QR-Code (einmalig, 24 Stunden gültig).
Auf dem Server geht es auch mit `docker exec koerperkompass /koerperkompass invite`.

**Ohne Server ausprobieren:** „Demo ausprobieren“ auf dem Startbildschirm.

---

## Module

| Modul | id | Felder | Quelle |
|---|---|---|---|
| Ernährung | `nutrition` | kcal, protein, carbs, fat (+ meal, name, photo) | Eingabe, Foto |
| Gewicht & Maße | `body` | weight, bodyFat, waist, hip, chest | Eingabe, Apple Health (Gewicht) |
| Aktivität & Schlaf | `activity` | steps, activeEnergy, sleepHours, restingHR, workoutMinutes | Apple Health |
| Wasser | `water` | ml | Eingabe (Beispielmodul) |
| Training | `training` | minutes (+ name) | Eingabe (Beispielmodul) |

Module lassen sich in den Einstellungen ein- und ausschalten. Ein neues Modul ist eine neue Datei in App und Server plus ein Listeneintrag – siehe [CLAUDE.md](CLAUDE.md).

---

## Datenschutz

- Alle Daten liegen **nur auf deinem eigenen Server** und lokal auf deinem iPhone. Es gibt keine Analyse-, Werbe- oder Tracking-Dienste.
- **Apple Health:** Die App liest Health-Daten nur nach deiner Freigabe. An deinen Server gehen sie erst nach einer **ausdrücklichen Zustimmung** in der App.
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
| POST | `/api/ai/photo`, `/api/ai/analysis` | nur mit `ANTHROPIC_API_KEY` |

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
