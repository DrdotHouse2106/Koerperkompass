#!/usr/bin/env python3
"""Kartoffelbox-Sprachdienst für Körperkompass (nur im Heimnetz betreiben).

POST /  {"text": "...", "persona": "brutal|sarge|drill|cheer|buddy|calm|coach"}  →  WAV (16 Bit, mono)

Kartoffelbox ist ein deutsches Text-to-Speech-Modell auf Basis von Chatterbox
(https://huggingface.co/SebastianBodza/Kartoffelbox-v0.1, zugangsbeschränkt: vorher auf Hugging Face anmelden,
Bedingungen akzeptieren und `huggingface-cli login` ausführen).

Einstellungen über Umgebungsvariablen:
  KB_HOST / KB_PORT   Adresse und Port (Standard 0.0.0.0:5100)
  KB_REF_DIR          Ordner mit optionalen Referenzstimmen <persona>.wav (5–15 s, eigene Aufnahme oder freie Sprachspende –
                      keine Stimmen echter Personen ohne deren Einverständnis)
  KB_DEVICE           cuda oder cpu (Standard: cuda, wenn verfügbar)

Im Körperkompass-Server: KK_TTS_URL=http://<dieser-rechner>:5100,http://127.0.0.1:5000  (Kartoffelbox vor Piper)
"""
import io
import json
import os
import threading
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import torch
from chatterbox.tts import ChatterboxTTS
from huggingface_hub import hf_hub_download
from safetensors.torch import load_file

# Ausdruck je Coach-Stil: exaggeration = Übertreibung/Emotion, cfg_weight = Tempo/Treue, temperature = Lebendigkeit
PERSONAS = {
    "sarge": dict(exaggeration=1.2, cfg_weight=0.3, temperature=0.8),  # Drill Sergeant – Hardcore: brüllt
    "dark": dict(exaggeration=0.35, cfg_weight=0.3, temperature=0.7),  # Dark Motivation: tief, ruhig, langsam
    "brutal": dict(exaggeration=1.3, cfg_weight=0.3, temperature=0.85),  # Drill Sergeant – Ohne Gnade
    "drill": dict(exaggeration=0.9, cfg_weight=0.3, temperature=0.7),
    "cheer": dict(exaggeration=0.9, cfg_weight=0.4, temperature=0.8),
    "buddy": dict(exaggeration=0.5, cfg_weight=0.4, temperature=0.6),
    "calm": dict(exaggeration=0.3, cfg_weight=0.5, temperature=0.5),
    "coach": dict(exaggeration=0.4, cfg_weight=0.5, temperature=0.6),
}
REF_DIR = os.environ.get("KB_REF_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "stimmen"))
DEVICE = os.environ.get("KB_DEVICE") or ("cuda" if torch.cuda.is_available() else "cpu")

print(f"Lade Kartoffelbox auf {DEVICE} …", flush=True)
model = ChatterboxTTS.from_pretrained(device=DEVICE)
model.t3.load_state_dict(load_file(hf_hub_download("SebastianBodza/Kartoffelbox-v0.1", "t3_cfg.safetensors"), device="cpu"))
lock = threading.Lock()  # eine Grafikkarte – immer nur ein Satz gleichzeitig
print("Bereit.", flush=True)


def synthesize(text: str, persona: str) -> bytes:
    params = PERSONAS.get(persona, PERSONAS["coach"])
    ref = os.path.join(REF_DIR, f"{persona}.wav")
    with lock, torch.inference_mode():
        wav = model.generate(text, audio_prompt_path=ref if os.path.exists(ref) else None, **params)
    samples = (wav.squeeze().cpu().numpy().clip(-1, 1) * 32767).astype(np.int16)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(model.sr)
        w.writeframes(samples.tobytes())
    return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            req = json.loads(self.rfile.read(min(int(self.headers.get("Content-Length", 0)), 20000)))
            text = str(req.get("text", "")).strip()
            if not text or len(text) > 1500:
                raise ValueError("Text fehlt oder ist zu lang")
            data = synthesize(text, str(req.get("persona", "coach")))
        except Exception as e:  # Fehler als Text zurück, der Körperkompass-Server probiert dann den nächsten Dienst
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())
            return
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):  # keine Texte ins Log schreiben
        pass


if __name__ == "__main__":
    ThreadingHTTPServer((os.environ.get("KB_HOST", "0.0.0.0"), int(os.environ.get("KB_PORT", "5100"))), Handler).serve_forever()
