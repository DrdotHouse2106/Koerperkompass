#!/usr/bin/env python3
"""Feste Sprüche der Coaches vorab rendern (z. B. nachts) – sie werden danach sofort abgespielt.

  python3 vorab.py --url http://<kartoffelbox>:5100 --out /var/lib/koerperkompass/tts [saetze.json]

Schreibt je Satz <sha256("persona|text")>.wav – genau so sucht der Körperkompass-Server danach (server/tts.go).
Vorhandene Dateien werden übersprungen, das Skript kann also jederzeit erneut laufen.
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.request

p = argparse.ArgumentParser()
p.add_argument("--url", default="http://127.0.0.1:5100")
p.add_argument("--out", default="tts")
p.add_argument("saetze", nargs="?", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "saetze.json"))
a = p.parse_args()

os.makedirs(a.out, exist_ok=True)
saetze = json.load(open(a.saetze, encoding="utf-8"))
total = sum(len(v) for v in saetze.values())
done = 0
for persona, texts in saetze.items():
    for text in texts:
        done += 1
        file = os.path.join(a.out, hashlib.sha256(f"{persona}|{text}".encode()).hexdigest() + ".wav")
        if os.path.exists(file):
            continue
        start = time.time()
        req = urllib.request.Request(a.url, json.dumps({"text": text, "persona": persona}).encode(), {"Content-Type": "application/json"})
        try:
            data = urllib.request.urlopen(req, timeout=600).read()
        except Exception as e:
            print(f"[{done}/{total}] Fehler bei {persona}: {e}", file=sys.stderr)
            continue
        open(file, "wb").write(data)
        print(f"[{done}/{total}] {persona} ({time.time() - start:.1f} s): {text}")
print("Fertig.")
