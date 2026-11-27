package main

// Claude-Connector (MCP): Nutzer verbinden Körperkompass in der Claude-App bzw. auf claude.ai als „benutzerdefinierten
// Connector“ (Adresse <KK_PUBLIC_URL>/mcp) und sprechen dort – über ihr eigenes Claude-Abo – mit ihren Daten.
//
// Verschlüsselung ohne Klartext auf der Festplatte:
//   - Beim Verbinden erzeugt die App einen Freigabe-Schlüssel K und lädt eine mit K verschlüsselte Kurzfassung hoch
//     (bei jedem Abgleich neu). Der Server speichert K nicht.
//   - K steckt im Zugangstoken, das nur Claude bekommt ("kkc_<id>.<K>"); der Server kennt davon nur einen Prüfwert.
//   - Nur während einer Claude-Anfrage entschlüsselt der Server die Kurzfassung im Arbeitsspeicher.
//   - Einträge von Claude legt der Server mit K verschlüsselt in einen Eingangskorb; die App holt sie ab und trägt ein.
//
// Anmeldung nach MCP-Vorgabe: OAuth 2.1 mit PKCE und dynamischer Client-Registrierung. Bestätigt wird in der App.

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"html/template"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

func migrateMCP() {
	db.Exec(`CREATE TABLE IF NOT EXISTS oauth_clients (id TEXT PRIMARY KEY, redirects TEXT NOT NULL, created INTEGER NOT NULL)`)
	db.Exec(`CREATE TABLE IF NOT EXISTS claude_share (user_id INTEGER PRIMARY KEY, blob TEXT NOT NULL DEFAULT '', updated INTEGER NOT NULL)`)
	db.Exec(`CREATE TABLE IF NOT EXISTS claude_tokens (id TEXT PRIMARY KEY, user_id INTEGER NOT NULL, hash TEXT NOT NULL, created INTEGER NOT NULL)`)
	db.Exec(`CREATE TABLE IF NOT EXISTS claude_inbox (id TEXT PRIMARY KEY, user_id INTEGER NOT NULL, blob TEXT NOT NULL, created INTEGER NOT NULL)`)
}

func randHex(n int) string { b := make([]byte, n); rand.Read(b); return hex.EncodeToString(b) }

// AES-GCM im Format von CryptoKit („combined“: Nonce | Daten | Tag), Base64
func sealK(key, plain []byte) string {
	block, _ := aes.NewCipher(key)
	gcm, _ := cipher.NewGCM(block)
	nonce := make([]byte, 12)
	rand.Read(nonce)
	return base64.StdEncoding.EncodeToString(gcm.Seal(nonce, nonce, plain, nil))
}

func openK(key []byte, blob string) ([]byte, bool) {
	d, err := base64.StdEncoding.DecodeString(blob)
	if err != nil || len(d) < 28 || len(key) != 32 {
		return nil, false
	}
	block, _ := aes.NewCipher(key)
	gcm, _ := cipher.NewGCM(block)
	out, err := gcm.Open(nil, d[:12], d[12:], nil)
	return out, err == nil
}

// --- OAuth ---

type authReq struct {
	client, redirect, state, challenge string
	user                               int64
	key                                []byte // Freigabe-Schlüssel, nur bis zum Tausch gegen das Token im Speicher
	code                               string
	created                            time.Time
}

var (
	authMu   sync.Mutex
	authReqs = map[string]*authReq{} // Schlüssel: Code zum Bestätigen in der App
)

func pruneAuth() {
	for k, a := range authReqs {
		if time.Since(a.created) > 15*time.Minute {
			delete(authReqs, k)
		}
	}
}

func oauthResource(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]any{"resource": selfURL() + "/mcp", "authorization_servers": []string{selfURL()}})
}

