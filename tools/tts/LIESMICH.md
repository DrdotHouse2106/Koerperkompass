# Sprachausgabe vom eigenen Server (optional)

Die App spricht standardmäßig mit der iPhone-Stimme. Mit einem Sprachdienst im Heimnetz klingen die Coaches
natürlicher – je Coach-Stil mit eigenem Tonfall (der Drill Sergeant brüllt wirklich). Alles bleibt im Heimnetz.

Der Körperkompass-Server (`POST /api/tts`, siehe `server/tts.go`) liefert:

1. **vorab gerenderte Sätze** aus `KK_TTS_DIR` (Standard: Ordner `tts` neben der Datenbank) – sofort,
2. sonst **live** von den Diensten in `KK_TTS_URL` (der Reihe nach, durch Komma getrennt), Ergebnis wird zwischengespeichert,
3. sonst nichts – dann spricht die App mit der iPhone-Stimme.

## Piper (schnell, läuft auf jeder CPU)

```bash
python3 -m venv /opt/piper && /opt/piper/bin/pip install "piper-tts[http]"
/opt/piper/bin/python -m piper.download_voices --data-dir /opt/piper/stimmen de_DE-thorsten-high de_DE-thorsten_emotional-medium
/opt/piper/bin/python -m piper.http_server --data-dir /opt/piper/stimmen -m de_DE-thorsten-high --host 127.0.0.1 --port 5000
```

Körperkompass-Server: `KK_TTS_URL=http://127.0.0.1:5000`. Stimme je Coach-Stil: siehe `defaultVoices` in `server/tts.go`,
anpassbar mit `KK_TTS_VOICES` (JSON). Prüfen, ob die installierte Piper-Version die Felder `voice`, `speaker` und `length_scale` annimmt.

## Kartoffelbox (sehr natürlich, Grafikkarte empfohlen)

Deutsches Modell auf Basis von Chatterbox: <https://huggingface.co/SebastianBodza/Kartoffelbox-v0.1>
(zugangsbeschränkt – auf Hugging Face anmelden, Bedingungen akzeptieren, `huggingface-cli login`).

```bash
python3 -m venv /opt/kartoffelbox && /opt/kartoffelbox/bin/pip install chatterbox-tts soundfile
/opt/kartoffelbox/bin/python kartoffelbox_server.py      # lauscht auf :5100
```

- NVIDIA-Grafikkarte mit ≥ 6 GB empfohlen; ohne Grafikkarte läuft es langsam (zum Vorrendern reicht das).
- Ältere Karten (z. B. GTX 1060, Pascal): eine PyTorch-Version mit Unterstützung für diese Generation verwenden.
- Optional Referenzstimmen je Stil in `stimmen/<stil>.wav` (5–15 s). Nur eigene Aufnahmen oder freie Sprachspenden –
  keine Stimmen echter Personen ohne deren Einverständnis.
- Körperkompass-Server: `KK_TTS_URL=http://<kartoffelbox>:5100,http://127.0.0.1:5000` (Kartoffelbox vor Piper).

## Feste Sprüche vorab rendern

```bash
python3 vorab.py --url http://<kartoffelbox>:5100 --out /var/lib/koerperkompass/tts saetze.json
```

`saetze.json` enthält die festen Sprüche je Coach-Stil (Anfeuern, „Pause vorbei“, „Noch zehn Sekunden.“). Die Texte müssen
genau so lauten wie in der App (`Persona` in `app/Koerperkompass/Views/VoiceCoachView.swift`). Das Skript überspringt
vorhandene Dateien und kann jederzeit erneut laufen.
