package main

import (
	"bytes"
	"embed"
	"encoding/base64"
	"encoding/json"
	"html/template"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
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
		writeJSON(w, map[string]any{"name": "koerperkompass", "version": version, "ai": aiEnabled(), "tts": env("KK_TTS_URL", "") != "", "reelkoch": reelkochEnabled(), "recipeLinks": true})
	})
	m.HandleFunc("GET /api/modules", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, modules) })
	m.HandleFunc("POST /api/pair", pairHandler)
	m.HandleFunc("POST /api/invite", auth(invite))
	m.HandleFunc("GET /api/me", auth(me))
	m.HandleFunc("DELETE /api/devices/{id}", auth(deleteDevice))
	m.HandleFunc("GET /api/profile", auth(getProfile))
	// Ende-zu-Ende-Verschlüsselung: der Server bewahrt nur den mit Passwort bzw. Wiederherstellungsschlüssel
	// verschlüsselten Datenschlüssel auf (nie Passwort oder Schlüssel im Klartext)
	m.HandleFunc("GET /api/vault", auth(getVault))
	m.HandleFunc("PUT /api/vault", auth(putVault))
	m.HandleFunc("PUT /api/profile", auth(putProfile))
	m.HandleFunc("GET /api/entries", auth(listEntries))
	m.HandleFunc("POST /api/entries", auth(putEntries))
	m.HandleFunc("POST /api/log", auth(postAppLog)) // Testphase, siehe applog.go
	m.HandleFunc("GET /api/log", auth(getAppLog))
	m.HandleFunc("POST /api/debug/dump", auth(postDebugDump)) // Testphase: lesbare Kopie auf Wunsch, siehe applog.go
	m.HandleFunc("DELETE /api/debug/dump", auth(deleteDebugDump))
	// Claude-Connector (MCP + OAuth), siehe mcp.go
	m.HandleFunc("POST /mcp", mcpHandler)
	m.HandleFunc("GET /.well-known/oauth-protected-resource", oauthResource)
	m.HandleFunc("GET /.well-known/oauth-protected-resource/mcp", oauthResource)
	m.HandleFunc("GET /.well-known/oauth-authorization-server", oauthMetadata)
	m.HandleFunc("POST /oauth/register", oauthRegister)
	m.HandleFunc("GET /oauth/authorize", oauthAuthorize)
	m.HandleFunc("GET /oauth/wait", oauthWait)
	m.HandleFunc("POST /oauth/token", oauthToken)
	m.HandleFunc("POST /api/claude/approve", auth(claudeApprove))
	m.HandleFunc("PUT /api/claude/share", auth(claudeShare))
	m.HandleFunc("DELETE /api/claude/share", auth(claudeUnshare))
	m.HandleFunc("GET /api/claude/inbox", auth(claudeInbox))
	m.HandleFunc("DELETE /api/claude/inbox/{id}", auth(claudeInboxDone))
	m.HandleFunc("GET /api/usage", auth(getUsage))     // KI-Verbrauch, siehe usage.go
	m.HandleFunc("DELETE /api/data", auth(deleteData)) // „Nur auf dem iPhone“: gespeicherte Daten löschen
	m.HandleFunc("GET /api/export", auth(export))
	m.HandleFunc("POST /api/import", auth(importData))
	m.HandleFunc("POST /api/ai/photo", auth(aiPhoto))
	m.HandleFunc("POST /api/ai/analysis", auth(aiAnalysis))
	m.HandleFunc("POST /api/ai/plan", auth(aiPlan))
	m.HandleFunc("POST /api/ai/next", auth(aiNext))
	m.HandleFunc("POST /api/ai/coach", auth(aiCoach))
	m.HandleFunc("POST /api/ai/motivation", auth(aiMotivation))
	m.HandleFunc("POST /api/ai/monolog", auth(aiMonolog))
	m.HandleFunc("POST /api/ai/voice", auth(aiVoice))
	m.HandleFunc("POST /api/ai/meal", auth(aiMeal))
	m.HandleFunc("POST /api/ai/recipe", auth(aiRecipe))
	// Übungsbibliothek (free-exercise-db), siehe exercises.go
	m.HandleFunc("GET /api/exercises", auth(listExercises))
	m.HandleFunc("GET /api/exercises/{id}", auth(getExercise))
	m.HandleFunc("GET /api/exercises/img/{path...}", exerciseImage)
	// Rezepte aus Reels über Reelkoch, siehe module_recipes.go
	m.HandleFunc("POST /api/recipes/link", auth(recipeLink)) // erkennt Video/Reel oder Rezeptseite
	m.HandleFunc("POST /api/recipes/reel", auth(recipeReel))
	m.HandleFunc("GET /api/recipes/reel/{id}", auth(recipeReelStatus))
	m.HandleFunc("GET /api/recipes/reelkoch", auth(recipeReelList))
	// Freundschaften (auch zwischen Servern), siehe friends.go
	m.HandleFunc("PUT /api/card", auth(putCard))
	m.HandleFunc("POST /api/friends/link", auth(friendLink))
	m.HandleFunc("POST /api/friends", auth(addFriend))
	m.HandleFunc("GET /api/friends", auth(listFriends))
	m.HandleFunc("DELETE /api/friends/{id}", auth(removeFriend))
	m.HandleFunc("POST /api/fed/accept", fedAccept)
	m.HandleFunc("GET /api/fed/card", fedCard)
	m.HandleFunc("POST /api/fed/remove", fedRemove)
	m.HandleFunc("GET /f/{code}", friendPage)
	// Anonyme Verbesserungsdaten (freiwillig), siehe telemetry.go
	m.HandleFunc("POST /api/tts", auth(tts)) // Sprachausgabe vom eigenen Server, siehe tts.go
	m.HandleFunc("POST /api/tts/wake", auth(ttsWake))
	m.HandleFunc("POST /api/telemetry", auth(telemetry))
	m.HandleFunc("POST /api/collect", collect)
	m.HandleFunc("GET /api/collect", collectExport)
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
	var req struct {
		SameUser bool
		Name     string
	}
	json.NewDecoder(r.Body).Decode(&req)
	var id int64
	if req.SameUser {
		id = uid(r)
	}
	code, err := newCode(id, req.Name)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, map[string]string{"code": code})
}