func oauthMetadata(w http.ResponseWriter, r *http.Request) {
	b := selfURL()
	writeJSON(w, map[string]any{"issuer": b, "authorization_endpoint": b + "/oauth/authorize", "token_endpoint": b + "/oauth/token",
		"registration_endpoint": b + "/oauth/register", "response_types_supported": []string{"code"},
		"grant_types_supported": []string{"authorization_code"}, "code_challenge_methods_supported": []string{"S256"},
		"token_endpoint_auth_methods_supported": []string{"none"}})
}

// POST /oauth/register – dynamische Client-Registrierung (Claude meldet sich selbst an)
func oauthRegister(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RedirectURIs []string `json:"redirect_uris"`
	}
	if !readJSON(w, r, &req) || len(req.RedirectURIs) == 0 {
		return
	}
	id := randHex(16)
	b, _ := json.Marshal(req.RedirectURIs)
	db.Exec(`INSERT INTO oauth_clients(id, redirects, created) VALUES(?,?,?)`, id, string(b), time.Now().Unix())
	w.WriteHeader(http.StatusCreated)
	writeJSON(w, map[string]any{"client_id": id, "redirect_uris": req.RedirectURIs, "token_endpoint_auth_method": "none",
		"grant_types": []string{"authorization_code"}, "response_types": []string{"code"}})
}

var authPage = template.Must(template.New("a").Parse(`<!doctype html><html lang="de"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Körperkompass mit Claude verbinden</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#111;color:#eee;max-width:480px;margin:40px auto;padding:0 16px;line-height:1.5}
a.b{display:block;text-align:center;background:#ff8c33;color:#000;padding:14px;border-radius:12px;font-weight:700;text-decoration:none}
.code{font:700 34px ui-monospace,monospace;letter-spacing:4px;text-align:center;margin:16px 0}small{color:#999}</style>
<h2>Körperkompass mit Claude verbinden</h2>
<p>Bestätige die Freigabe in der Körperkompass-App. Dort wählst du auch, was Claude sehen darf.</p>
<p><a class="b" href="koerperkompass://claude-connect?req={{.}}">In Körperkompass öffnen</a></p>
<p>Oder in der App unter <b>Einstellungen → Claude-Connector</b> diesen Code eingeben:</p><div class="code">{{.}}</div>
<p id="s"><small>Warte auf Bestätigung …</small></p>
<script>setInterval(async()=>{const r=await fetch('/oauth/wait?req={{.}}');const j=await r.json();if(j.redirect)location=j.redirect},2000)</script>`))

// GET /oauth/authorize – zeigt die Seite mit dem Bestätigungscode
func oauthAuthorize(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	var redirects string
	db.QueryRow(`SELECT redirects FROM oauth_clients WHERE id=?`, q.Get("client_id")).Scan(&redirects)
	var list []string
	json.Unmarshal([]byte(redirects), &list)
	ok := false
	for _, u := range list {
		ok = ok || u == q.Get("redirect_uri")
	}
	if !ok || q.Get("response_type") != "code" || q.Get("code_challenge_method") != "S256" || q.Get("code_challenge") == "" {
		http.Error(w, "ungültige Anfrage", http.StatusBadRequest)
		return
	}
	code := strings.ToUpper(randHex(4)) // 8 Zeichen zum Abtippen
	authMu.Lock()
	pruneAuth()
	authReqs[code] = &authReq{client: q.Get("client_id"), redirect: q.Get("redirect_uri"), state: q.Get("state"),
		challenge: q.Get("code_challenge"), created: time.Now()}
	authMu.Unlock()
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	authPage.Execute(w, code)
}

// GET /oauth/wait?req=… – die Seite fragt, ob die App schon bestätigt hat
func oauthWait(w http.ResponseWriter, r *http.Request) {
	authMu.Lock()
	defer authMu.Unlock()
	a := authReqs[strings.ToUpper(r.URL.Query().Get("req"))]
	if a == nil || a.code == "" {
		writeJSON(w, map[string]any{})
		return
	}
	u, _ := url.Parse(a.redirect)
	v := u.Query()
	v.Set("code", a.code)
	if a.state != "" {
		v.Set("state", a.state)
	}
	u.RawQuery = v.Encode()
	writeJSON(w, map[string]any{"redirect": u.String()})
}

