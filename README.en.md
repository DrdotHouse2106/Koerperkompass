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
- 🗺 **My plan** – overview: weight path to goal, BMI scale, daily goals, water and training
- 🏁 **Adventure** – gamification: character card, shareable player card with your own photo, achievements, week strip and 🔥 streak, daily and custom quests, XP, levels, ranks, attributes
- 📖 **Recipes** – your own recipe collection: paste any link – reels/videos (Facebook, Instagram, TikTok, YouTube) go to Reelkoch on your server, recipe websites are imported directly – or paste recipe text. Nutrition per serving, “Eaten” logs servings, the coach suggests matching recipes. **Cook with the coach:** step-by-step help with questions by text or voice, “hands-free” listens again after each answer
- 🧠 **Mood** – state of mind like Apple Health (read and write, iOS 18)
- 🤒 **Symptoms** – stuffy nose, cough, headache, fever … with severity, synced with Apple Health “Symptoms”; the coach proposes entries when you mention them and adapts training advice
- 📈 **Exercises** – log sets with reps and weight, progress chart per exercise, tiers bronze → silver → gold → platinum
- 🏋️ **Training programs** – 4-week programs with training and rest days, XP per session, templates or created by Claude; optional penalties for missed sessions
- 💧 **Drinks** – water, coffee, tea, beer, wine … with one tap; drinking goal, caffeine, alcohol; drink reminders you can tick off in the notification
- 🏋️ **Training** – own tab with today’s session and nine ready-made programs
- 🔔 **Reminders** – motivational messages in the morning (optionally evening), a different one every day, personalised with name, streak and goal
- 🎙 **Voice coach** – talk during training, sets are logged and rest is counted down; runs on-device with Apple Intelligence (free, offline). Siri: “Log water in Körperkompass”
- 💬 **Coach** – personal health coach (Claude) in a chat that knows your goals, food, drinks, weight and training; daily briefing and reminder (needs `ANTHROPIC_API_KEY`)
- 🧭 **Compass** – 7/30/90-day analysis: averages, trends, goal achievement, correlations (e.g. sleep ↔ calories). Optional detailed analysis with Claude
- 🔐 **End-to-end encryption** – optional with your own password: entries and profile are encrypted on the iPhone, the server (and its operator) sees no content. Recovery key for “forgot password”
- 📱 **iPhone only** – optionally keep all data only on the iPhone: the server deletes its copy and only forwards to Claude and speech output (Settings → Storage)
- 🤝 **Friends (decentralised)** – friendships with users on your own or **other Körperkompass servers**, no central service: friend list with player cards, weekly challenge leaderboard, optionally friends of friends. Only game values are shared, never health data (requires `KK_PUBLIC_URL` and HTTPS)
- 👥 **Multiple users** – invite other people, each with their own account, own access and own data
- ✈️ **Offline** – local cache, syncs when the server is reachable
- 🎮 **Demo mode** – sample data, no server needed

Languages: German (default) and English.

### Screenshots

_Placeholder_

## Server setup

### Docker Compose

```bash
mkdir koerperkompass && cd koerperkompass
curl -O https://raw.githubusercontent.com/DrdotHouse2106/Koerperkompass/main/server/docker-compose.yml
docker compose up -d
docker compose logs        # shows the pairing code
```

Then open `http://<server-ip>:8080` – the pairing code is shown there as a QR code as well.

| Variable | Meaning |
|---|---|
| `ANTHROPIC_API_KEY` | your own Claude API key for photo recognition and detailed analysis (optional) |
| `KK_PUBLIC_URL` | public address, e.g. `https://kompass.example.de` (for the QR code behind a reverse proxy) |
| `KK_MODEL` | Claude model (default `claude-opus-5-5`) |
| `KK_REELKOCH_URL`, `KK_REELKOCH_TOKEN` | optional: address and API token of [Reelkoch](https://github.com/DrdotHouse2106/Reelkoch) – recipes from reel links |
| `PORT` | port (default `8080`) |
| `KK_DB` | SQLite file path (image: `/data/koerperkompass.db`) |

### Proxmox (LXC)

Create a Debian 12 container. Either install Docker (enable *nesting*) and use Docker Compose, or build the binary with Go and run it via systemd – see the German [README](README.md#auf-proxmox-lxc) for the exact commands.
Building needs about 2.5 GB RAM; in small LXC containers (where `/tmp` is a RAM tmpfs) set `GOCACHE=/var/tmp/go-cache GOTMPDIR=/var/tmp GOMAXPROCS=1` and build with `-p 1`.

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

## Getting the app onto your iPhone

Until it is on the App Store: create the app in App Store Connect (bundle ID `de.drdothouse.koerperkompass`, HealthKit enabled), create an App Store Connect API key, add the secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` to the GitHub repo, run the “TestFlight (iOS)” workflow and install the build via the TestFlight app. Alternatively build it from Xcode on a Mac. Details in the German [README](README.md#app-auf-dein-iphone-bringen).

## Modules

| Module | id | Fields |
|---|---|---|
| Adventure | `quests` | – (computed from all other modules) |
| Nutrition | `nutrition` | kcal, protein, carbs, fat |
| Weight & measurements | `body` | weight, bodyFat, waist, hip, chest |
| Activity & sleep | `activity` | steps, activeEnergy, sleepHours, restingHR, workoutMinutes |
| Water | `water` | ml |
| Training | `training` | minutes |
| Recipes | `recipes` | – (recipe with nutrition per serving) |
| Mood | `mood` | mood (1–7, + valence, feelings, areas, kind, time) |
| Symptoms | `symptoms` | severity (1–3, + symptom, name, time) |

A new module is one new file in the app and one in the server plus a list entry – see [CLAUDE.md](CLAUDE.md) (German).

## Privacy

- Data is stored **only on your own server** and locally on your iPhone. No analytics, ads or tracking.
- Apple Health data is only sent to your server after **explicit consent** in the app.
- **Claude API (optional):** only if your server has its own API key **and** you consented in the app are photos or summarised values sent to Anthropic via your server.
- Details: [PRIVACY.md](PRIVACY.md)

## License

[MIT](LICENSE)
