package main

// Übungsbibliothek: rund 870 Übungen aus der gemeinfreien „free-exercise-db“ (github.com/yuhonas/free-exercise-db,
// Unlicense) mit Haupt- und Hilfsmuskeln, Gerät, Anleitung und zwei Bildern (Start/Ende).
// Deutsche Namen und Anleitungen übersetzt Claude einmalig (nur öffentliche Übungstexte, keine persönlichen Daten)
// und der Server merkt sie sich. Bilder holt der Server einmal von GitHub und hält sie im Datenordner vor.

import (
	"context"
	_ "embed"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"

	"github.com/anthropics/anthropic-sdk-go/v2"
)

//go:embed exercises.json
var exercisesJSON []byte

type exercise struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Level        string   `json:"level"`
	Equipment    *string  `json:"equipment"`
	Primary      []string `json:"primaryMuscles"`
	Secondary    []string `json:"secondaryMuscles"`
	Instructions []string `json:"instructions"`
	Category     string   `json:"category"`
	Mechanic     *string  `json:"mechanic"`
	Force        *string  `json:"force"`
	Images       []string `json:"images"`
}

var (
	exOnce  sync.Once
	exList  []exercise
	exByID  = map[string]*exercise{}
	exMu    sync.Mutex // eine Übersetzung der Namen gleichzeitig
	imgPath = regexp.MustCompile(`^[A-Za-z0-9_\-()',.]+/[01]\.jpg$`)
)

func loadExercises() {
	exOnce.Do(func() {
		json.Unmarshal(exercisesJSON, &exList)
		for i := range exList {
			exByID[exList[i].ID] = &exList[i]
		}
		db.Exec(`CREATE TABLE IF NOT EXISTS exercise_de (id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '', instructions TEXT NOT NULL DEFAULT '')`)
	})
}

// deutsche Namen aus dem Speicher
func exerciseNamesDE() map[string]string {
	m := map[string]string{}
	rows, err := db.Query(`SELECT id, name FROM exercise_de WHERE name <> ''`)
	if err != nil {
		return m
	}
	defer rows.Close()
	for rows.Next() {
		var id, n string
		rows.Scan(&id, &n)
		m[id] = n
	}
	return m
}

// GET /api/exercises → Liste (ohne Anleitung); fehlen deutsche Namen, werden sie im Hintergrund übersetzt
func listExercises(w http.ResponseWriter, r *http.Request) {
	loadExercises()
	de := exerciseNamesDE()
	if len(de) < len(exList) && aiEnabled() {
		go translateNames()
	}
	out := make([]map[string]any, 0, len(exList))
	for _, e := range exList {
		out = append(out, map[string]any{"id": e.ID, "name": e.Name, "nameDe": de[e.ID], "level": e.Level, "equipment": e.Equipment,
			"primary": e.Primary, "secondary": e.Secondary, "category": e.Category, "images": e.Images})
	}
	writeJSON(w, out)
}

// GET /api/exercises/{id} → eine Übung mit Anleitung (auf Deutsch, sobald übersetzt)
func getExercise(w http.ResponseWriter, r *http.Request) {
	loadExercises()
	e, ok := exByID[r.PathValue("id")]
	if !ok {
		http.NotFound(w, r)
		return
	}
	var nameDe, instrDe string
	db.QueryRow(`SELECT name, instructions FROM exercise_de WHERE id=?`, e.ID).Scan(&nameDe, &instrDe)
	if instrDe == "" && aiEnabled() && r.URL.Query().Get("lang") != "en" {
		nameDe, instrDe = translateExercise(r, e, nameDe)
	}
	var steps []string
	json.Unmarshal([]byte(instrDe), &steps)
	writeJSON(w, map[string]any{"id": e.ID, "name": e.Name, "nameDe": nameDe, "level": e.Level, "equipment": e.Equipment,
		"primary": e.Primary, "secondary": e.Secondary, "category": e.Category, "mechanic": e.Mechanic, "force": e.Force,
		"images": e.Images, "instructions": e.Instructions, "instructionsDe": steps})
}

// translateExercise übersetzt Name und Anleitung einer Übung (kleines Modell) und merkt sie sich
func translateExercise(r *http.Request, e *exercise, nameDe string) (string, string) {
	b, _ := json.Marshal(map[string]any{"name": e.Name, "instructions": e.Instructions})
	system := `Übersetze diese Fitness-Übung ins Deutsche. Übliche deutsche Studiobezeichnungen verwenden (z. B. „Bankdrücken“,
„Kreuzheben“, „Seitheben mit Kurzhanteln“); feste Fachbegriffe wie „Curl“ dürfen bleiben. Anleitung natürlich, per Du.
Antworte ausschließlich mit JSON: {"name": "…", "instructions": ["…", "…"]}`
	out, err := askModel(r.Context(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
		[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(string(b)))})
	if err != nil {
		return nameDe, ""
	}
	var res struct {
		Name         string   `json:"name"`
		Instructions []string `json:"instructions"`
	}
	i, j := strings.Index(out, "{"), strings.LastIndex(out, "}")
	if i < 0 || j < i || json.Unmarshal([]byte(out[i:j+1]), &res) != nil || len(res.Instructions) == 0 {
		return nameDe, ""
	}
	if nameDe == "" {
		nameDe = res.Name
	}
	steps, _ := json.Marshal(res.Instructions)
	db.Exec(`INSERT INTO exercise_de(id, name, instructions) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, instructions=excluded.instructions`,
		e.ID, nameDe, string(steps))
	return nameDe, string(steps)
}

