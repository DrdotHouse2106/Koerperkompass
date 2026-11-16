package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/anthropics/anthropic-sdk-go/v2"
)

// Claude API ist optional: nur aktiv, wenn ANTHROPIC_API_KEY gesetzt ist.
// Die App fragt vor jedem Weitergeben ausdrücklich nach Zustimmung.
func aiEnabled() bool { return env("ANTHROPIC_API_KEY", "") != "" }

const disclaimer = "Hinweis: Dies ist eine automatische Auswertung und keine ärztliche Beratung."

// ask schickt eine Anfrage an Claude und gibt den Text der Antwort zurück.
// Lehnt das Modell ab, beantwortet ein Ersatzmodell die Anfrage (server-seitiger Fallback).
func ask(ctx context.Context, system string, effort anthropic.BetaOutputConfigEffort, content ...anthropic.BetaContentBlockParamUnion) (string, error) {
	client := anthropic.NewClient() // liest ANTHROPIC_API_KEY
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	msg, err := client.Beta.Messages.New(ctx, anthropic.BetaMessageNewParams{
		Model:        anthropic.Model(env("KK_MODEL", "claude-opus-5-5")),
		MaxTokens:    16000,
		System:       []anthropic.BetaTextBlockParam{{Text: system}},
		OutputConfig: anthropic.BetaOutputConfigParam{Effort: effort},
		Fallbacks:    anthropic.BetaFallbacksParamOfDefault(),
		Betas:        []anthropic.AnthropicBeta{anthropic.AnthropicBetaServerSideFallback2026_07_01},
		Messages:     []anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(content...)},
	})
	if err != nil {
		return "", err
	}
	if msg.StopReason == anthropic.BetaStopReasonRefusal {
		return "", errRefused
	}
	var b strings.Builder
	for _, c := range msg.Content {
		if c.Type == "text" {
			b.WriteString(c.Text)
		}
	}
	return b.String(), nil
}

type aiError string

func (e aiError) Error() string { return string(e) }

const errRefused = aiError("Anfrage wurde abgelehnt")

func requireAI(w http.ResponseWriter) bool {
	if !aiEnabled() {
		http.Error(w, "Auf dem Server ist kein Claude-API-Key hinterlegt", http.StatusNotImplemented)
		return false
	}
	return true
}

