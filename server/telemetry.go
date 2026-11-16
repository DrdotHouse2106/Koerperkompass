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
	"net/http"
	"strings"
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

// collect: Hauptserver nimmt anonyme Daten an (nur mit KK_COLLECT=1).
func collect(w http.ResponseWriter, r *http.Request) {
	if env("KK_COLLECT", "") != "1" {
		http.NotFound(w, r)
		return
	}
	var req struct {
		Items []json.RawMessage `json:"items"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	if len(req.Items) > 200 {
		http.Error(w, "zu viele Einträge", http.StatusBadRequest)
		return
	}
	db.Exec(collectSchema)
	now := time.Now().Unix()
	for _, it := range req.Items {
		if len(it) < 4000 && json.Valid(it) {
			db.Exec(`INSERT INTO collected(received, data) VALUES(?,?)`, now, string(it))
		}
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