// translateAll übersetzt beim Start einmal alles, was noch fehlt: erst alle Namen, dann alle Anleitungen
// (je 8 Übungen pro Aufruf, kleines Modell). Läuft im Hintergrund; was fertig ist, bleibt gespeichert.
func translateAll() {
	if !aiEnabled() {
		return
	}
	loadExercises()
	translateNames()
	have := map[string]bool{}
	if rows, err := db.Query(`SELECT id FROM exercise_de WHERE instructions <> ''`); err == nil {
		for rows.Next() {
			var id string
			rows.Scan(&id)
			have[id] = true
		}
		rows.Close()
	}
	var todo []exercise
	for _, e := range exList {
		if !have[e.ID] && len(e.Instructions) > 0 {
			todo = append(todo, e)
		}
	}
	system := `Übersetze diese Fitness-Übungen ins Deutsche: Name mit üblicher deutscher Studiobezeichnung, Anleitung natürlich und per Du.
Antworte ausschließlich mit JSON: {"<id>": {"name": "…", "instructions": ["…", "…"]}, …}`
	for len(todo) > 0 {
		n := min(8, len(todo))
		in := map[string]any{}
		for _, e := range todo[:n] {
			in[e.ID] = map[string]any{"name": e.Name, "instructions": e.Instructions}
		}
		todo = todo[n:]
		b, _ := json.Marshal(in)
		out, err := askModel(context.Background(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
			[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(string(b)))})
		if err != nil {
			log.Printf("Übungen übersetzen: %v", err)
			return
		}
		var res map[string]struct {
			Name         string   `json:"name"`
			Instructions []string `json:"instructions"`
		}
		i, j := strings.Index(out, "{"), strings.LastIndex(out, "}")
		if i < 0 || j < i || json.Unmarshal([]byte(out[i:j+1]), &res) != nil {
			continue
		}
		for id, x := range res {
			if _, ok := exByID[id]; !ok || len(x.Instructions) == 0 {
				continue
			}
			steps, _ := json.Marshal(x.Instructions)
			db.Exec(`INSERT INTO exercise_de(id, name, instructions) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET
				name=CASE WHEN exercise_de.name='' THEN excluded.name ELSE exercise_de.name END, instructions=excluded.instructions`,
				id, strings.TrimSpace(x.Name), string(steps))
		}
	}
	log.Printf("Übungen: Übersetzung vollständig")
}

// translateNames übersetzt fehlende Namen in Blöcken zu 100 (einmalig, im Hintergrund)
func translateNames() {
	if !exMu.TryLock() {
		return
	}
	defer exMu.Unlock()
	de := exerciseNamesDE()
	var todo []exercise
	for _, e := range exList {
		if de[e.ID] == "" {
			todo = append(todo, e)
		}
	}
	system := `Übersetze die Namen dieser Fitness-Übungen ins Deutsche – übliche deutsche Studiobezeichnungen, kurz.
Antworte ausschließlich mit JSON: {"<id>": "deutscher Name", …}`
	for len(todo) > 0 {
		n := min(100, len(todo))
		in := map[string]string{}
		for _, e := range todo[:n] {
			in[e.ID] = e.Name
		}
		todo = todo[n:]
		b, _ := json.Marshal(in)
		out, err := askModel(context.Background(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
			[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(string(b)))})
		if err != nil {
			return
		}
		var res map[string]string
		i, j := strings.Index(out, "{"), strings.LastIndex(out, "}")
		if i < 0 || j < i || json.Unmarshal([]byte(out[i:j+1]), &res) != nil {
			continue
		}
		for id, name := range res {
			if _, ok := exByID[id]; ok && strings.TrimSpace(name) != "" {
				db.Exec(`INSERT INTO exercise_de(id, name) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name`, id, strings.TrimSpace(name))
			}
		}
	}
}

// GET /api/exercises/img/{path...} → Übungsbild (öffentlich, nur Pfade aus der Datenbank), im Datenordner zwischengespeichert
func exerciseImage(w http.ResponseWriter, r *http.Request) {
	p := r.PathValue("path")
	if !imgPath.MatchString(p) || strings.Contains(p, "..") {
		http.NotFound(w, r)
		return
	}
	file := filepath.Join(filepath.Dir(env("KK_DB", "data/koerperkompass.db")), "exercise-img", filepath.FromSlash(p))
	if _, err := os.Stat(file); err != nil {
		resp, err := pageClient.Get("https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/" + p)
		if err != nil || resp.StatusCode != 200 {
			if resp != nil {
				resp.Body.Close()
			}
			http.Error(w, "Bild nicht verfügbar", http.StatusBadGateway)
			return
		}
		data, _ := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
		resp.Body.Close()
		os.MkdirAll(filepath.Dir(file), 0o750)
		os.WriteFile(file, data, 0o640)
	}
	w.Header().Set("Cache-Control", "public, max-age="+strconv.Itoa(30*24*3600))
	w.Header().Set("Content-Type", "image/jpeg")
	http.ServeFile(w, r, file)
}
