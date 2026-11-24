package main

// KI-Relais: zentraler Dienst, über den Körperkompass-Server ohne eigenen Claude-Schlüssel die KI nutzen.
// Spricht dieselbe Schnittstelle wie Anthropic (POST /v1/messages); ein Server braucht dafür nur
//   ANTHROPIC_BASE_URL=https://<relais>  und  ANTHROPIC_API_KEY=<Relais-Schlüssel>
// Das Relais prüft Schlüssel und Guthaben, leitet mit dem eigenen Claude-Schlüssel weiter, zählt die Tokens aus der
// Antwort und bucht die Kosten ab. Inhalte werden weder gespeichert noch protokolliert.
//
// Start:    koerperkompass relay
// Schlüssel: koerperkompass relay-key add <Name> <Euro> | topup <Name> <Euro> | list

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

func openRelayDB() {
	var err error
	db, err = sql.Open("sqlite", env("RELAY_DB", "data/relay.db")+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)")
	if err != nil {
		log.Fatal(err)
	}
	db.SetMaxOpenConns(1)
	// Beträge in Mikro-Euro (1 € = 1.000.000)
	db.Exec(`CREATE TABLE IF NOT EXISTS relay_keys (hash TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, balance INTEGER NOT NULL DEFAULT 0,
		used INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL)`)
	db.Exec(`CREATE TABLE IF NOT EXISTS relay_usage (name TEXT NOT NULL, day TEXT NOT NULL, model TEXT NOT NULL, calls INTEGER NOT NULL DEFAULT 0,
		input INTEGER NOT NULL DEFAULT 0, output INTEGER NOT NULL DEFAULT 0, micro INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (name, day, model))`)
}

func keyHash(k string) string { h := sha256.Sum256([]byte(k)); return hex.EncodeToString(h[:]) }

func euro(s string) int64 {
	f, err := strconv.ParseFloat(strings.ReplaceAll(s, ",", "."), 64)
	if err != nil {
		log.Fatal("Betrag in Euro angeben, z. B. 10 oder 2,50")
	}
	return int64(f * 1e6)
}

// relayKeyCmd verwaltet Relais-Schlüssel auf der Kommandozeile
func relayKeyCmd(args []string) {
	openRelayDB()
	switch {
	case len(args) == 3 && args[0] == "add":
		b := make([]byte, 24)
		rand.Read(b)
		k := "kkr_" + hex.EncodeToString(b)
		if _, err := db.Exec(`INSERT INTO relay_keys(hash, name, balance, created) VALUES(?,?,?,?)`, keyHash(k), args[1], euro(args[2]), time.Now().Unix()); err != nil {
			log.Fatal(err)
		}
		fmt.Printf("Schlüssel für %s (nur jetzt sichtbar):\n%s\n", args[1], k)
	case len(args) == 3 && args[0] == "topup":
		res, _ := db.Exec(`UPDATE relay_keys SET balance=balance+? WHERE name=?`, euro(args[2]), args[1])
		if n, _ := res.RowsAffected(); n == 0 {
			log.Fatal("unbekannter Name")
		}
		fmt.Println("aufgeladen")
	case len(args) == 2 && args[0] == "remove":
		db.Exec(`DELETE FROM relay_keys WHERE name=?`, args[1])
	case len(args) == 1 && args[0] == "list":
		rows, _ := db.Query(`SELECT name, balance, used FROM relay_keys ORDER BY name`)
		defer rows.Close()
		for rows.Next() {
			var n string
			var b, u int64
			rows.Scan(&n, &b, &u)
			fmt.Printf("%-24s Guthaben %8.2f €   verbraucht %8.2f €\n", n, float64(b)/1e6, float64(u)/1e6)
		}
	default:
		fmt.Println("relay-key add <Name> <Euro> | topup <Name> <Euro> | remove <Name> | list")
	}
}

func relayError(w http.ResponseWriter, code int, typ, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]any{"type": "error", "error": map[string]string{"type": typ, "message": msg}})
}

func relayKey(r *http.Request) string {
	if k := r.Header.Get("X-Api-Key"); k != "" {
		return k
	}
	return strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
}

