package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"syscall"
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

func reelkochEnabled() bool {
	return env("KK_REELKOCH_URL", "") != "" && env("KK_REELKOCH_TOKEN", "") != ""
}

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
			// Mehrere Varianten in einem Reel („Variante 1 …“)? Dann als eigenständige Rezepte aufteilen
			if parts := recipeVariants(r, recipe); len(parts) > 1 {
				res["recipes"] = parts
			} else if n, err := recipeNutrition(r, recipe); err == nil {
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

// recipeVariants teilt ein Rezept mit mehreren Varianten (Schritte „Variante 1 …“, „Version 2 …“) in eigenständige
// Rezepte mit eigenen Zutaten und Nährwerten pro Portion. Ohne Varianten oder bei Fehlern: nil.
func recipeVariants(r *http.Request, recipe map[string]any) []map[string]any {
	steps, _ := recipe["steps"].([]string)
	n := 0
	for _, s := range steps {
		l := strings.ToLower(s)
		if strings.HasPrefix(l, "variante") || strings.HasPrefix(l, "version") || strings.HasPrefix(l, "variant") {
			n++
		}
	}
	if n < 2 {
		return nil
	}
	b, _ := json.Marshal(recipe)
	system := `Das Rezept enthält mehrere Varianten. Teile es in eigenständige Rezepte – eins je Variante – mit den Zutaten,
die diese Variante braucht (gemeinsame Grundzutaten gehören zu jeder Variante, die sie nutzt; Mengen sinnvoll aufteilen),
den Schritten dieser Variante und realistischen Nährwerten pro Portion. Erfinde keine Zutaten. Antworte ausschließlich mit JSON:
{"recipes": [{"title": "…", "servings": "…", "time": "", "ingredients": [{"amount": "…", "name": "…"}], "steps": ["…"],
"notes": "", "kcal": Zahl, "protein": g, "carbs": g, "fat": g}]}`
	out, err := askModel(r.Context(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
		[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(string(b)))})
	if err != nil {
		return nil
	}
	var res struct {
		Recipes []map[string]any `json:"recipes"`
	}
	i, j := strings.Index(out, "{"), strings.LastIndex(out, "}")
	if i < 0 || j < i || json.Unmarshal([]byte(out[i:j+1]), &res) != nil {
		return nil
	}
	for _, x := range res.Recipes {
		x["source"], x["reelkoch"] = recipe["source"], recipe["reelkoch"]
	}
	return res.Recipes
}

// recipeNutrition schätzt Nährwerte pro Portion (kleines Modell, Bruchteile eines Cents).
func recipeNutrition(r *http.Request, recipe map[string]any) (map[string]any, error) {
	ctx := r.Context()
	b, _ := json.Marshal(recipe)
	system := `Schätze realistische Nährwerte pro Portion für dieses Rezept (deutsche Lebensmittel).
Sind keine Portionen angegeben, nimm eine übliche Anzahl an. Antworte ausschließlich mit JSON:
{"servings": "Anzahl Portionen als Text", "kcal": Zahl, "protein": g, "carbs": g, "fat": g}`
	out, err := askModel(ctx, env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
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
	var req struct{ Text, Lang, Image string } // Image: optional JPEG (Base64), z. B. Kochbuchseite oder Screenshot
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	if (strings.TrimSpace(req.Text) == "" && req.Image == "") || len(req.Text) > 20000 || len(req.Image) > 6<<20 {
		http.Error(w, "Text bzw. Foto fehlt oder ist zu groß", http.StatusBadRequest)
		return
	}
	out, err := recipeFromText(r.Context(), req.Text, req.Lang, req.Image)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeObject(w, out)
}

// recipeFromText lässt Claude (kleines Modell) aus beliebigem Text ein Rezept mit Nährwerten machen.
func recipeFromText(ctx context.Context, text, lang string, image ...string) (string, error) {
	system := `Mach aus dem Text ein Rezept. Erfinde nichts: fehlende Mengen bleiben leer oder so, wie genannt („etwas“, „1 Schuss“).
Schätze zusätzlich realistische Nährwerte pro Portion (deutsche Lebensmittel; ohne Portionsangabe eine übliche Anzahl annehmen).
Antworte ausschließlich mit JSON:
{"title": "…", "servings": "…", "time": "… oder leer", "ingredients": [{"amount": "…", "name": "…"}], "steps": ["…"],
 "notes": "kurze Tipps oder leer", "kcal": Zahl, "protein": g, "carbs": g, "fat": g}
Sprache: ` + langName(lang) + `. Ist kein Rezept erkennbar, gib {"error": "kurze Begründung"} zurück.`
	blocks := []anthropic.BetaContentBlockParamUnion{}
	if len(image) > 0 && image[0] != "" {
		// Foto einer Kochbuchseite, Rezeptkarte oder eines Screenshots: Text ablesen
		blocks = append(blocks, anthropic.NewBetaImageBlock(anthropic.BetaBase64ImageSourceParam{Data: image[0], MediaType: anthropic.BetaBase64ImageSourceMediaTypeImageJPEG}))
		if strings.TrimSpace(text) != "" {
			text = "Lies das Rezept vom Foto ab.\nHinweis: " + text
		} else {
			text = "Lies das Rezept vom Foto ab."
		}
	}
	blocks = append(blocks, anthropic.NewBetaTextBlock(text))
	return askModel(ctx, env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
		[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(blocks...)})
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

// ---- Beliebiger Link: Video/Reel → Reelkoch, Webseite → eingebettete Rezeptdaten (schema.org), sonst Claude ----

// Hosts, deren Links als Video an Reelkoch gehen (dort ggf. ERLAUBTE_HOSTS passend erweitern)
func videoHost(u *url.URL) bool {
	host := strings.ToLower(u.Hostname())
	for _, h := range strings.Split(env("KK_REELKOCH_HOSTS", "facebook.com,fb.watch,instagram.com,tiktok.com,youtube.com,youtu.be"), ",") {
		if h = strings.TrimSpace(h); h != "" && (host == h || strings.HasSuffix(host, "."+h)) {
			return true
		}
	}
	return false
}

// POST /api/recipes/link {url, ai, lang} → {"kind":"video","id":…} (Auftrag bei Reelkoch) oder {"kind":"web","recipe":{…}}
func recipeLink(w http.ResponseWriter, r *http.Request) {
	var req struct {
		URL  string
		AI   bool // Zustimmung: Claude darf Seite lesen bzw. Nährwerte schätzen
		Lang string
	}
	if !readJSON(w, r, &req) {
		return
	}
	u, err := url.Parse(strings.TrimSpace(req.URL))
	if err != nil || (u.Scheme != "https" && u.Scheme != "http") || u.Host == "" {
		http.Error(w, "Kein gültiger Link", http.StatusBadRequest)
		return
	}
	if videoHost(u) {
		if !requireReelkoch(w) {
			return
		}
		var res map[string]any
		if code, err := reelkoch("POST", "/api/rezept", map[string]string{"url": u.String()}, &res); err != nil {
			http.Error(w, err.Error(), code)
			return
		}
		writeJSON(w, map[string]any{"kind": "video", "id": res["id"], "status": res["status"]})
		return
	}
	page, err := fetchPage(u.String())
	if err != nil {
		http.Error(w, "Seite nicht abrufbar: "+err.Error(), http.StatusBadGateway)
		return
	}
	recipe := recipeFromJSONLD(page)
	if recipe == nil {
		if !req.AI || !aiEnabled() {
			http.Error(w, "Auf der Seite sind keine Rezeptdaten eingebettet. Mit Zustimmung zu Claude kann die Seite gelesen werden.", http.StatusUnprocessableEntity)
			return
		}
		out, err := recipeFromText(r.Context(), pageText(page), req.Lang)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		i, j := strings.Index(out, "{"), strings.LastIndex(out, "}")
		if i < 0 || j < i || json.Unmarshal([]byte(out[i:j+1]), &recipe) != nil {
			http.Error(w, "Antwort nicht verwertbar", http.StatusBadGateway)
			return
		}
		if e, ok := recipe["error"].(string); ok {
			http.Error(w, e, http.StatusUnprocessableEntity)
			return
		}
	} else if recipe["kcal"] == nil && req.AI && aiEnabled() {
		if n, err := recipeNutrition(r, recipe); err == nil {
			for k, v := range n {
				recipe[k] = v
			}
		}
	}
	recipe["source"] = u.String()
	writeJSON(w, map[string]any{"kind": "web", "recipe": recipe})
}

// fetchPage lädt eine öffentliche Webseite – nie Adressen im eigenen Netz (Schutz vor Missbrauch des Servers)
var pageClient = &http.Client{Timeout: 20 * time.Second, Transport: &http.Transport{
	DialContext: (&net.Dialer{Timeout: 5 * time.Second, Control: func(_, address string, _ syscall.RawConn) error {
		host, _, _ := net.SplitHostPort(address)
		if ip := net.ParseIP(host); ip == nil || ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
			return fmt.Errorf("Adresse im lokalen Netz nicht erlaubt")
		}
		return nil
	}}).DialContext,
}}

func fetchPage(u string) (string, error) {
	req, _ := http.NewRequest("GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; Koerperkompass)")
	req.Header.Set("Accept-Language", "de,en;q=0.5")
	resp, err := pageClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	return string(b), err
}

var (
	ldRe    = regexp.MustCompile(`(?is)<script[^>]*application/ld\+json[^>]*>(.*?)</script>`)
	dropRe  = regexp.MustCompile(`(?is)<(script|style|noscript|svg)[^>]*>.*?</(script|style|noscript|svg)>`)
	tagRe   = regexp.MustCompile(`(?s)<[^>]+>`)
	spaceRe = regexp.MustCompile(`\s+`)
	numRe   = regexp.MustCompile(`[\d]+(?:[.,]\d+)?`)
	// Menge am Anfang einer Zutat: „200 g Mehl“, „1/2 TL Salz“, „2 Eier“
	amountRe = regexp.MustCompile(`^((?:[\d½¼¾⅓⅔.,/\- ]+)(?:\s*(?:g|kg|mg|ml|l|cl|dl|EL|TL|Msp\.?|Prise[n]?|Pck\.?|Päckchen|Stück|Stk\.?|Dose[n]?|Becher|Bund|Zehe[n]?|Scheibe[n]?|Tasse[n]?|Handvoll|cups?|tbsp|tsp|oz)\b\.?)?)\s+(.+)$`)
)

// pageText: lesbarer Text einer Seite für Claude (gekürzt)
func pageText(page string) string {
	t := spaceRe.ReplaceAllString(tagRe.ReplaceAllString(dropRe.ReplaceAllString(page, " "), " "), " ")
	if len(t) > 15000 {
		t = t[:15000]
	}
	return strings.TrimSpace(t)
}

// recipeFromJSONLD liest schema.org/Recipe aus eingebettetem JSON-LD (Chefkoch, Lecker, die meisten Blogs …)
func recipeFromJSONLD(page string) map[string]any {
	for _, m := range ldRe.FindAllStringSubmatch(page, -1) {
		var v any
		if json.Unmarshal([]byte(strings.TrimSpace(m[1])), &v) != nil {
			continue
		}
		if x := findRecipe(v); x != nil {
			return mapRecipe(x)
		}
	}
	return nil
}

func findRecipe(v any) map[string]any {
	switch t := v.(type) {
	case []any:
		for _, x := range t {
			if r := findRecipe(x); r != nil {
				return r
			}
		}
	case map[string]any:
		switch ty := t["@type"].(type) {
		case string:
			if ty == "Recipe" {
				return t
			}
		case []any:
			for _, x := range ty {
				if x == "Recipe" {
					return t
				}
			}
		}
		if g, ok := t["@graph"]; ok {
			return findRecipe(g)
		}
	}
	return nil
}

func mapRecipe(x map[string]any) map[string]any {
	var str func(v any) string
	str = func(v any) string {
		switch t := v.(type) {
		case string:
			return strings.TrimSpace(htmlText(t))
		case float64:
			return strconv.FormatFloat(t, 'f', -1, 64)
		case []any:
			if len(t) > 0 {
				return str(t[0])
			}
		}
		return ""
	}
	var ingredients []map[string]string
	for _, z := range asList(x["recipeIngredient"]) {
		z := spaceRe.ReplaceAllString(str(z), " ")
		if m := amountRe.FindStringSubmatch(z); m != nil {
			ingredients = append(ingredients, map[string]string{"amount": strings.TrimSpace(m[1]), "name": m[2]})
		} else if z != "" {
			ingredients = append(ingredients, map[string]string{"amount": "", "name": z})
		}
	}
	var steps []string
	var addSteps func(v any)
	addSteps = func(v any) {
		switch t := v.(type) {
		case string:
			for _, s := range strings.Split(htmlText(t), "\n") {
				if s = strings.TrimSpace(s); s != "" {
					steps = append(steps, s)
				}
			}
		case []any:
			for _, s := range t {
				addSteps(s)
			}
		case map[string]any:
			if l, ok := t["itemListElement"]; ok {
				addSteps(l)
			} else {
				addSteps(t["text"])
			}
		}
	}
	addSteps(x["recipeInstructions"])
	r := map[string]any{"title": str(x["name"]), "servings": numRe.FindString(str(x["recipeYield"])),
		"time": isoDuration(str(x["totalTime"])), "ingredients": ingredients, "steps": steps, "notes": ""}
	if img := imageURL(x["image"]); img != "" {
		r["image"] = img
	}
	if n, ok := x["nutrition"].(map[string]any); ok {
		for k, key := range map[string]string{"kcal": "calories", "protein": "proteinContent", "carbs": "carbohydrateContent", "fat": "fatContent"} {
			if f, err := strconv.ParseFloat(strings.ReplaceAll(numRe.FindString(str(n[key])), ",", "."), 64); err == nil && f > 0 {
				r[k] = f
			}
		}
	}
	return r
}

func asList(v any) []any {
	if l, ok := v.([]any); ok {
		return l
	}
	if v == nil {
		return nil
	}
	return []any{v}
}

func imageURL(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case []any:
		if len(t) > 0 {
			return imageURL(t[0])
		}
	case map[string]any:
		return imageURL(t["url"])
	}
	return ""
}

func htmlText(s string) string {
	s = strings.NewReplacer("<br>", "\n", "<br/>", "\n", "<br />", "\n", "</p>", "\n", "&amp;", "&", "&nbsp;", " ", "&quot;", "\"", "&#39;", "'").Replace(s)
	return tagRe.ReplaceAllString(s, "")
}

// isoDuration: „PT1H30M“ → „1 Std. 30 Min.“
func isoDuration(s string) string {
	m := regexp.MustCompile(`^P(?:\d+D)?T?(?:(\d+)H)?(?:(\d+)M)?`).FindStringSubmatch(s)
	if m == nil || (m[1] == "" && m[2] == "") {
		return ""
	}
	var parts []string
	if m[1] != "" && m[1] != "0" {
		parts = append(parts, m[1]+" Std.")
	}
	if m[2] != "" && m[2] != "0" {
		parts = append(parts, m[2]+" Min.")
	}
	return strings.Join(parts, " ")
}
