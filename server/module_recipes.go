package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/anthropics/anthropic-sdk-go/v2"
)

// Rezepte: eigene Rezeptsammlung. Ein Eintrag je Rezept (Titel, Zutaten, Schritte, Nährwerte pro Portion).
// Keine Felder für die Analyse – ein Rezept ist nichts Gegessenes; „Gegessen“ legt einen Ernährungs-Eintrag an.
//
// Reel-Links (Facebook, Instagram, TikTok) verarbeitet Reelkoch (github.com/DrdotHouse2106/Reelkoch):
// KK_REELKOCH_URL und KK_REELKOCH_TOKEN (API-Token aus Reelkoch → Konto). Video, Ton und Bilder bleiben dort.
// Eingefügter Text (z. B. Beschreibung eines Reels) wird direkt mit Claude strukturiert.
var recipes = Module{ID: "recipes", Name: "Rezepte", Symbol: "book.closed.fill", Fields: []Field{}}

func reelkochEnabled() bool { return env("KK_REELKOCH_URL", "") != "" && env("KK_REELKOCH_TOKEN", "") != "" }

var reelkochClient = &http.Client{Timeout: 30 * time.Second}

// reelkoch ruft die Reelkoch-API auf und leitet Fehler mit Statuscode weiter.
func reelkoch(method, path string, body any, out any) (int, error) {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, strings.TrimRight(env("KK_REELKOCH_URL", ""), "/")+path, rd)
	req.Header.Set("Authorization", "Bearer "+env("KK_REELKOCH_TOKEN", ""))
	req.Header.Set("Content-Type", "application/json")
	resp, err := reelkochClient.Do(req)
	if err != nil {
		return http.StatusBadGateway, fmt.Errorf("Reelkoch nicht erreichbar: %w", err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if resp.StatusCode >= 300 {
		return resp.StatusCode, fmt.Errorf("Reelkoch: %s", strings.TrimSpace(string(data)))
	}
	return resp.StatusCode, json.Unmarshal(data, out)
}

func requireReelkoch(w http.ResponseWriter) bool {
	if !reelkochEnabled() {
		http.Error(w, "Reelkoch ist auf dem Server nicht eingerichtet (KK_REELKOCH_URL, KK_REELKOCH_TOKEN)", http.StatusNotImplemented)
		return false
	}
	return true
}

// POST /api/recipes/reel {url} → Auftrag bei Reelkoch, Antwort {id, status}
func recipeReel(w http.ResponseWriter, r *http.Request) {
	var req struct{ URL string }
	if !requireReelkoch(w) || !readJSON(w, r, &req) {
		return
	}
	var res map[string]any
	if code, err := reelkoch("POST", "/api/rezept", map[string]string{"url": strings.TrimSpace(req.URL)}, &res); err != nil {
		http.Error(w, err.Error(), code)
		return
	}
	writeJSON(w, res)
}

// GET /api/recipes/reel/{id}?nutrition=1 → {status, fehler?, recipe?}. Fertige Rezepte im App-Format,
// mit nutrition=1 (nur mit Zustimmung der Person) inklusive geschätzter Nährwerte pro Portion.
func recipeReelStatus(w http.ResponseWriter, r *http.Request) {
	if !requireReelkoch(w) {
		return
	}
	var d struct {
		Status string `json:"status"`
		Fehler string `json:"fehler"`
		URL    string `json:"url"`
		Rezept *struct {
			Titel     string  `json:"titel"`
			Portionen *string `json:"portionen"`
			Zeit      *string `json:"zeit"`
			Zutaten   []struct {
				Menge string `json:"menge"`
				Zutat string `json:"zutat"`
			} `json:"zutaten"`
			Schritte []string `json:"schritte"`
			Hinweise *string  `json:"hinweise"`
			Quelle   string   `json:"quelle"`
		} `json:"rezept"`
	}
	if code, err := reelkoch("GET", "/api/rezept/"+r.PathValue("id"), nil, &d); err != nil {
		http.Error(w, err.Error(), code)
		return
	}
	res := map[string]any{"status": d.Status}
	if d.Fehler != "" {
		res["fehler"] = d.Fehler
	}
	if d.Status == "fertig" && d.Rezept != nil {
		x := d.Rezept
		var ingredients []map[string]string
		for _, z := range x.Zutaten {
			ingredients = append(ingredients, map[string]string{"amount": z.Menge, "name": z.Zutat})
		}
		recipe := map[string]any{"title": x.Titel, "servings": deref(x.Portionen), "time": deref(x.Zeit),
			"ingredients": ingredients, "steps": x.Schritte, "notes": deref(x.Hinweise),
			"source": firstNonEmpty(x.Quelle, d.URL), "reelkoch": r.PathValue("id")}
		if r.URL.Query().Get("nutrition") == "1" && aiEnabled() {
			if n, err := recipeNutrition(r, recipe); err == nil {
				for k, v := range n {
					recipe[k] = v
				}
			}
		}
		res["recipe"] = recipe
	}
	writeJSON(w, res)
}

// GET /api/recipes/reelkoch → fertige Rezepte aus Reelkoch zum Übernehmen
func recipeReelList(w http.ResponseWriter, r *http.Request) {
	if !requireReelkoch(w) {
		return
	}
	var list []map[string]any
	if code, err := reelkoch("GET", "/api/rezepte", nil, &list); err != nil {
		http.Error(w, err.Error(), code)
		return
	}
	out := []map[string]any{}
	for _, x := range list {
		if x["status"] == "fertig" {
			out = append(out, map[string]any{"id": x["id"], "title": x["titel"], "url": x["url"], "date": x["datum"]})
		}
	}
	writeJSON(w, out)
}

// recipeNutrition schätzt Nährwerte pro Portion (kleines Modell, Bruchteile eines Cents).
func recipeNutrition(r *http.Request, recipe map[string]any) (map[string]any, error) {
	b, _ := json.Marshal(recipe)
	system := `Schätze realistische Nährwerte pro Portion für dieses Rezept (deutsche Lebensmittel).
Sind keine Portionen angegeben, nimm eine übliche Anzahl an. Antworte ausschließlich mit JSON:
{"servings": "Anzahl Portionen als Text", "kcal": Zahl, "protein": g, "carbs": g, "fat": g}`
	out, err := askModel(r.Context(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
		[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(string(b)))})
	if err != nil {
		return nil, err
	}
	var n map[string]any
	i, j := strings.Index(out, "{"), strings.LastIndex(out, "}")
	if i < 0 || j < i {
		return nil, fmt.Errorf("Antwort nicht verwertbar")
	}
	if err := json.Unmarshal([]byte(out[i:j+1]), &n); err != nil {
		return nil, err
	}
	if s, ok := recipe["servings"].(string); ok && s != "" {
		delete(n, "servings") // genannte Portionen behalten
	}
	return n, nil
}

// POST /api/ai/recipe {text, lang} → Rezept aus eingefügtem Text (z. B. Reel-Beschreibung), mit Nährwerten pro Portion
func aiRecipe(w http.ResponseWriter, r *http.Request) {
	var req struct{ Text, Lang string }
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	if strings.TrimSpace(req.Text) == "" || len(req.Text) > 20000 {
		http.Error(w, "Text fehlt oder ist zu lang", http.StatusBadRequest)
		return
	}
	system := `Mach aus dem Text ein Rezept. Erfinde nichts: fehlende Mengen bleiben leer oder so, wie genannt („etwas“, „1 Schuss“).
Schätze zusätzlich realistische Nährwerte pro Portion (deutsche Lebensmittel; ohne Portionsangabe eine übliche Anzahl annehmen).
Antworte ausschließlich mit JSON:
{"title": "…", "servings": "…", "time": "… oder leer", "ingredients": [{"amount": "…", "name": "…"}], "steps": ["…"],
 "notes": "kurze Tipps oder leer", "kcal": Zahl, "protein": g, "carbs": g, "fat": g}
Sprache: ` + langName(req.Lang) + `. Ist kein Rezept erkennbar, gib {"error": "kurze Begründung"} zurück.`
	out, err := askModel(r.Context(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
		[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(req.Text))})
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeObject(w, out)
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func firstNonEmpty(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
