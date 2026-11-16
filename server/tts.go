package main

// Sprachausgabe vom eigenen Server (optional): POST /api/tts {text, persona} → WAV.
//
// 1. Vorab erzeugte Dateien (z. B. mit Kartoffelbox, siehe tools/tts/) liegen im Ordner KK_TTS_DIR
//    (Standard: Ordner „tts“ neben der Datenbank) als <sha256(persona|text)>.wav – sie werden sofort geliefert.
// 2. Sonst wird der Text live erzeugt: KK_TTS_URL enthält einen oder mehrere Sprachdienste (durch Komma getrennt),
//    die der Reihe nach probiert werden – z. B. zuerst Kartoffelbox auf dem GPU-Rechner (tools/tts/kartoffelbox_server.py),
//    dann Piper auf enten. Das Ergebnis wird im selben Ordner zwischengespeichert.
//    Ohne Dienst und ohne vorab erzeugte Datei: 404 – die App nimmt dann die iPhone-Stimme.
//
// An jeden Dienst geht {"text", "persona", "voice", "speaker", "length_scale"}: Piper nutzt voice/speaker/length_scale,
// der Kartoffelbox-Dienst nutzt persona.

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Stimme je Coach-Stil (Piper-Stimmen „Thorsten“; die emotionale Stimme hat Sprecher wie angry, amused, neutral).
// Anpassbar über KK_TTS_VOICES als JSON, z. B. {"sarge":{"voice":"…","speaker":"angry","length":0.85}}.
type ttsVoice struct {
	Voice   string  `json:"voice"`
	Speaker string  `json:"speaker"`
	Length  float64 `json:"length"` // < 1 schneller, > 1 langsamer
}

var defaultVoices = map[string]ttsVoice{
	"sarge": {"de_DE-thorsten_emotional-medium", "angry", 0.85},
	"drill": {"de_DE-thorsten_emotional-medium", "angry", 0.95},
	"cheer": {"de_DE-thorsten_emotional-medium", "amused", 0.9},
	"buddy": {"de_DE-thorsten-high", "", 1.0},
	"calm":  {"de_DE-thorsten-high", "", 1.15},
	"coach": {"de_DE-thorsten-high", "", 1.0},
}

func ttsVoices() map[string]ttsVoice {
	v := map[string]ttsVoice{}
	for k, x := range defaultVoices {
		v[k] = x
	}
	if custom := env("KK_TTS_VOICES", ""); custom != "" {
		json.Unmarshal([]byte(custom), &v)
	}
	return v
}

func ttsDir() string {
	return env("KK_TTS_DIR", filepath.Join(filepath.Dir(env("KK_DB", "data/koerperkompass.db")), "tts"))
}

// TTSKey: Dateiname für einen Satz – identisch im Vorab-Skript tools/tts/vorab.py
func ttsKey(persona, text string) string {
	h := sha256.Sum256([]byte(persona + "|" + text))
	return hex.EncodeToString(h[:])
}

var ttsClient = &http.Client{Timeout: 60 * time.Second}

func tts(w http.ResponseWriter, r *http.Request) {
	var req struct{ Text, Persona string }
	if !readJSON(w, r, &req) {
		return
	}
	req.Text = strings.TrimSpace(req.Text)
	if req.Text == "" || len(req.Text) > 1500 {
		http.Error(w, "Text fehlt oder ist zu lang", http.StatusBadRequest)
		return
	}
	if _, ok := ttsVoices()[req.Persona]; !ok {
		req.Persona = "coach"
	}
	file := filepath.Join(ttsDir(), ttsKey(req.Persona, req.Text)+".wav")
	if data, err := os.ReadFile(file); err == nil {
		w.Header().Set("Content-Type", "audio/wav")
		w.Write(data)
		return
	}
	services := strings.FieldsFunc(env("KK_TTS_URL", ""), func(c rune) bool { return c == ',' || c == ' ' })
	if len(services) == 0 {
		http.Error(w, "keine Sprachausgabe auf dem Server eingerichtet", http.StatusNotFound)
		return
	}
	v := ttsVoices()[req.Persona]
	body := map[string]any{"text": req.Text, "persona": req.Persona, "voice": v.Voice, "length_scale": v.Length}
	if v.Speaker != "" {
		body["speaker"] = v.Speaker
	}
	b, _ := json.Marshal(body)
	var data []byte
	var errs []string
	for _, url := range services {
		d, err := ttsCall(url, b)
		if err == nil {
			data = d
			break
		}
		errs = append(errs, err.Error())
	}
	if data == nil {
		http.Error(w, "Sprachausgabe fehlgeschlagen: "+strings.Join(errs, "; "), http.StatusBadGateway)
		return
	}
	if os.MkdirAll(ttsDir(), 0o750) == nil {
		os.WriteFile(file, data, 0o640) // für das nächste Mal zwischenspeichern
	}
	w.Header().Set("Content-Type", "audio/wav")
	w.Write(data)
}

// ttsCall fragt einen Sprachdienst an und liefert WAV-Daten.
func ttsCall(url string, body []byte) ([]byte, error) {
	resp, err := ttsClient.Post(strings.TrimRight(url, "/"), "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("%s nicht erreichbar", url)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 20<<20))
	if resp.StatusCode != 200 || len(data) < 44 || string(data[:4]) != "RIFF" {
		return nil, fmt.Errorf("%s: Fehler %s", url, strconv.Itoa(resp.StatusCode))
	}
	return data, nil
}
