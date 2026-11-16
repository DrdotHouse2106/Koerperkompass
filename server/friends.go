package main

// Freundschaften – auch zwischen verschiedenen Körperkompass-Servern (dezentral, ohne zentralen Dienst).
//
// Ablauf: Nutzer A erzeugt einen Freundschaftslink (<KK_PUBLIC_URL>/f/<code>). Nutzer B fügt ihn in seiner App ein;
// Bs Server meldet sich bei As Server (POST /api/fed/accept) und beide speichern einen gemeinsamen Schlüssel.
// Danach holt jeder Server die Spielerkarte des Freundes direkt beim anderen Server ab (GET /api/fed/card).
// Geteilt wird nur die Spielerkarte, die die App selbst hochlädt (Name, Level, Rang, Serie, Wochenwerte) –
// niemals Gesundheitsdaten. Liegen beide Nutzer auf demselben Server, läuft alles intern.

import (
	"bytes"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"time"
)

const friendSchema = `
CREATE TABLE IF NOT EXISTS friends (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  url TEXT NOT NULL, pub TEXT NOT NULL, secret TEXT NOT NULL, card TEXT NOT NULL DEFAULT '{}', created INTEGER NOT NULL,
  UNIQUE(user_id, url, pub));
CREATE TABLE IF NOT EXISTS friendlinks (code TEXT PRIMARY KEY, user_id INTEGER NOT NULL, expires INTEGER NOT NULL);`

// migrateFriends ergänzt die Tabellen und gibt jedem Nutzer eine öffentliche, zufällige Kennung.
func migrateFriends() error {
	db.Exec(`ALTER TABLE users ADD COLUMN pub TEXT NOT NULL DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN card TEXT NOT NULL DEFAULT '{}'`)
	db.Exec(`UPDATE users SET pub = lower(hex(randomblob(12))) WHERE pub = ''`)
	_, err := db.Exec(friendSchema)
	return err
}

func randomHex(n int) string {
	b := make([]byte, n)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// selfURL ist die öffentliche Adresse dieses Servers (nötig für Freundschaften).
func selfURL() string { return strings.TrimRight(env("KK_PUBLIC_URL", ""), "/") }

var handler http.Handler // für interne Aufrufe an sich selbst (gleicher Server)

var fedClient = &http.Client{Timeout: 6 * time.Second,
	CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}

// fedCall ruft einen Föderations-Endpunkt auf einem (anderen oder diesem) Server auf.
func fedCall(base, method, path string, body any, secret string) ([]byte, error) {
	if base != selfURL() && !strings.HasPrefix(base, "https://") && env("KK_FED_HTTP", "") == "" {
		return nil, errors.New("nur HTTPS-Server können befreundet werden")
	}
	var buf io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		buf = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, base+path, buf)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-KK-Secret", secret)
	if base == selfURL() {
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code >= 300 {
			return nil, errors.New(strings.TrimSpace(rec.Body.String()))
		}
		return rec.Body.Bytes(), nil
	}
	resp, err := fedClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return nil, errors.New(strings.TrimSpace(string(data)))
	}
	return data, nil
}

func userPub(id int64) (pub string) {
	db.Exec(`UPDATE users SET pub = lower(hex(randomblob(12))) WHERE id=? AND pub = ''`, id) // neue Nutzer
	db.QueryRow(`SELECT pub FROM users WHERE id=?`, id).Scan(&pub)
	return
}

// --- Endpunkte für die eigene App ---

// putCard speichert die Spielerkarte, die Freunde sehen dürfen.
func putCard(w http.ResponseWriter, r *http.Request) {
	var card map[string]any
	if !readJSON(w, r, &card) {
		return
	}
	b, _ := json.Marshal(card)
	db.Exec(`UPDATE users SET card=? WHERE id=?`, string(b), uid(r))
	w.WriteHeader(http.StatusNoContent)
}

func friendLink(w http.ResponseWriter, r *http.Request) {
	if selfURL() == "" {
		http.Error(w, "Auf dem Server ist KK_PUBLIC_URL nicht gesetzt – nötig für Freundschaften", http.StatusNotImplemented)
		return
	}
	code := randomHex(10)
	db.Exec(`INSERT INTO friendlinks(code, user_id, expires) VALUES(?,?,?)`, code, uid(r), time.Now().Add(7*24*time.Hour).Unix())
	writeJSON(w, map[string]string{"link": selfURL() + "/f/" + code})
}