// POST /api/claude/approve {req, key, blob} – die App bestätigt (angemeldet) und liefert Schlüssel und Kurzfassung
func claudeApprove(w http.ResponseWriter, r *http.Request) {
	var req struct{ Req, Key, Blob string }
	if !readJSON(w, r, &req) {
		return
	}
	key, err := base64.StdEncoding.DecodeString(req.Key)
	if err != nil || len(key) != 32 {
		http.Error(w, "ungültiger Schlüssel", http.StatusBadRequest)
		return
	}
	authMu.Lock()
	a := authReqs[strings.ToUpper(strings.TrimSpace(req.Req))]
	if a == nil || a.code != "" {
		authMu.Unlock()
		http.Error(w, "Code unbekannt oder abgelaufen – in Claude neu verbinden", http.StatusNotFound)
		return
	}
	a.user, a.key, a.code = uid(r), key, randHex(16)
	authMu.Unlock()
	db.Exec(`INSERT INTO claude_share(user_id, blob, updated) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET blob=excluded.blob, updated=excluded.updated`,
		uid(r), req.Blob, time.Now().Unix())
	w.WriteHeader(http.StatusNoContent)
}

// POST /oauth/token – Code gegen Zugangstoken tauschen (PKCE)
func oauthToken(w http.ResponseWriter, r *http.Request) {
	r.ParseForm()
	authMu.Lock()
	var a *authReq
	for k, x := range authReqs {
		if x.code != "" && x.code == r.Form.Get("code") {
			a = x
			delete(authReqs, k)
		}
	}
	authMu.Unlock()
	sum := sha256.Sum256([]byte(r.Form.Get("code_verifier")))
	if a == nil || r.Form.Get("grant_type") != "authorization_code" || a.redirect != r.Form.Get("redirect_uri") ||
		base64.RawURLEncoding.EncodeToString(sum[:]) != a.challenge {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"invalid_grant"}`))
		return
	}
	id := randHex(16)
	token := "kkc_" + id + "." + base64.RawURLEncoding.EncodeToString(a.key)
	db.Exec(`INSERT INTO claude_tokens(id, user_id, hash, created) VALUES(?,?,?,?)`, id, a.user, hashToken(token), time.Now().Unix())
	writeJSON(w, map[string]any{"access_token": token, "token_type": "Bearer", "expires_in": 365 * 24 * 3600})
}

// --- Freigabe aus der App ---

// PUT /api/claude/share {blob} – neue verschlüsselte Kurzfassung (bei jedem Abgleich)
func claudeShare(w http.ResponseWriter, r *http.Request) {
	var req struct{ Blob string }
	if !readJSON(w, r, &req) {
		return
	}
	db.Exec(`UPDATE claude_share SET blob=?, updated=? WHERE user_id=?`, req.Blob, time.Now().Unix(), uid(r))
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /api/claude/share – Verbindung trennen: Kurzfassung, Tokens und Eingangskorb löschen
func claudeUnshare(w http.ResponseWriter, r *http.Request) {
	for _, q := range []string{`DELETE FROM claude_share WHERE user_id=?`, `DELETE FROM claude_tokens WHERE user_id=?`, `DELETE FROM claude_inbox WHERE user_id=?`} {
		db.Exec(q, uid(r))
	}
	w.WriteHeader(http.StatusNoContent)
}

// GET /api/claude/inbox – von Claude eingetragene Vorschläge (mit K verschlüsselt)
func claudeInbox(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query(`SELECT id, blob FROM claude_inbox WHERE user_id=? ORDER BY created`, uid(r))
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()
	list := []map[string]string{}
	for rows.Next() {
		var id, blob string
		rows.Scan(&id, &blob)
		list = append(list, map[string]string{"id": id, "blob": blob})
	}
	writeJSON(w, list)
}

func claudeInboxDone(w http.ResponseWriter, r *http.Request) {
	db.Exec(`DELETE FROM claude_inbox WHERE user_id=? AND id=?`, uid(r), r.PathValue("id"))
	w.WriteHeader(http.StatusNoContent)
}

// --- MCP ---

var mcpTools = []map[string]any{
	{"name": "koerperkompass_daten", "description": "Liest die freigegebenen Körperkompass-Daten der Person: heutige Werte (Essen, Trinken, " +
		"Aktivität, Schlaf, Gewicht, Training, Stimmung, Beschwerden), Ziele und den Verlauf der letzten Tage. Vor jeder Antwort zu Ernährung, " +
		"Training oder Gesundheit aufrufen. Keine ärztliche Beratung.",
		"inputSchema": map[string]any{"type": "object", "properties": map[string]any{}}},
	{"name": "koerperkompass_eintragen", "description": "Trägt Gegessenes, Getränke, Gewicht, Schlaf, Stimmung, Beschwerden oder einen Termin bzw. eine Erinnerung (z. B. Trainingszeit) in Körperkompass ein – " +
		"nur, was die Person tatsächlich zu sich genommen hat bzw. ausdrücklich eintragen möchte, nach kurzer Bestätigung. Die App übernimmt " +
		"es beim nächsten Öffnen. Nährwerte realistisch für deutsche Portionen schätzen.",
		"inputSchema": map[string]any{"type": "object", "properties": map[string]any{
			"day": map[string]any{"type": "integer", "description": "0 = heute, -1 = gestern"},
			"items": map[string]any{"type": "array", "items": map[string]any{"type": "object", "properties": map[string]any{
				"meal": map[string]any{"type": "string", "enum": []string{"breakfast", "lunch", "dinner", "snack"}},
				"name": map[string]any{"type": "string"}, "amount": map[string]any{"type": "string"}, "time": map[string]any{"type": "string", "description": "HH:MM"},
				"kcal": map[string]any{"type": "number"}, "protein": map[string]any{"type": "number"}, "carbs": map[string]any{"type": "number"},
				"fat": map[string]any{"type": "number"}, "ml": map[string]any{"type": "number", "description": "nur bei Getränken"},
				"caffeine": map[string]any{"type": "number", "description": "mg"}, "alcohol": map[string]any{"type": "number", "description": "g"},
			}}},
			"weight": map[string]any{"type": "number", "description": "kg"},
			"sleep": map[string]any{"type": "object", "description": "letzte Nacht", "properties": map[string]any{
				"quality": map[string]any{"type": "integer", "description": "1 sehr schlecht … 5 sehr gut"}, "hours": map[string]any{"type": "number"},
				"issues": map[string]any{"type": "array", "items": map[string]any{"type": "string", "enum": []string{"fallAsleep", "wokeUp", "early", "dreams", "pain", "noise", "stress", "late"}}}}},
			"event": map[string]any{"type": "object", "description": "Termin im Kalender (reminder false, z. B. Trainingszeit) oder Erinnerung (reminder true)",
				"properties": map[string]any{"title": map[string]any{"type": "string"}, "day": map[string]any{"type": "integer", "description": "0 = heute, 1 = morgen"},
					"time": map[string]any{"type": "string", "description": "HH:MM"}, "minutes": map[string]any{"type": "integer"}, "reminder": map[string]any{"type": "boolean"}}},
			"mood": map[string]any{"type": "object", "properties": map[string]any{"level": map[string]any{"type": "integer", "description": "1 sehr unangenehm … 7 sehr angenehm"}}},
			"symptoms": map[string]any{"type": "array", "items": map[string]any{"type": "object", "properties": map[string]any{
				"symptom": map[string]any{"type": "string", "enum": []string{"sinusCongestion", "runnyNose", "soreThroat", "coughing", "headache", "fever",
					"chills", "fatigue", "bodyAndMuscleAches", "lowerBackPain", "nausea", "diarrhea", "dizziness", "shortnessOfBreath", "lossOfSmell", "sleepChanges", "kneePain", "jointPain", "muscleSoreness", "other"}},
				"name":     map[string]any{"type": "string", "description": "nur bei other"},
				"severity": map[string]any{"type": "integer", "description": "1 leicht, 2 mittel, 3 stark"},
			}}},
		}}},
}

// claudeAuth prüft das Zugangstoken und liefert Nutzer und Freigabe-Schlüssel
func claudeAuth(r *http.Request) (int64, []byte, bool) {
	t := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	id, k, ok := strings.Cut(strings.TrimPrefix(t, "kkc_"), ".")
	key, err := base64.RawURLEncoding.DecodeString(k)
	var user int64
	var hash string
	if !ok || err != nil || db.QueryRow(`SELECT user_id, hash FROM claude_tokens WHERE id=?`, id).Scan(&user, &hash) != nil || hash != hashToken(t) {
		return 0, nil, false
	}
	return user, key, true
}

// POST /mcp – JSON-RPC (Streamable HTTP, Antworten als JSON)
func mcpHandler(w http.ResponseWriter, r *http.Request) {
	user, key, ok := claudeAuth(r)
	if !ok {
		w.Header().Set("WWW-Authenticate", `Bearer resource_metadata="`+selfURL()+`/.well-known/oauth-protected-resource"`)
		http.Error(w, "nicht verbunden", http.StatusUnauthorized)
		return
	}
	var req struct {
		ID     json.RawMessage `json:"id"`
		Method string          `json:"method"`
		Params struct {
			ProtocolVersion string          `json:"protocolVersion"`
			Name            string          `json:"name"`
			Arguments       json.RawMessage `json:"arguments"`
		} `json:"params"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	if req.ID == nil { // Benachrichtigung
		w.WriteHeader(http.StatusAccepted)
		return
	}
	text := func(s string, isErr bool) map[string]any {
		return map[string]any{"content": []map[string]string{{"type": "text", "text": s}}, "isError": isErr}
	}
	var result any = map[string]any{}
	switch req.Method {
	case "initialize":
		v := req.Params.ProtocolVersion
		if v == "" {
			v = "2025-06-18"
		}
		result = map[string]any{"protocolVersion": v, "capabilities": map[string]any{"tools": map[string]any{}},
			"serverInfo": map[string]string{"name": "koerperkompass", "version": version},
			"instructions": "Körperkompass ist die Gesundheits- und Fitness-App der Person. Lies zuerst koerperkompass_daten. Antworte auf Deutsch, " +
				"konkret und kurz. Keine Diagnosen, keine ärztliche Beratung."}
	case "tools/list":
		result = map[string]any{"tools": mcpTools}
	case "tools/call":
		switch req.Params.Name {
		case "koerperkompass_daten":
			var blob string
			db.QueryRow(`SELECT blob FROM claude_share WHERE user_id=?`, user).Scan(&blob)
			if plain, ok := openK(key, blob); ok {
				result = text(string(plain), false)
			} else {
				result = text("Keine Daten freigegeben – in der Körperkompass-App unter Einstellungen → Claude-Connector neu verbinden.", true)
			}
		case "koerperkompass_eintragen":
			if len(req.Params.Arguments) > 64<<10 {
				result = text("zu groß", true)
				break
			}
			db.Exec(`INSERT INTO claude_inbox(id, user_id, blob, created) VALUES(?,?,?,?)`, randHex(12), user, sealK(key, req.Params.Arguments), time.Now().Unix())
			result = text("Vorgemerkt – Körperkompass trägt es beim nächsten Öffnen der App ein.", false)
		default:
			result = text("unbekanntes Werkzeug", true)
		}
	}
	writeJSON(w, map[string]any{"jsonrpc": "2.0", "id": req.ID, "result": result})
}
