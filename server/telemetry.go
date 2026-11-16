package main

// Anonyme Verbesserungsdaten (freiwillig, standardmäßig aus):
//
//   App → eigener Server (POST /api/telemetry) → Hauptserver (POST /api/collect)
//
// Der eigene Server reicht die von der App bereits anonymisierten Daten nur weiter – ohne Nutzerkennung, ohne
// Gesundheitswerte. Abschalten: KK_TELEMETRY=off. Ziel: KK_TELEMETRY_URL (Standard: Hauptserver des Projekts).
// Der Hauptserver nimmt nur an, wenn KK_COLLECT=1 gesetzt ist, speichert ohne IP-Adresse und gibt die Daten nur mit
// KK_COLLECT_TOKEN heraus (GET /api/collect, Header „Authorization: Bearer <token>“).

import (
	"bytes"
	"crypto/subtle"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

const collectSchema = `CREATE TABLE IF NOT EXISTS collected (id INTEGER PRIMARY KEY, received INTEGER NOT NULL, data TEXT NOT NULL);`

// telemetry: von der eigenen App, wird unverändert (nur die Liste „items“) an den Hauptserver weitergereicht.
func telemetry(w http.ResponseWriter, r *http.Request) {
	if env("KK_TELEMETRY", "") == "off" {
		http.Error(w, "Weiterleitung auf diesem Server abgeschaltet", http.StatusNotImplemented)
		return
	}
	var req struct {
		Items []json.RawMessage `json:"items"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	if len(req.Items) == 0 || len(req.Items) > 200 {
		http.Error(w, "1 bis 200 Einträge", http.StatusBadRequest)
		return
	}
	body, _ := json.Marshal(map[string]any{"items": req.Items})
	target := env("KK_TELEMETRY_URL", "https://kompass.ulber.me/api/collect")
	resp, err := fedClient.Post(target, "application/json", bytes.NewReader(body))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 500))
		http.Error(w, strings.TrimSpace(string(msg)), http.StatusBadGateway)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Erlaubte Felder je Eintrag: Typ und Höchstlänge bei Text. Alles andere wird verworfen.
var collectFields = map[string]int{
	"kind": 20, "persona": 20, "source": 20, "app": 20, "ios": 5, "lang": 5, "exercise": 80,
	"heard": 1000, "reply": 3000, // Texte nur, wenn Nutzer sie zusätzlich freigegeben haben
	"ms": -1, "rest": -1, // Zahlen
	"setDetected": -2, "onDevice": -2, // Wahrheitswerte
}

// validItem prüft einen Eintrag gegen collectFields und liefert ihn bereinigt zurück.
func validItem(raw json.RawMessage) (map[string]any, bool) {
	var it map[string]any
	if json.Unmarshal(raw, &it) != nil || len(it) == 0 {
		return nil, false
	}
	for k, v := range it {
		limit, ok := collectFields[k]
		if !ok {
			return nil, false
		}
		switch x := v.(type) {
		case string:
			if limit < 0 || len(x) > limit {
				return nil, false
			}
		case float64:
			if limit != -1 || x < 0 || x > 1e7 {
				return nil, false
			}
		case bool:
			if limit != -2 {
				return nil, false
			}
		default:
			return nil, false
		}
	}
	return it, true
}

// Anfragen-Limit pro Absender-IP für /api/collect – nur im Arbeitsspeicher, IP-Adressen werden nicht gespeichert.
var (
	collectMu   sync.Mutex
	collectHits = map[string][]time.Time{}
)

// clientIP: hinter dem eigenen Reverse Proxy (KK_TRUSTED_PROXY, z. B. 10.8.0.1) zählt der letzte Eintrag in
// X-Forwarded-For (vom Proxy angehängt), sonst die direkte Verbindung.
func clientIP(r *http.Request) string {
	ip := hostOnly(r.RemoteAddr)
	if proxy := env("KK_TRUSTED_PROXY", ""); proxy != "" && ip == proxy {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			parts := strings.Split(xff, ",")
			if p := strings.TrimSpace(parts[len(parts)-1]); net.ParseIP(p) != nil {
				return p
			}
		}
	}
	return ip
}

func allowCollect(ip string) bool {
	limit, err := strconv.Atoi(env("KK_COLLECT_LIMIT", "30"))
	if err != nil || limit < 1 {
		limit = 30
	}
	collectMu.Lock()
	defer collectMu.Unlock()
	cutoff := time.Now().Add(-time.Hour)
	if len(collectHits) > 10000 { // aufräumen, damit der Speicher nicht wächst
		for k, ts := range collectHits {
			if len(ts) == 0 || ts[len(ts)-1].Before(cutoff) {
				delete(collectHits, k)
			}
		}
	}
	recent := collectHits[ip][:0]
	for _, t := range collectHits[ip] {
		if t.After(cutoff) {
			recent = append(recent, t)
		}
	}
	if len(recent) >= limit {
		collectHits[ip] = recent
		return false
	}
	collectHits[ip] = append(recent, time.Now())
	return true
}

// collect: Hauptserver nimmt anonyme Daten an (nur mit KK_COLLECT=1).
// Schutz: höchstens 1 MB pro Anfrage, Limit pro Absender-IP (KK_COLLECT_LIMIT, Standard 30/Stunde),
// nur bekannte Felder mit passenden Typen und Längen.
func collect(w http.ResponseWriter, r *http.Request) {
	if env("KK_COLLECT", "") != "1" {
		http.NotFound(w, r)
		return
	}
	if !allowCollect(clientIP(r)) {
		w.Header().Set("Retry-After", "3600")
		http.Error(w, "zu viele Anfragen", http.StatusTooManyRequests)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var req struct {
		Items []json.RawMessage `json:"items"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	if len(req.Items) == 0 || len(req.Items) > 200 {
		http.Error(w, "1 bis 200 Einträge", http.StatusBadRequest)
		return
	}
	var valid []map[string]any
	for _, raw := range req.Items {
		if it, ok := validItem(raw); ok {
			valid = append(valid, it)
		}
	}
	if len(valid) == 0 {
		http.Error(w, "keine gültigen Einträge", http.StatusBadRequest)
		return
	}
	db.Exec(collectSchema)
	now := time.Now().Unix()
	for _, it := range valid {
		b, _ := json.Marshal(it)
		db.Exec(`INSERT INTO collected(received, data) VALUES(?,?)`, now, string(b))
	}
	// Obergrenze, damit die Datenbank nicht vollläuft
	db.Exec(`DELETE FROM collected WHERE id <= (SELECT MAX(id) - 200000 FROM collected)`)
	w.WriteHeader(http.StatusNoContent)
}

// collectExport: gesammelte Daten als JSON (nur mit KK_COLLECT_TOKEN).
func collectExport(w http.ResponseWriter, r *http.Request) {
	token := env("KK_COLLECT_TOKEN", "")
	got := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if env("KK_COLLECT", "") != "1" || token == "" || subtle.ConstantTimeCompare([]byte(token), []byte(got)) != 1 {
		http.NotFound(w, r)
		return
	}
	db.Exec(collectSchema)
	rows, err := db.Query(`SELECT received, data FROM collected ORDER BY id`)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var ts int64
		var data string
		rows.Scan(&ts, &data)
		out = append(out, map[string]any{"received": time.Unix(ts, 0).UTC().Format(time.RFC3339), "data": json.RawMessage(data)})
	}
	writeJSON(w, out)
}
