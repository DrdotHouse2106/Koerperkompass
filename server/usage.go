package main

// KI-Verbrauch: zählt pro Nutzer, Tag und Modell die Tokens jeder Claude-Anfrage (aus der Antwort von Anthropic)
// und schätzt die Kosten. Grundlage, um später Preise oder Guthaben festzulegen. Hintergrundaufgaben
// (z. B. Übersetzung der Übungen) zählen unter Nutzer 0.

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/anthropics/anthropic-sdk-go/v2"
)

// Listenpreise in US-Dollar pro Million Tokens (Stand 11/2026): Eingabe, Ausgabe, Cache lesen, Cache schreiben
var prices = map[string][4]float64{
	"opus":   {4, 20, 0.20, 5},
	"sonnet": {2, 10, 0.10, 2.5},
	"haiku":  {0.10, 0.50, 0.01, 0.125},
	"fable":  {8, 40, 0.20, 10},
}

func migrateUsage() {
	db.Exec(`CREATE TABLE IF NOT EXISTS ai_usage (user_id INTEGER NOT NULL, day TEXT NOT NULL, model TEXT NOT NULL,
		calls INTEGER NOT NULL DEFAULT 0, input INTEGER NOT NULL DEFAULT 0, output INTEGER NOT NULL DEFAULT 0,
		cache_read INTEGER NOT NULL DEFAULT 0, cache_write INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, day, model))`)
}

func recordUsage(ctx context.Context, model string, u anthropic.BetaUsage) {
	user, _ := ctx.Value(ctxKey{}).(int64)
	db.Exec(`INSERT INTO ai_usage(user_id, day, model, calls, input, output, cache_read, cache_write) VALUES(?,?,?,1,?,?,?,?)
		ON CONFLICT(user_id, day, model) DO UPDATE SET calls=calls+1, input=input+excluded.input, output=output+excluded.output,
		cache_read=cache_read+excluded.cache_read, cache_write=cache_write+excluded.cache_write`,
		user, time.Now().Format("2006-01-02"), model, u.InputTokens, u.OutputTokens, u.CacheReadInputTokens, u.CacheCreationInputTokens)
}

// cost schätzt die Kosten in US-Dollar
func cost(model string, in, out, cr, cw int64) float64 {
	p := prices["opus"]
	for k, v := range prices {
		if strings.Contains(model, k) {
			p = v
		}
	}
	return (float64(in)*p[0] + float64(out)*p[1] + float64(cr)*p[2] + float64(cw)*p[3]) / 1e6
}

// GET /api/usage?days=30 → eigener Verbrauch pro Tag und Modell, Summe und geschätzte Kosten (USD)
func getUsage(w http.ResponseWriter, r *http.Request) {
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 || days > 366 {
		days = 30
	}
	since := time.Now().AddDate(0, 0, -days+1).Format("2006-01-02")
	rows, err := db.Query(`SELECT day, model, calls, input, output, cache_read, cache_write FROM ai_usage WHERE user_id=? AND day>=? ORDER BY day DESC, model`, uid(r), since)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	list := []map[string]any{}
	var calls, tokens int64
	var usd float64
	for rows.Next() {
		var day, model string
		var c, in, out, cr, cw int64
		rows.Scan(&day, &model, &c, &in, &out, &cr, &cw)
		k := cost(model, in, out, cr, cw)
		calls, tokens, usd = calls+c, tokens+in+out+cr+cw, usd+k
		list = append(list, map[string]any{"day": day, "model": model, "calls": c, "input": in, "output": out, "cacheRead": cr, "cacheWrite": cw, "usd": k})
	}
	writeJSON(w, map[string]any{"days": days, "calls": calls, "tokens": tokens, "usd": usd, "rows": list})
}
