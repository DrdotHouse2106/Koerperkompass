package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// App-Protokoll für die Testphase: Die App meldet Abläufe (Tippen, Abgleich, Server-Aufrufe, Fehler)
// an den eigenen Server – nur Kennungen und Zeitstempel, keine Gesundheitswerte.
// Wird nie weitergeleitet. Pro Nutzer bleiben die letzten 5000 Zeilen.

func migrateAppLog() {
	db.Exec(`CREATE TABLE IF NOT EXISTS applog (user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, ts INTEGER NOT NULL, msg TEXT NOT NULL)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS applog_user ON applog(user_id, ts)`)
}

// POST /api/log – Liste von {ts, msg}
func postAppLog(w http.ResponseWriter, r *http.Request) {
	var lines []struct {
		TS  int64  `json:"ts"`
		Msg string `json:"msg"`
	}
	if !readJSON(w, r, &lines) {
		return
	}
	u := uid(r)
	for _, l := range lines {
		db.Exec(`INSERT INTO applog(user_id, ts, msg) VALUES(?,?,?)`, u, l.TS, truncate(l.Msg, 2000))
	}
	db.Exec(`DELETE FROM applog WHERE user_id=? AND ts < (SELECT ts FROM applog WHERE user_id=? ORDER BY ts DESC LIMIT 1 OFFSET 5000)`, u, u)
	w.WriteHeader(http.StatusNoContent)
}

// GET /api/log?n=500 – als Text, neueste zuletzt
func getAppLog(w http.ResponseWriter, r *http.Request) {
	n, _ := strconv.Atoi(r.URL.Query().Get("n"))
	if n <= 0 || n > 5000 {
		n = 500
	}
	rows, err := db.Query(`SELECT ts, msg FROM (SELECT ts, msg FROM applog WHERE user_id=? ORDER BY ts DESC LIMIT ?) ORDER BY ts`, uid(r), n)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	var b strings.Builder
	for rows.Next() {
		var ts int64
		var msg string
		rows.Scan(&ts, &msg)
		fmt.Fprintf(&b, "%s %s\n", time.UnixMilli(ts).Format("2006-01-02 15:04:05.000"), msg)
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte(b.String()))
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

// Testdaten: Auf ausdrücklichen Wunsch schickt die App eine lesbare Kopie aller eigenen Daten (Profil, Einträge,
// Gesprächsprotokoll) zur Auswertung in der Testphase – die einzige Ausnahme von der Verschlüsselungspflicht.
// Pro Nutzer nur die neueste Kopie, nach 14 Tagen gelöscht, jederzeit löschbar. Nie weitergeleitet.
func migrateDebugDump() {
	db.Exec(`CREATE TABLE IF NOT EXISTS debug_dump (user_id INTEGER PRIMARY KEY, data TEXT NOT NULL, created INTEGER NOT NULL)`)
	db.Exec(`DELETE FROM debug_dump WHERE created < ?`, time.Now().AddDate(0, 0, -14).Unix())
}

// POST /api/debug/dump – lesbare Kopie speichern (ersetzt die vorige)
func postDebugDump(w http.ResponseWriter, r *http.Request) {
	data, err := io.ReadAll(io.LimitReader(r.Body, 50<<20))
	if err != nil || !json.Valid(data) {
		http.Error(w, "ungültige Daten", http.StatusBadRequest)
		return
	}
	db.Exec(`INSERT INTO debug_dump(user_id, data, created) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET data=excluded.data, created=excluded.created`,
		uid(r), string(data), time.Now().Unix())
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /api/debug/dump
func deleteDebugDump(w http.ResponseWriter, r *http.Request) {
	db.Exec(`DELETE FROM debug_dump WHERE user_id=?`, uid(r))
	w.WriteHeader(http.StatusNoContent)
}