// POST /v1/messages – nur nicht gestreamte Anfragen mit erlaubten Modellen (genau das, was der Körperkompass-Server schickt)
func relayMessages(w http.ResponseWriter, r *http.Request) {
	var name string
	var balance int64
	if db.QueryRow(`SELECT name, balance FROM relay_keys WHERE hash=?`, keyHash(relayKey(r))).Scan(&name, &balance) != nil {
		relayError(w, 401, "authentication_error", "Unbekannter Relais-Schlüssel")
		return
	}
	if balance <= 0 {
		relayError(w, 402, "billing_error", "Guthaben aufgebraucht – bitte aufladen")
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 30<<20))
	if err != nil {
		relayError(w, 400, "invalid_request_error", "Anfrage unlesbar")
		return
	}
	var req struct {
		Model     string `json:"model"`
		MaxTokens int    `json:"max_tokens"`
		Stream    bool   `json:"stream"`
	}
	json.Unmarshal(body, &req)
	if req.Stream || req.MaxTokens > 16000 || !strings.Contains(","+env("RELAY_MODELS", "claude-opus-5-5,claude-sonnet-5-5,claude-haiku-5-5")+",", ","+req.Model+",") {
		relayError(w, 400, "invalid_request_error", "Nicht erlaubt: nur Körperkompass-Anfragen (ohne Streaming, erlaubte Modelle, max_tokens ≤ 16000)")
		return
	}
	out, _ := http.NewRequestWithContext(r.Context(), "POST", "https://api.anthropic.com"+r.URL.Path+"?"+r.URL.RawQuery, bytes.NewReader(body))
	out.Header.Set("Content-Type", "application/json")
	out.Header.Set("X-Api-Key", os.Getenv("ANTHROPIC_API_KEY"))
	for _, h := range []string{"Anthropic-Version", "Anthropic-Beta"} {
		if v := r.Header.Get(h); v != "" {
			out.Header.Set(h, v)
		}
	}
	resp, err := (&http.Client{Timeout: 6 * time.Minute}).Do(out)
	if err != nil {
		relayError(w, 502, "api_error", "Claude nicht erreichbar")
		return
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == 200 {
		var res struct {
			Model string `json:"model"`
			Usage struct {
				In  int64 `json:"input_tokens"`
				Out int64 `json:"output_tokens"`
				CR  int64 `json:"cache_read_input_tokens"`
				CW  int64 `json:"cache_creation_input_tokens"`
			} `json:"usage"`
		}
		json.Unmarshal(data, &res)
		rate, _ := strconv.ParseFloat(env("RELAY_EUR_PER_USD", "0.92"), 64)
		markup, _ := strconv.ParseFloat(env("RELAY_MARKUP", "1.5"), 64)
		micro := int64(cost(res.Model, res.Usage.In, res.Usage.Out, res.Usage.CR, res.Usage.CW) * rate * markup * 1e6)
		db.Exec(`UPDATE relay_keys SET balance=balance-?, used=used+? WHERE name=?`, micro, micro, name)
		db.Exec(`INSERT INTO relay_usage(name, day, model, calls, input, output, micro) VALUES(?,?,?,1,?,?,?)
			ON CONFLICT(name, day, model) DO UPDATE SET calls=calls+1, input=input+excluded.input, output=output+excluded.output, micro=micro+excluded.micro`,
			name, time.Now().Format("2006-01-02"), res.Model, res.Usage.In+res.Usage.CR+res.Usage.CW, res.Usage.Out, micro)
	}
	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	w.WriteHeader(resp.StatusCode)
	w.Write(data)
}

// GET /v1/balance → {name, balance, used} in Euro (für Anzeige im eigenen Server bzw. in der App)
func relayBalance(w http.ResponseWriter, r *http.Request) {
	var name string
	var b, u int64
	if db.QueryRow(`SELECT name, balance, used FROM relay_keys WHERE hash=?`, keyHash(relayKey(r))).Scan(&name, &b, &u) != nil {
		relayError(w, 401, "authentication_error", "Unbekannter Relais-Schlüssel")
		return
	}
	writeJSON(w, map[string]any{"name": name, "balance": float64(b) / 1e6, "used": float64(u) / 1e6})
}

func runRelay() {
	if os.Getenv("ANTHROPIC_API_KEY") == "" {
		log.Fatal("ANTHROPIC_API_KEY fehlt")
	}
	openRelayDB()
	m := http.NewServeMux()
	m.HandleFunc("POST /v1/messages", relayMessages)
	m.HandleFunc("GET /v1/balance", relayBalance)
	addr := env("RELAY_ADDR", ":8090")
	log.Printf("KI-Relais %s auf %s", version, addr)
	log.Fatal(http.ListenAndServe(addr, m))
}