// aiPhoto schätzt Nährwerte aus einem Foto (JPEG, Base64).
func aiPhoto(w http.ResponseWriter, r *http.Request) {
	var req struct{ Image, Lang string }
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	system := `Du schätzt Nährwerte von Mahlzeiten auf Fotos. Antworte ausschließlich mit einem JSON-Objekt:
{"name": "kurze Bezeichnung", "kcal": Zahl, "protein": Gramm, "carbs": Gramm, "fat": Gramm}
Schätze die sichtbare Portion. Sprache für "name": ` + langName(req.Lang) + `.`
	out, err := ask(r.Context(), system, anthropic.BetaOutputConfigEffortLow,
		anthropic.NewBetaImageBlock(anthropic.BetaBase64ImageSourceParam{Data: req.Image, MediaType: anthropic.BetaBase64ImageSourceMediaTypeImageJPEG}),
		anthropic.NewBetaTextBlock("Welche Mahlzeit ist das und welche Nährwerte hat sie ungefähr?"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeObject(w, out)
}

// writeObject übernimmt nur das JSON-Objekt aus der Antwort des Modells.
func writeObject(w http.ResponseWriter, out string) {
	i, j := strings.Index(out, "{"), strings.LastIndex(out, "}")
	var res map[string]any
	if i < 0 || j < i || json.Unmarshal([]byte(out[i:j+1]), &res) != nil {
		http.Error(w, "Antwort nicht verwertbar", http.StatusBadGateway)
		return
	}
	writeJSON(w, res)
}

// aiPlan erstellt ein Trainingsprogramm mit einigen Trainingstagen, die im Wechsel absolviert werden.
func aiPlan(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Wish, Profile, Lang, History string
		Days                         int
	}
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	if req.Days < 1 || req.Days > 7 {
		req.Days = 3
	}
	system := `Du bist ein erfahrener, vorsichtiger Trainer. Erstelle ein 4-Wochen-Trainingsprogramm mit 2 bis 4 unterschiedlichen
Trainingstagen, die reihum absolviert werden. Passe Umfang und Übungen an Profil und Wunsch an, sicher und realistisch.
Antworte ausschließlich mit JSON:
{"name": "kurzer Programmname", "days": [{"title": "Name des Trainingstags", "exercises": ["Übung – Sätze × Wiederholungen", ...]}]}
Sprache: ` + langName(req.Lang) + `.`
	prompt := "Trainingstage pro Woche: " + strconv.Itoa(req.Days) + "\nWunsch: " + req.Wish + "\nProfil: " + req.Profile +
		"\n\nBisheriger Trainingsverlauf mit Rückmeldungen (zu leicht/genau richtig/zu schwer) – Belastung daran anpassen:\n" + req.History
	out, err := ask(r.Context(), system, anthropic.BetaOutputConfigEffortMedium, anthropic.NewBetaTextBlock(prompt))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeObject(w, out)
}

// aiAnalysis erstellt die Kompass-Auswertung über die aktiven Module.
// „local“ enthält die lokal berechneten Kennzahlen der App (z. B. Health-Werte, die nicht auf dem Server liegen).
func aiAnalysis(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Days    int
		Modules []string
		Profile string
		Local   string
		Lang    string
	}
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	if req.Days <= 0 || req.Days > 366 {
		req.Days = 30
	}
	from := time.Now().AddDate(0, 0, -req.Days).Format("2006-01-02")
	var b strings.Builder
	for _, id := range req.Modules {
		m := moduleByID(id)
		if m == nil {
			continue
		}
		es, _ := queryEntries(`user_id=? AND module=? AND deleted=0 AND date>=?`, uid(r), id, from)
		b.WriteString(m.Summary(es))
	}
	system := `Du bist ein freundlicher Gesundheits-Coach in einer Tracking-App. Werte die Daten der letzten Tage aus:
erkenne Muster und Zusammenhänge (z. B. Schlaf und Kalorien), bewerte die Zielerreichung und mache 3–5 konkrete, kleine Vorschläge.
Bleib vorsichtig: keine Diagnosen, keine Medikamente; bei auffälligen Werten Rücksprache mit Ärztin oder Arzt empfehlen.
Schreibe kurz, verständlich, in Markdown, auf ` + langName(req.Lang) + `.`
	prompt := "Zeitraum: letzte " + strconv.Itoa(req.Days) + " Tage\n\nProfil und Ziele:\n" + req.Profile +
		"\n\nDaten vom Server:\n" + b.String() + "\nKennzahlen aus der App:\n" + req.Local
	out, err := ask(r.Context(), system, anthropic.BetaOutputConfigEffortMedium, anthropic.NewBetaTextBlock(prompt))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeJSON(w, map[string]string{"text": out, "disclaimer": disclaimer})
}

func langName(l string) string {
	if strings.HasPrefix(l, "en") {
		return "Englisch"
	}
	return "Deutsch"
}

// aiNext passt die nächste Trainingseinheit an Verlauf und Rückmeldungen an (progressive Steigerung).
func aiNext(w http.ResponseWriter, r *http.Request) {
	var req struct{ Profile, Plan, Session, History, Lang string }
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	system := `Du bist ein erfahrener, vorsichtiger Trainer. Passe die geplante nächste Trainingseinheit an den Verlauf an:
War die letzte Einheit „zu leicht“, steigere moderat (mehr Gewicht, Wiederholungen oder Sätze); bei „zu schwer“ reduziere;
bei „genau richtig“ steigere minimal. Nutze eingetragene Gewichte und Wiederholungen für konkrete Zahlen.
Behalte den Charakter der Einheit bei. Antworte ausschließlich mit JSON:
{"title": "Name der Einheit", "exercises": ["Übung – Sätze × Wiederholungen (ggf. Gewicht)", ...], "note": "ein kurzer Satz, warum so"}
Sprache: ` + langName(req.Lang) + `.`
	prompt := "Profil: " + req.Profile + "\nProgramm: " + req.Plan + "\nGeplante Einheit: " + req.Session + "\n\n" + req.History
	out, err := ask(r.Context(), system, anthropic.BetaOutputConfigEffortMedium, anthropic.NewBetaTextBlock(prompt))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeObject(w, out)
}
