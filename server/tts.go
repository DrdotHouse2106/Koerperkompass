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
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
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
	"sarge":  {"de_DE-thorsten_emotional-medium", "angry", 0.85},
	"brutal": {"de_DE-thorsten_emotional-medium", "angry", 0.8},
	// Dark Motivation: tiefe, ruhige Erzählstimme (Deutsch / Englisch)
	"dark":   {"de_DE-thorsten-high", "", 1.3},
	"darkEn": {"en_US-ryan-high", "", 1.25},
	"drill":  {"de_DE-thorsten_emotional-medium", "angry", 0.95},
	"cheer":  {"de_DE-thorsten_emotional-medium", "amused", 0.9},
	"buddy":  {"de_DE-thorsten-high", "", 1.0},
	"calm":   {"de_DE-thorsten-high", "", 1.15},
	"coach":  {"de_DE-thorsten-high", "", 1.0},
	// Weitere Stimmen, in der App fest auswählbar (Einstellungen → Stimme)
	"neutral":   {"de_DE-thorsten_emotional-medium", "neutral", 1.0},
	"whisper":   {"de_DE-thorsten_emotional-medium", "whisper", 1.0},
	"surprised": {"de_DE-thorsten_emotional-medium", "surprised", 1.0},
	"kerstin":   {"de_DE-kerstin-medium", "", 1.0},
	"ramona":    {"de_DE-ramona-low", "", 1.0},
	"karlsson":  {"de_DE-karlsson-low", "", 1.0},
	"pavoque":   {"de_DE-pavoque-low", "", 1.0},
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

// Kurzer Verbindungsaufbau (schlafender PC fällt schnell durch), aber genug Zeit zum Erzeugen
var ttsClient = &http.Client{Timeout: 60 * time.Second, Transport: &http.Transport{DialContext: (&net.Dialer{Timeout: 2 * time.Second}).DialContext}}

// Dienste, die gerade nicht antworten, werden nur kurz übersprungen – nie dauerhaft
var (
	ttsMu   sync.Mutex
	ttsDown = map[string]time.Time{}
)

func ttsSkip(url string) bool {
	ttsMu.Lock()
	defer ttsMu.Unlock()
	return time.Now().Before(ttsDown[url])
}

func ttsMark(url string, ok bool) {
	ttsMu.Lock()
	defer ttsMu.Unlock()
	if ok {
		delete(ttsDown, url)
	} else {
		ttsDown[url] = time.Now().Add(15 * time.Second)
	}
}

func tts(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Text, Persona string
		Private       bool // „Nur auf dem iPhone“: nichts auf dem Server zwischenspeichern
	}
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
		w.Header().Set("X-KK-TTS-Final", "1") // endgültige Fassung – darf auf dem iPhone zwischengespeichert werden
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
	best := false // Ergebnis vom ersten (bevorzugten) Dienst?
	for i, url := range services {
		if i < len(services)-1 && ttsSkip(url) {
			errs = append(errs, url+" schläft gerade")
			continue
		}
		d, err := ttsCall(url, b)
		ttsMark(url, err == nil)
		if err == nil {
			data, best = d, i == 0
			break
		}
		errs = append(errs, err.Error())
	}
	if data == nil {
		http.Error(w, "Sprachausgabe fehlgeschlagen: "+strings.Join(errs, "; "), http.StatusBadGateway)
		return
	}
	// Nur die bevorzugte Stimme dauerhaft speichern – Rückfall-Töne (z. B. Piper, solange Kartoffelbox schläft) nicht
	if best && !req.Private {
		if os.MkdirAll(ttsDir(), 0o750) == nil {
			os.WriteFile(file, data, 0o640)
		}
		w.Header().Set("X-KK-TTS-Final", "1")
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

// ttsWake weckt den Sprach-PC per Wake-on-LAN (KK_TTS_WAKE_MAC, Ziel KK_TTS_WAKE_ADDR, Standard 255.255.255.255:9)
// und meldet, ob der bevorzugte Sprachdienst schon antwortet.
var lastWake time.Time

func ttsWake(w http.ResponseWriter, r *http.Request) {
	services := strings.FieldsFunc(env("KK_TTS_URL", ""), func(c rune) bool { return c == ',' || c == ' ' })
	ready := len(services) > 0 && ttsReachable(services[0])
	sent := false
	if mac := env("KK_TTS_WAKE_MAC", ""); mac != "" && !ready {
		ttsMu.Lock()
		due := time.Since(lastWake) > 20*time.Second
		if due {
			lastWake = time.Now()
		}
		ttsMu.Unlock()
		if due {
			sent = sendMagicPacket(mac, env("KK_TTS_WAKE_ADDR", "255.255.255.255:9")) == nil
		}
	}
	if ready {
		ttsMark(services[0], true)
	}
	writeJSON(w, map[string]bool{"ready": ready || len(services) < 2, "sent": sent})
}

// ttsReachable: antwortet der Dienst (TCP-Verbindung in 1 Sekunde)?
func ttsReachable(url string) bool {
	host := strings.TrimPrefix(strings.TrimPrefix(url, "http://"), "https://")
	if i := strings.Index(host, "/"); i >= 0 {
		host = host[:i]
	}
	c, err := net.DialTimeout("tcp", host, time.Second)
	if err != nil {
		return false
	}
	c.Close()
	return true
}

// sendMagicPacket: 6 × 0xFF, dann 16 × die MAC-Adresse, per UDP-Broadcast
func sendMagicPacket(mac, addr string) error {
	hw, err := net.ParseMAC(mac)
	if err != nil {
		return err
	}
	packet := bytes.Repeat([]byte{0xFF}, 6)
	for i := 0; i < 16; i++ {
		packet = append(packet, hw...)
	}
	conn, err := net.Dial("udp", addr)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Write(packet)
	return err
}