// me liefert Namen und gekoppelte Geräte des eigenen Kontos.
func me(w http.ResponseWriter, r *http.Request) {
	var name string
	db.QueryRow(`SELECT name FROM users WHERE id=?`, uid(r)).Scan(&name)
	current := hashToken(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	rows, err := db.Query(`SELECT rowid, device, created, hash FROM tokens WHERE user_id=? ORDER BY created`, uid(r))
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()
	devices := []map[string]any{}
	for rows.Next() {
		var id, created int64
		var device, hash string
		rows.Scan(&id, &device, &created, &hash)
		devices = append(devices, map[string]any{"id": id, "device": device, "created": created, "current": hash == current})
	}
	writeJSON(w, map[string]any{"name": name, "devices": devices})
}

// deleteDevice entzieht einem eigenen Gerät den Zugang.
func deleteDevice(w http.ResponseWriter, r *http.Request) {
	db.Exec(`DELETE FROM tokens WHERE rowid=? AND user_id=?`, r.PathValue("id"), uid(r))
	w.WriteHeader(http.StatusNoContent)
}

func getProfile(w http.ResponseWriter, r *http.Request) {
	var p string
	db.QueryRow(`SELECT profile FROM users WHERE id=?`, uid(r)).Scan(&p)
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(p))
}

// Nur verschlüsselte Inhalte annehmen: Einträge als "enc:v1:…", Profil als {"enc": …} (siehe Vault.swift).
// So liegen auf dem Server nie Gesundheitsdaten im Klartext.
var errPlain = "Nur verschlüsselte Daten erlaubt – bitte die App aktualisieren"