// addFriend löst den Freundschaftslink eines anderen Nutzers ein (auf diesem oder einem anderen Server).
func addFriend(w http.ResponseWriter, r *http.Request) {
	var req struct{ Link string }
	if !readJSON(w, r, &req) {
		return
	}
	if selfURL() == "" {
		http.Error(w, "Auf dem Server ist KK_PUBLIC_URL nicht gesetzt – nötig für Freundschaften", http.StatusNotImplemented)
		return
	}
	i := strings.LastIndex(req.Link, "/f/")
	if i < 0 {
		http.Error(w, "Kein Freundschaftslink", http.StatusBadRequest)
		return
	}
	base, code := strings.TrimRight(strings.TrimSpace(req.Link[:i]), "/"), strings.TrimSpace(req.Link[i+3:])
	if u, err := url.Parse(base); err != nil || u.Host == "" {
		http.Error(w, "Kein Freundschaftslink", http.StatusBadRequest)
		return
	}
	secret := randomHex(24)
	data, err := fedCall(base, "POST", "/api/fed/accept", map[string]string{"code": code, "url": selfURL(), "pub": userPub(uid(r)), "secret": secret}, "")
	if err != nil {
		http.Error(w, "Der andere Server hat abgelehnt: "+err.Error(), http.StatusBadGateway)
		return
	}
	var res struct{ Pub string }
	json.Unmarshal(data, &res)
	if _, err := db.Exec(`INSERT OR REPLACE INTO friends(user_id, url, pub, secret, created) VALUES(?,?,?,?,?)`, uid(r), base, res.Pub, secret, time.Now().Unix()); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type friend struct {
	ID     int64           `json:"id"`
	URL    string          `json:"url"`
	Card   json.RawMessage `json:"card"`
	Online bool            `json:"online"`
	pub    string
	secret string
}

// listFriends holt die aktuellen Karten aller Freunde (parallel); bei Fehlern wird die letzte bekannte gezeigt.
func listFriends(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query(`SELECT id, url, pub, secret, card FROM friends WHERE user_id=? ORDER BY created`, uid(r))
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	fs := []*friend{}
	for rows.Next() {
		f := &friend{}
		var card string
		rows.Scan(&f.ID, &f.URL, &f.pub, &f.secret, &card)
		f.Card = json.RawMessage(card)
		fs = append(fs, f)
	}
	rows.Close()
	me := userPub(uid(r))
	var wg sync.WaitGroup
	for _, f := range fs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			q := url.Values{"pub": {f.pub}, "from": {me}, "url": {selfURL()}}
			if data, err := fedCall(f.URL, "GET", "/api/fed/card?"+q.Encode(), nil, f.secret); err == nil && json.Valid(data) {
				f.Card, f.Online = data, true
			}
		}()
	}
	wg.Wait()
	for _, f := range fs {
		if f.Online {
			db.Exec(`UPDATE friends SET card=? WHERE id=?`, string(f.Card), f.ID)
		}
	}
	writeJSON(w, fs)
}

// removeFriend beendet eine Freundschaft auf beiden Seiten.
func removeFriend(w http.ResponseWriter, r *http.Request) {
	var f friend
	if db.QueryRow(`SELECT url, pub, secret FROM friends WHERE id=? AND user_id=?`, r.PathValue("id"), uid(r)).Scan(&f.URL, &f.pub, &f.secret) == nil {
		fedCall(f.URL, "POST", "/api/fed/remove", map[string]string{"pub": f.pub, "from": userPub(uid(r)), "url": selfURL()}, f.secret)
	}
	db.Exec(`DELETE FROM friends WHERE id=? AND user_id=?`, r.PathValue("id"), uid(r))
	w.WriteHeader(http.StatusNoContent)
}

// --- Endpunkte für andere Server (Föderation) ---

