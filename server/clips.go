package main

// „Meine Clips“: private Motivations-Tonspuren aus Reels/Videos – nur für das eigene Konto, nie geteilt.
// Der Server lädt mit yt-dlp (KK_YTDLP, braucht ffmpeg) nur den Ton und legt ihn als m4a im Datenordner ab
// (clips/<Nutzer>/<id>.m4a). Ohne KK_YTDLP ist die Funktion aus. Die Verantwortung für die Nutzung
// (Privatkopie, keine Weitergabe) liegt bei der Person, die den Link einfügt.

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func clipsEnabled() bool { return env("KK_YTDLP", "") != "" }

func migrateClips() {
	db.Exec(`CREATE TABLE IF NOT EXISTS clips (user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		id TEXT NOT NULL, url TEXT NOT NULL, title TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL, PRIMARY KEY (user_id, id))`)
}

func clipDir(u int64) string {
	return filepath.Join(filepath.Dir(env("KK_DB", "data/koerperkompass.db")), "clips", strconv.FormatInt(u, 10))
}

// POST /api/clips {url} → Ton laden (höchstens 10 Minuten), Antwort {id, title}
func addClip(w http.ResponseWriter, r *http.Request) {
	var req struct{ URL string }
	if !clipsEnabled() {
		http.Error(w, "Meine Clips ist auf dem Server nicht eingerichtet (KK_YTDLP)", http.StatusNotImplemented)
		return
	}
	if !readJSON(w, r, &req) {
		return
	}
	u, err := url.Parse(strings.TrimSpace(req.URL))
	if err != nil || u.Scheme != "https" || u.Host == "" {
		http.Error(w, "Kein gültiger Link", http.StatusBadRequest)
		return
	}
	user := uid(r)
	dir := clipDir(user)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	b := make([]byte, 6)
	rand.Read(b)
	id := hex.EncodeToString(b)
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Minute)
	defer cancel()
	err = exec.CommandContext(ctx, env("KK_YTDLP", ""), "--no-playlist", "--no-progress", "-q", "-x", "--audio-format", "m4a",
		"--match-filter", "duration <= 600", "--max-filesize", "40M", "-o", filepath.Join(dir, id+".%(ext)s"), u.String()).Run()
	file := filepath.Join(dir, id+".m4a")
	if _, statErr := os.Stat(file); err != nil || statErr != nil {
		http.Error(w, "Ton konnte nicht geladen werden", http.StatusBadGateway)
		return
	}
	// Kein Titel aus dem Reel (dort steht nur die Beschreibung) – einen eigenen kann man in der App vergeben
	db.Exec(`INSERT INTO clips(user_id, id, url, created) VALUES(?,?,?,?)`, user, id, u.String(), time.Now().Unix())
	writeJSON(w, map[string]string{"id": id})
}

// GET /api/clips → eigene Clips, neueste zuerst
func listClips(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query(`SELECT id, url, title, created FROM clips WHERE user_id=? ORDER BY created DESC`, uid(r))
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	list := []map[string]any{}
	for rows.Next() {
		var id, u, title string
		var created int64
		rows.Scan(&id, &u, &title, &created)
		list = append(list, map[string]any{"id": id, "url": u, "title": title, "created": created})
	}
	writeJSON(w, list)
}

// GET /api/clips/{id} → Tonspur (nur die eigene)
func getClip(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var n int
	db.QueryRow(`SELECT count(*) FROM clips WHERE user_id=? AND id=?`, uid(r), id).Scan(&n)
	if n == 0 || strings.ContainsAny(id, "/.") {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "audio/mp4")
	http.ServeFile(w, r, filepath.Join(clipDir(uid(r)), id+".m4a"))
}

// PUT /api/clips/{id} {title} → eigener Titel (leer = keiner)
func renameClip(w http.ResponseWriter, r *http.Request) {
	var req struct{ Title string }
	if !readJSON(w, r, &req) {
		return
	}
	db.Exec(`UPDATE clips SET title=? WHERE user_id=? AND id=?`, truncate(strings.TrimSpace(req.Title), 100), uid(r), r.PathValue("id"))
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /api/clips/{id}
func deleteClip(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if strings.ContainsAny(id, "/.") {
		http.NotFound(w, r)
		return
	}
	db.Exec(`DELETE FROM clips WHERE user_id=? AND id=?`, uid(r), id)
	os.Remove(filepath.Join(clipDir(uid(r)), id+".m4a"))
	w.WriteHeader(http.StatusNoContent)
}
