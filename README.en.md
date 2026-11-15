# 🧭 Körperkompass

**Nutrition, weight, activity and sleep in one place – your data on your own server.**

Körperkompass has two parts:

- **iOS app** (`app/`) – one app for everyone on the App Store. SwiftUI, iOS 17+, no external dependencies.
- **Server** (`server/`) – **self-hosted by every user**: a single Go binary with SQLite, available as a Docker image.

There is no central service: the developers run no server and never see any data. Everyone is responsible for their own health data.

[Deutsche Version](README.md) · [Privacy](PRIVACY.md)

> ⚠️ **All values (calorie needs, nutrient estimates, analyses) are estimates only and no substitute for medical or nutritional advice.**

## Features

- 🍽 **Nutrition** – daily goals, protein/carb/fat rings, 7-day chart, diary (breakfast, lunch, dinner, snack), optional photo entry with nutrient estimate
- ⚖️ **Weight & measurements** – weight, body fat, waist, hip, chest, with history and target weight
- 🚶 **Activity & sleep** – steps, active energy, sleep, resting heart rate and workouts from Apple Health
- 💧 **Water**, 🏋️ **Training** – simple sample modules, templates for your own modules
- 🧭 **Compass** – 7/30/90-day analysis: averages, trends, goal achievement, correlations (e.g. sleep ↔ calories). Optional detailed analysis with Claude
- 👨‍👩‍👧 **Family** – several users per server, each only sees their own data
- ✈️ **Offline** – local cache, syncs when the server is reachable
- 🎮 **Demo mode** – sample data, no server needed

Languages: German (default) and English.

### Screenshots

_Placeholder_

## Server setup

### Docker Compose

```bash
mkdir koerperkompass && cd koerperkompass
curl -O https://raw.githubusercontent.com/DrdotHouse2106/K-rperkompass/main/server/docker-compose.yml
docker compose up -d
docker compose logs        # shows the pairing code
```

Then open `http://<server-ip>:8080` – the pairing code is shown there as a QR code as well.

| Variable | Meaning |
|---|---|
| `ANTHROPIC_API_KEY` | your own Claude API key for photo recognition and detailed analysis (optional) |
| `KK_PUBLIC_URL` | public address, e.g. `https://kompass.example.de` (for the QR code behind a reverse proxy) |
| `KK_MODEL` | Claude model (default `claude-opus-5-5`) |
| `PORT` | port (default `8080`) |
| `KK_DB` | SQLite file path (image: `/data/koerperkompass.db`) |

### Proxmox (LXC)

Create a Debian 12 container. Either install Docker (enable *nesting*) and use Docker Compose, or build the binary with Go and run it via systemd – see the German [README](README.md#auf-proxmox-lxc) for the exact commands.

### HTTPS via reverse proxy

Don't expose the server unprotected – put it behind a reverse proxy with a certificate.

**Caddy:**

```
kompass.example.de {
    reverse_proxy 192.168.1.20:8080
}
```

**Nginx Proxy Manager:** add a proxy host for your domain → scheme `http`, IP of the server, port `8080`; SSL tab: request a Let's Encrypt certificate, enable *Force SSL*; Advanced tab: `client_max_body_size 20m;`.

Set `KK_PUBLIC_URL` afterwards. A VPN (WireGuard, Tailscale) works as well.

### Backup

All data is stored in **one SQLite file** (`data/koerperkompass.db` plus `-wal`/`-shm`). Stop the container and copy `data/`, or run `sqlite3 data/koerperkompass.db ".backup backup.db"`. Per-user JSON export: in the app (*Settings → Data → Export*) or `GET /api/export`.

## Pairing the app

1. Open the app → **“Scan QR code”** and scan the code on the server's web page (or enter address and code manually).
2. Setup assistant: goal, weight, target weight, height, age, sex, activity, modules. Daily goals use **Mifflin-St Jeor** (with active energy from Apple Health if available) and can be changed later.
3. Optionally connect Apple Health.

More devices and family members: *Settings → Server → invite*, or `docker exec koerperkompass /koerperkompass invite` on the server.

## Modules

| Module | id | Fields |
|---|---|---|
| Nutrition | `nutrition` | kcal, protein, carbs, fat |
| Weight & measurements | `body` | weight, bodyFat, waist, hip, chest |
| Activity & sleep | `activity` | steps, activeEnergy, sleepHours, restingHR, workoutMinutes |
| Water | `water` | ml |
| Training | `training` | minutes |

A new module is one new file in the app and one in the server plus a list entry – see [CLAUDE.md](CLAUDE.md) (German).

## Privacy

- Data is stored **only on your own server** and locally on your iPhone. No analytics, ads or tracking.
- Apple Health data is only sent to your server after **explicit consent** in the app.
- **Claude API (optional):** only if your server has its own API key **and** you consented in the app are photos or summarised values sent to Anthropic via your server.
- Details: [PRIVACY.md](PRIVACY.md)

## License

[MIT](LICENSE)