func fedAccept(w http.ResponseWriter, r *http.Request) {
	var req struct{ Code, URL, Pub, Secret string }
	if !readJSON(w, r, &req) {
		return
	}
	var owner int64
	if len(req.Secret) < 32 || req.Pub == "" || db.QueryRow(`DELETE FROM friendlinks WHERE code=? AND expires>? RETURNING user_id`, req.Code, time.Now().Unix()).Scan(&owner) != nil {
		time.Sleep(time.Second)
		http.Error(w, "Freundschaftslink ungültig oder abgelaufen", http.StatusForbidden)
		return
	}
	pub := userPub(owner)
	if req.URL == selfURL() && req.Pub == pub {
		http.Error(w, "Das ist dein eigener Link", http.StatusBadRequest)
		return
	}
	db.Exec(`INSERT OR REPLACE INTO friends(user_id, url, pub, secret, created) VALUES(?,?,?,?,?)`, owner, req.URL, req.Pub, req.Secret, time.Now().Unix())
	writeJSON(w, map[string]string{"pub": pub})
}

// fedFriend prüft, ob die Anfrage von einem echten Freund des Nutzers <pub> kommt.
func fedFriend(r *http.Request, pub, from, fromURL string) (userID int64, ok bool) {
	var secret string
	err := db.QueryRow(`SELECT f.user_id, f.secret FROM friends f JOIN users u ON u.id=f.user_id WHERE u.pub=? AND f.pub=? AND f.url=?`,
		pub, from, fromURL).Scan(&userID, &secret)
	return userID, err == nil && subtle.ConstantTimeCompare([]byte(secret), []byte(r.Header.Get("X-KK-Secret"))) == 1
}

// fedCard liefert die Spielerkarte – und, falls freigegeben, die Freunde, die selbst sichtbar sein wollen.
func fedCard(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	userID, ok := fedFriend(r, q.Get("pub"), q.Get("from"), q.Get("url"))
	if !ok {
		http.Error(w, "keine Freundschaft", http.StatusForbidden)
		return
	}
	var raw string
	db.QueryRow(`SELECT card FROM users WHERE id=?`, userID).Scan(&raw)
	card := map[string]any{}
	json.Unmarshal([]byte(raw), &card)
	delete(card, "friends")
	if card["showFriends"] == true {
		type row struct{ u, p, c string }
		var all []row
		rows, _ := db.Query(`SELECT url, pub, card FROM friends WHERE user_id=?`, userID)
		for rows != nil && rows.Next() {
			var x row
			rows.Scan(&x.u, &x.p, &x.c)
			all = append(all, x)
		}
		if rows != nil {
			rows.Close() // erst schließen: der Server hat nur eine Datenbankverbindung
		}
		list := []map[string]any{}
		for _, x := range all {
			if x.u == selfURL() { // Freund auf diesem Server: aktuelle Karte direkt lesen
				db.QueryRow(`SELECT card FROM users WHERE pub=?`, x.p).Scan(&x.c)
			}
			fc := map[string]any{}
			json.Unmarshal([]byte(x.c), &fc)
			// nur Freunde, die selbst zugestimmt haben – und nicht der Anfragende selbst
			if fc["visible"] != true || (x.p == q.Get("from") && x.u == q.Get("url")) {
				continue
			}
			host := x.u
			if pu, err := url.Parse(x.u); err == nil {
				host = pu.Host
			}
			list = append(list, map[string]any{"name": fc["name"], "level": fc["level"], "rank": fc["rank"], "streak": fc["streak"], "server": host})
		}
		card["friends"] = list
	}
	writeJSON(w, card)
}

func fedRemove(w http.ResponseWriter, r *http.Request) {
	var req struct{ Pub, From, URL string }
	if !readJSON(w, r, &req) {
		return
	}
	if userID, ok := fedFriend(r, req.Pub, req.From, req.URL); ok {
		db.Exec(`DELETE FROM friends WHERE user_id=? AND pub=? AND url=?`, userID, req.From, req.URL)
	}
	w.WriteHeader(http.StatusNoContent)
}

// friendPage: wer den Link im Browser öffnet, bekommt einen Hinweis.
func friendPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	io.WriteString(w, "Körperkompass-Freundschaftslink\n\nÖffne die Körperkompass-App → Abenteuer → Freunde und füge diesen Link dort ein.\n")
}