func sealedEntry(d json.RawMessage) bool {
	return bytes.HasPrefix(bytes.TrimSpace(d), []byte(`"enc:v1:`))
}

func sealedProfile(p json.RawMessage) bool {
	var m map[string]json.RawMessage
	return json.Unmarshal(p, &m) == nil && (len(m) == 0 || (len(m) == 1 && m["enc"] != nil))
}

func putProfile(w http.ResponseWriter, r *http.Request) {
	var p json.RawMessage
	if !readJSON(w, r, &p) {
		return
	}
	if !sealedProfile(p) {
		http.Error(w, errPlain, http.StatusUnprocessableEntity)
		return
	}
	db.Exec(`UPDATE users SET profile=? WHERE id=?`, string(p), uid(r))
	w.WriteHeader(http.StatusNoContent)
}

// deleteData löscht alle gespeicherten Daten des Nutzers (Einträge, Profil, Spielerkarte, Protokoll).
// Konto, Geräte und Freundschaften bleiben – die App nutzt den Server danach nur noch als Durchgang (Claude, Stimme).
func deleteData(w http.ResponseWriter, r *http.Request) {
	u := uid(r)
	for _, q := range []string{`DELETE FROM entries WHERE user_id=?`, `DELETE FROM applog WHERE user_id=?`, `DELETE FROM debug_dump WHERE user_id=?`, `UPDATE users SET profile='{}', card='{}' WHERE id=?`} {
		if _, err := db.Exec(q, u); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	}
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
	for _, e := range es {
		if !sealedEntry(e.Data) {
			http.Error(w, errPlain, http.StatusUnprocessableEntity)
			return
		}
	}
	if err := saveEntries(uid(r), es); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func getVault(w http.ResponseWriter, r *http.Request) {
	var v string
	db.QueryRow(`SELECT vault FROM users WHERE id=?`, uid(r)).Scan(&v)
	if v == "" {
		v = "{}"
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(v))
}

func putVault(w http.ResponseWriter, r *http.Request) {
	var v json.RawMessage
	if !readJSON(w, r, &v) {
		return
	}
	db.Exec(`UPDATE users SET vault=? WHERE id=?`, string(v), uid(r))
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
	for _, e := range b.Entries {
		if !sealedEntry(e.Data) {
			http.Error(w, errPlain, http.StatusUnprocessableEntity)
			return
		}
	}
	if len(b.Profile) > 0 && string(b.Profile) != "null" && sealedProfile(b.Profile) {
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

// isLocal: Aufruf direkt aus dem Heimnetz – nicht über den Reverse Proxy und nicht über die öffentliche Adresse.
// Nur dann zeigt die Weboberfläche den Kopplungscode, damit ihn niemand aus dem Internet abgreifen kann.
func isLocal(r *http.Request) bool {
	for _, h := range []string{"X-Forwarded-For", "X-Real-Ip", "Forwarded", "X-Forwarded-Proto", "X-Forwarded-Host"} {
		if r.Header.Get(h) != "" {
			return false
		}
	}
	if pub, err := url.Parse(selfURL()); err == nil && pub.Host != "" && strings.EqualFold(pub.Hostname(), hostOnly(r.Host)) {
		return false
	}
	ip := net.ParseIP(hostOnly(r.RemoteAddr))
	return ip != nil && (ip.IsLoopback() || ip.IsPrivate())
}

func hostOnly(hostport string) string {
	if h, _, err := net.SplitHostPort(hostport); err == nil {
		return h
	}
	return hostport
}

// page zeigt die kleine Weboberfläche; den QR-Code nur im Heimnetz und nur, solange noch niemand gekoppelt ist.
func page(w http.ResponseWriter, r *http.Request) {
	data := map[string]any{"Version": version, "AI": aiEnabled(), "Local": isLocal(r)}
	if code := firstStartCode(); code != "" && isLocal(r) {
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
