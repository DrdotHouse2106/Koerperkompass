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
/opt/piper/bin/python -m piper.download_voices --data-dir /opt/piper/stimmen de_DE-thorsten-high de_DE-thorsten_emotional-medium \
  de_DE-kerstin-medium de_DE-ramona-low de_DE-karlsson-low de_DE-pavoque-low   # weitere Stimmen, in der App wählbar
/opt/piper/bin/python -m piper.http_server --data-dir /opt/piper/stimmen -m de_DE-thorsten-high --host 127.0.0.1 --port 5000
```

Körperkompass-Server: `KK_TTS_URL=http://127.0.0.1:5000/synthesize` (Piper 1.8 nimmt POST nur unter `/synthesize` an).
Felder: `text`, `voice` (Dateiname ohne `.onnx`), `speaker` (bei Thorsten emotional: amused, angry, disgusted, drunk,
neutral, sleepy, surprised, whisper), `length_scale`. Stimme je Coach-Stil: siehe `defaultVoices` in `server/tts.go`,
anpassbar mit `KK_TTS_VOICES` (JSON). Rechenzeit auf einem i3-8109U: etwa 0,1–0,6 s pro Satz.

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
- Körperkompass-Server: `KK_TTS_URL=http://<kartoffelbox>:5100,http://127.0.0.1:5000/synthesize` (Kartoffelbox vor Piper).

## Feste Sprüche vorab rendern

```bash
python3 vorab.py --url http://<kartoffelbox>:5100 --out /var/lib/koerperkompass/tts saetze.json
```

`saetze.json` enthält die festen Sprüche je Coach-Stil (Anfeuern, „Pause vorbei“, „Noch zehn Sekunden.“). Die Texte müssen
genau so lauten wie in der App (`Persona` in `app/Koerperkompass/Views/VoiceCoachView.swift`). Das Skript überspringt
vorhandene Dateien und kann jederzeit erneut laufen.

## Sprach-PC nur bei Bedarf (Wake-on-LAN)

Startet jemand den Trainings- oder Gesundheitscoach, ruft die App `POST /api/tts/wake` auf. Der Körperkompass-Server schickt
dann ein Wake-on-LAN-Paket an den Sprach-PC (`KK_TTS_WAKE_MAC`, Ziel `KK_TTS_WAKE_ADDR`, z. B. `192.168.72.255:9`) und meldet,
ob Kartoffelbox schon antwortet. Bis dahin sprechen vorgerenderte Sätze und Piper; die App zeigt „Kleinen Moment, die Stimme
wird geladen …“. Ein nicht erreichbarer Dienst wird nur 15 Sekunden übersprungen, dann erneut versucht. Rückfall-Töne werden
nicht dauerhaft gespeichert – nur die Fassung des bevorzugten Dienstes (Kopfzeile `X-KK-TTS-Final: 1`).
Das Herunterfahren nach längerer Ruhe regelt der Sprach-PC selbst.
