package main

import (
	"embed"
	"encoding/base64"
	"encoding/json"
	"html/template"
	"net/http"
	"net/url"
	"strconv"
	"time"

	qrcode "github.com/skip2/go-qrcode"
)

// Entry ist ein Datensatz eines Moduls. Data enthält die Modulfelder als JSON.
type Entry struct {
	ID      string          `json:"id"`
	Module  string          `json:"module"`
	Date    string          `json:"date"` // JJJJ-MM-TT
	Data    json.RawMessage `json:"data"`
	Updated int64           `json:"updated"` // Änderungszeit in ms (vom Gerät), neuere gewinnt
	Deleted bool            `json:"deleted,omitempty"`
	Rev     int64           `json:"rev,omitempty"` // vom Server vergeben, für den Abgleich
}

func routes() http.Handler {
	m := http.NewServeMux()
	m.HandleFunc("GET /{$}", page)
	m.HandleFunc("GET /api/status", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"name": "koerperkompass", "version": version, "ai": aiEnabled()})
	})
	m.HandleFunc("GET /api/modules", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, modules) })
	m.HandleFunc("POST /api/pair", pairHandler)
	m.HandleFunc("POST /api/invite", auth(invite))
	m.HandleFunc("GET /api/profile", auth(getProfile))
	m.HandleFunc("PUT /api/profile", auth(putProfile))
	m.HandleFunc("GET /api/entries", auth(listEntries))
	m.HandleFunc("POST /api/entries", auth(putEntries))
	m.HandleFunc("GET /api/export", auth(export))
	m.HandleFunc("POST /api/import", auth(importData))
	m.HandleFunc("POST /api/ai/photo", auth(aiPhoto))
	m.HandleFunc("POST /api/ai/analysis", auth(aiAnalysis))
	return http.MaxBytesHandler(m, 20<<20)
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		http.Error(w, "ungültiges JSON: "+err.Error(), http.StatusBadRequest)
		return false
	}
	return true
}

func pairHandler(w http.ResponseWriter, r *http.Request) {
	var req struct{ Code, Name, Device string }
	if !readJSON(w, r, &req) {
		return
	}
	token, userID, err := pair(req.Code, req.Name, req.Device)
	if err != nil {
		time.Sleep(time.Second) // bremst Rateversuche
		http.Error(w, "Kopplungscode ungültig oder abgelaufen", http.StatusForbidden)
		return
	}
	writeJSON(w, map[string]any{"token": token, "userId": userID})
}

// invite erzeugt einen Code für ein weiteres Gerät („sameUser“) oder ein neues Familienmitglied.
func invite(w http.ResponseWriter, r *http.Request) {
	var req struct{ SameUser bool }
	json.NewDecoder(r.Body).Decode(&req)
	var id int64
	if req.SameUser {
		id = uid(r)
	}
	code, err := newCode(id)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, map[string]string{"code": code})
}

func getProfile(w http.ResponseWriter, r *http.Request) {
	var p string
	db.QueryRow(`SELECT profile FROM users WHERE id=?`, uid(r)).Scan(&p)
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(p))
}

func putProfile(w http.ResponseWriter, r *http.Request) {
	var p json.RawMessage
	if !readJSON(w, r, &p) {
		return
	}
	db.Exec(`UPDATE users SET profile=? WHERE id=?`, string(p), uid(r))
	w.WriteHeader(http.StatusNoContent)
}

// listEntries liefert alle Einträge mit rev > since (inkl. gelöschter, damit Geräte sie entfernen).
func listEntries(w http.ResponseWriter, r *http.Request) {
	since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
	es, err := queryEntries(`user_id=? AND rev>?`, uid(r), since)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, es)
}

func queryEntries(where string, args ...any) ([]Entry, error) {
	rows, err := db.Query(`SELECT id, module, date, data, updated, deleted, rev FROM entries WHERE `+where+` ORDER BY rev`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	es := []Entry{}
	for rows.Next() {
		var e Entry
		var data string
		rows.Scan(&e.ID, &e.Module, &e.Date, &data, &e.Updated, &e.Deleted, &e.Rev)
		e.Data = json.RawMessage(data)
		es = append(es, e)
	}
	return es, rows.Err()
}

// saveEntries schreibt Einträge; ältere Stände überschreiben keine neueren.
func saveEntries(userID int64, es []Entry) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for i, e := range es {
		if e.ID == "" || e.Module == "" {
			continue
		}
		if len(e.Data) == 0 {
			e.Data = json.RawMessage("{}")
		}
		_, err := tx.Exec(`INSERT INTO entries(user_id, id, module, date, data, updated, deleted, rev) VALUES(?,?,?,?,?,?,?,?)
			ON CONFLICT(user_id, id) DO UPDATE SET module=excluded.module, date=excluded.date, data=excluded.data,
			updated=excluded.updated, deleted=excluded.deleted, rev=excluded.rev WHERE excluded.updated >= entries.updated`,
			userID, e.ID, e.Module, e.Date, string(e.Data), e.Updated, e.Deleted, time.Now().UnixNano()+int64(i))
		if err != nil {
			return err
		}
	}
	return tx.Commit()
}

func putEntries(w http.ResponseWriter, r *http.Request) {
	var es []Entry
	if !readJSON(w, r, &es) {
		return
	}
	if err := saveEntries(uid(r), es); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Export/Import: komplettes Profil und alle Einträge eines Nutzers als JSON.
type backup struct {
	Version  int             `json:"version"`
	Exported string          `json:"exported,omitempty"`
	Profile  json.RawMessage `json:"profile"`
	Entries  []Entry         `json:"entries"`
}

func export(w http.ResponseWriter, r *http.Request) {
	b := backup{Version: 1, Exported: time.Now().UTC().Format(time.RFC3339)}
	var p string
	db.QueryRow(`SELECT profile FROM users WHERE id=?`, uid(r)).Scan(&p)
	b.Profile = json.RawMessage(p)
	b.Entries, _ = queryEntries(`user_id=? AND deleted=0`, uid(r))
	w.Header().Set("Content-Disposition", `attachment; filename="koerperkompass-export.json"`)
	writeJSON(w, b)
}

func importData(w http.ResponseWriter, r *http.Request) {
	var b backup
	if !readJSON(w, r, &b) {
		return
	}
	if len(b.Profile) > 0 && string(b.Profile) != "null" {
		db.Exec(`UPDATE users SET profile=? WHERE id=?`, string(b.Profile), uid(r))
	}
	if err := saveEntries(uid(r), b.Entries); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, map[string]int{"imported": len(b.Entries)})
}

//go:embed index.html
var files embed.FS
var tmpl = template.Must(template.ParseFS(files, "index.html"))

// page zeigt die kleine Weboberfläche; den QR-Code nur, solange noch niemand gekoppelt ist.
func page(w http.ResponseWriter, r *http.Request) {
	data := map[string]any{"Version": version, "AI": aiEnabled()}
	if code := firstStartCode(); code != "" {
		base := env("KK_PUBLIC_URL", "")
		if base == "" {
			scheme := "http"
			if r.TLS != nil || r.Header.Get("X-Forwarded-Proto") == "https" {
				scheme = "https"
			}
			base = scheme + "://" + r.Host
		}
		link := "koerperkompass://pair?server=" + url.QueryEscape(base) + "&code=" + code
		png, _ := qrcode.Encode(link, qrcode.Medium, 320)
		data["Code"], data["Server"] = code, base
		data["QR"] = template.URL("data:image/png;base64," + base64.StdEncoding.EncodeToString(png))
	}
	tmpl.Execute(w, data)
}
