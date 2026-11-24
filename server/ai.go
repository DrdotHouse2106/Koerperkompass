package main

import (
	"context"
	_ "embed"
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
	return askMessages(ctx, system, effort, []anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(content...)})
}

// askMessages führt ein Gespräch mit mehreren Nachrichten (z. B. für den Coach).
func askMessages(ctx context.Context, system string, effort anthropic.BetaOutputConfigEffort, messages []anthropic.BetaMessageParam) (string, error) {
	return askModel(ctx, env("KK_MODEL", "claude-opus-5-5"), system, effort, messages)
}

// askModel ruft ein bestimmtes Modell auf. Für Opus/Sonnet/Fable ist der serverseitige Fallback bei Ablehnung aktiv;
// Haiku hat keinen solchen Fallback.
func askModel(ctx context.Context, model, system string, effort anthropic.BetaOutputConfigEffort, messages []anthropic.BetaMessageParam) (string, error) {
	client := anthropic.NewClient() // liest ANTHROPIC_API_KEY
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	params := anthropic.BetaMessageNewParams{
		Model:        anthropic.Model(model),
		MaxTokens:    16000,
		System:       []anthropic.BetaTextBlockParam{{Text: system}},
		OutputConfig: anthropic.BetaOutputConfigParam{Effort: effort},
		Messages:     messages,
	}
	if !strings.Contains(model, "haiku") {
		params.Fallbacks = anthropic.BetaFallbacksParamOfDefault()
		params.Betas = []anthropic.AnthropicBeta{anthropic.AnthropicBetaServerSideFallback2026_07_01}
	}
	msg, err := client.Beta.Messages.New(ctx, params)
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
Nutze nur Geräte, die laut Profil vorhanden sind (bei „keine“ nur Übungen mit dem eigenen Körpergewicht) und beachte, was über die Person bekannt ist (z. B. Beschwerden, Zeit, Vorlieben).
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
Behalte den Charakter der Einheit bei. Nutze nur Geräte, die laut Profil vorhanden sind (bei „keine“ nur Übungen mit dem eigenen Körpergewicht) und beachte, was über die Person bekannt ist (z. B. Beschwerden, Zeit, Vorlieben).
Antworte ausschließlich mit JSON:
{"title": "Name der Einheit", "exercises": ["Übung – Sätze × Wiederholungen (ggf. Gewicht)", ...], "note": "ein kurzer Satz, warum so"}
Sprache: ` + langName(req.Lang) + `.`
	prompt := "Profil: " + req.Profile + "\nProgramm: " + req.Plan + "\nGeplante Einheit: " + req.Session + "\n\n" + req.History
	// kleines Modell: Ersatz für Apple Intelligence auf älteren iPhones, kostet Bruchteile eines Cents
	out, err := askModel(r.Context(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
		[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(prompt))})
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeObject(w, out)
}

// aiCoach: Gesundheitscoach im Gespräch. „context“ ist die von der App erstellte Zusammenfassung der eigenen Daten.
func aiCoach(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Messages []struct{ Role, Content string }
		Context  string
		Lang     string
		Voice    bool // Gesprächsmodus: Antwort wird vorgelesen, danach antwortet die Person per Sprache
	}
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	if len(req.Messages) > 30 {
		req.Messages = req.Messages[len(req.Messages)-30:]
	}
	var msgs []anthropic.BetaMessageParam
	for _, m := range req.Messages {
		block := anthropic.NewBetaTextBlock(m.Content)
		if m.Role == "assistant" {
			if len(msgs) == 0 {
				continue // Gespräch muss mit dem Nutzer beginnen
			}
			msgs = append(msgs, anthropic.BetaMessageParam{OfAssistant: &anthropic.BetaAssistantMessageParam{Content: []anthropic.BetaContentBlockParamUnion{block}}})
		} else {
			msgs = append(msgs, anthropic.NewBetaUserMessage(block))
		}
	}
	if len(msgs) == 0 {
		http.Error(w, "keine Nachricht", http.StatusBadRequest)
		return
	}
	system := `Du bist der persönliche Gesundheitscoach in der App „Körperkompass“: warmherzig, motivierend, ehrlich und konkret.
Du kennst die aktuellen Daten der Person (unten). Beziehe dich darauf mit konkreten Zahlen, gib praktische, kleine nächste Schritte
(Essen, Trinken, Bewegung, Training, Schlaf, Erholung) und frag nach, wenn etwas unklar ist. Antworte kurz (meist 3–8 Sätze oder eine
knappe Liste), in Markdown, auf ` + langName(req.Lang) + `, per Du.
Grenzen: keine Diagnosen, keine Medikamente oder Nahrungsergänzungs-Dosierungen, keine Crash-Diäten. Bei Schmerzen, Schwindel,
Essstörungs-Anzeichen oder auffälligen Werten empfiehl freundlich ärztlichen Rat. Du ersetzt keine ärztliche Beratung.
Empfiehl nur Geräte, die laut Profil vorhanden sind (bei „keine“ nur Körpergewicht).
Zeiten: Richte jede Empfehlung mit Zeitbezug (Essen, Training, Spaziergang, Schlaf) nach Wochentag, Uhrzeit und dem Tagesablauf im Profil.
Schlag nichts vor, was mit Arbeitszeiten oder festen Terminen kollidiert. Ist der Tagesablauf unbekannt oder unklar, frag kurz nach,
statt Uhrzeiten vorzugeben (z. B. „Wann arbeitest du heute noch?“).
Steht eine eigene Rezeptsammlung in den Daten, schlag beim Thema Essen gern passende Rezepte daraus vor (mit Blick auf übrige Kalorien und Eiweiß).

Lerne die Person kennen: Fehlt dir etwas Wichtiges für gute Empfehlungen (z. B. Trainingsgeräte, Beschwerden oder Verletzungen,
verfügbare Zeit, Vorlieben, Alltag), stell gelegentlich genau eine kurze Frage dazu – nicht in jeder Antwort.
Erfährst du etwas Dauerhaftes, das für Training oder Ernährung wichtig ist und noch nicht bekannt ist, hänge ganz am Ende eigene Zeilen an:
MERKEN: kurze Tatsache in der dritten Person; weitere Tatsache
GERÄTE: vollständige Liste aus dumbbells, barbell, kettlebell, bands, pullupbar, bench, bike, treadmill, rope, gym – oder keine
ALLTAG: vollständige, aktualisierte Beschreibung des Tagesablaufs (Arbeitszeiten je Wochentag, feste Termine wie Sport oder Spaziergänge,
Essens- und Schlafenszeiten) – nur, wenn du dazu etwas Neues erfährst; bisherige Angaben übernehmen, nichts erfinden.
Die GERÄTE-Zeile nur, wenn sich am Gerätebestand etwas geändert hat. Nichts Gesundheitliches erfinden oder deuten, nur Gesagtes merken.

Einträge vorschlagen: Erzählt die Person, was sie tatsächlich gegessen oder getrunken hat, was sie heute wiegt, wie sie sich fühlt
oder welche Beschwerden bzw. Krankheitssymptome sie hat (nicht bei Fragen, Plänen oder Überlegungen), hänge ganz am Ende eine einzige Zeile an (JSON in einer Zeile, die App fragt vor dem Speichern nach):
EINTRAGEN: {"day": 0, "items": [{"meal": "breakfast|lunch|dinner|snack", "name": "kurz", "amount": "Menge", "kcal": Zahl, "protein": g, "carbs": g, "fat": g}], "weight": kg, "mood": {"level": 1-7, "feelings": [], "areas": []}, "symptoms": [{"symptom": "id", "severity": 1-3}]}
day: 0 = heute, -1 = gestern. Bei Getränken in items zusätzlich "ml", "caffeine" (mg), "alcohol" (g). Ist eine Uhrzeit genannt oder ableitbar, "time": "HH:MM". weight nur, wenn genannt.
Nur die genannten Teile angeben, weglassen was nicht vorkommt.
mood: 1 = sehr unangenehm … 7 = sehr angenehm; feelings aus happy, content, calm, grateful, proud, confident, excited, hopeful, relieved,
drained, stressed, overwhelmed, anxious, worried, irritated, frustrated, sad, lonely, indifferent; areas aus work, family, partner, friends,
health, fitness, selfCare, hobbies, money, tasks, weather, travel.
symptoms: symptom aus sinusCongestion (verstopfte Nase), runnyNose, soreThroat, coughing, headache, fever, chills, fatigue,
bodyAndMuscleAches, lowerBackPain, nausea, diarrhea, dizziness, shortnessOfBreath, lossOfSmell, sleepChanges; severity 1 leicht, 2 mittel, 3 stark.
Beschwerden, die heute schon eingetragen sind, nicht erneut vorschlagen.
Beschwerden berücksichtigen: Bei Erkältung oberhalb des Halses (Nase, leichter Hals) höchstens lockere Bewegung; bei Fieber, Gliederschmerzen,
Husten mit Brustbeschwerden oder Atemnot kein Training, sondern Ruhe und Trinken. Keine Diagnosen. Bei starken, mehr als etwa
einer Woche anhaltenden Beschwerden, hohem Fieber oder Atemnot zum Arztbesuch raten.
Realistische Nährwerte für deutsche Portionen schätzen. Nichts eintragen, was schon in den heutigen Daten steht.

Nachrichten mit Datum in eckigen Klammern stammen von früheren Tagen – was dort gegessen, getrunken oder trainiert
wurde, gehört NICHT zu heute. Für heute zählen ausschließlich die folgenden Daten.

Aktuelle Daten der Person (Stand heute):
` + req.Context
	if req.Voice {
		system += "\n\nGESPRÄCHSMODUS: Deine Antwort wird vorgelesen und die Person antwortet gleich per Sprache. Sprich natürlich wie im Gespräch: " +
			"2–4 kurze Sätze, keine Listen, keine Überschriften, kein Markdown, keine Emojis. Höchstens eine Frage am Ende. " +
			"Die Zeilen MERKEN, ALLTAG, GERÄTE und EINTRAGEN darfst du weiterhin anhängen."
	}
	out, err := askMessages(r.Context(), system, anthropic.BetaOutputConfigEffortMedium, msgs)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	// MERKEN-/GERÄTE-Zeilen herauslösen – die App speichert sie im Profil
	res := map[string]any{}
	var text, learn []string
	for _, line := range strings.Split(out, "\n") {
		t := strings.TrimSpace(strings.Trim(strings.TrimSpace(line), "*_"))
		switch {
		case strings.HasPrefix(t, "MERKEN:"):
			for _, f := range strings.Split(strings.TrimPrefix(t, "MERKEN:"), ";") {
				if f = strings.TrimSpace(f); f != "" {
					learn = append(learn, f)
				}
			}
		case strings.HasPrefix(t, "ALLTAG:"):
			res["routine"] = strings.TrimSpace(strings.TrimPrefix(t, "ALLTAG:"))
		case strings.HasPrefix(t, "EINTRAGEN:"):
			var log map[string]any
			if json.Unmarshal([]byte(strings.TrimSpace(strings.TrimPrefix(t, "EINTRAGEN:"))), &log) == nil {
				res["log"] = log
			}
		case strings.HasPrefix(t, "GERÄTE:"):
			eq := []string{}
			for _, g := range strings.Split(strings.TrimPrefix(t, "GERÄTE:"), ",") {
				if g = strings.ToLower(strings.TrimSpace(g)); g != "" && g != "keine" {
					eq = append(eq, g)
				}
			}
			res["equipment"] = eq
		default:
			text = append(text, line)
		}
	}
	res["text"] = strings.TrimSpace(strings.Join(text, "\n"))
	if len(learn) > 0 {
		res["learn"] = learn
	}
	writeJSON(w, res)
}

// aiMotivation erzeugt kurze, persönliche Motivationssprüche für die nächsten Erinnerungen.
// Bewusst mit dem günstigen kleinen Modell (KK_MODEL_SMALL, Standard Claude Haiku 5.5) und wenig Aufwand.
//
//go:embed dark_style.md
var darkStyle string

func aiMotivation(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Context, Lang, Style string
		Count                int
	}
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	if req.Count < 1 || req.Count > 6 {
		req.Count = 2
	}
	if req.Style == "dark" {
		if req.Lang != "en" && req.Lang != "mix" {
			req.Lang = "de"
		}
		// „Dark Motivation“: kurze, ernste Geschichten nach der Stilvorlage (dark_style.md)
		system := darkStyle + `

Schreibe eigene Geschichten in diesem Stil. Antworte ausschließlich mit JSON:
{"stories": [{"lang": "de|en", "inner": true|false, "lines": ["Zeile", "…"]}]}  (inner = Form „innere Stimme“; Formen abwechseln)
Sprache: ` + map[string]string{"de": "Deutsch", "en": "Englisch", "mix": "abwechselnd Deutsch und Englisch"}[req.Lang] + `.`
		prompt := "Schreibe " + strconv.Itoa(req.Count) + " verschiedene Geschichten. Greife, wo es passt, den Weg der Person auf:\n" + req.Context
		out, err := askModel(r.Context(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
			[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(prompt))})
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		writeObject(w, out)
		return
	}
	system := `Du schreibst kurze, motivierende Push-Mitteilungen für eine Gesundheits-App. Jede höchstens 140 Zeichen, per Du,
warm, konkret auf die Daten der Person bezogen (Serie, Ziel, Training, Trinken, Essen), abwechslungsreich, gern mit einem Emoji,
nie belehrend, keine Diagnosen. Regeln: fehlerfreies, natürliches Deutsch; keine Kalorien- oder Grammzahlen und keine Rechnungen; niemals wenig Essen, Auslassen von Mahlzeiten oder Hungern loben; Essdaten können unvollständig sein – nicht danach bewerten. Lieber Serie, Ziel, Training, Trinken, Durchhalten und kleine nächste Schritte.
Antworte ausschließlich mit JSON: {"messages": ["…", "…"]}. Sprache: ` + langName(req.Lang) + `.`
	prompt := "Schreibe " + strconv.Itoa(req.Count) + " verschiedene Mitteilungen (morgens zuerst).\n\nDaten:\n" + req.Context
	out, err := askModel(r.Context(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
		[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(prompt))})
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeObject(w, out)
}

// aiVoice: ein Wortwechsel mit dem Trainings-Coach (Ersatz für Apple Intelligence auf älteren iPhones, kleines Modell).
func aiVoice(w http.ResponseWriter, r *http.Request) {
	var req struct{ Style, Plan, Profile, History, Text string }
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	system := req.Style + ` Du begleitest ein Training per Sprache. Antworte sehr kurz (1–2 Sätze, wird vorgelesen), per Du, auf Deutsch,
ohne Emojis. Erkenne aus der Meldung Übung, Wiederholungen und Gewicht und empfiehl die Pause (60–180 Sekunden). Bei Schmerzen: abbrechen lassen.
Heutige Einheit: ` + req.Plan + `. Profil: ` + req.Profile + `
Antworte ausschließlich mit JSON: {"reply": "…", "exercise": "Übung oder leer", "reps": Zahl, "weight": kg oder 0, "restSeconds": Zahl oder 0}`
	prompt := "Bisher:\n" + req.History + "\n\nNeue Meldung: " + req.Text
	out, err := askModel(r.Context(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
		[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(anthropic.NewBetaTextBlock(prompt))})
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeObject(w, out)
}

// aiMeal zerlegt eine freie Beschreibung („Mein Frühstück waren 2 Berliner“) in Lebensmittel mit Nährwerten.
// Kleines, günstiges Modell (KK_MODEL_SMALL, Standard Claude Haiku 5.5).
func aiMeal(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Text, Lang, Hint, History, Now, Image string   // Image: optional JPEG (Base64) vom Teller oder der Packung
		Images                                []string // mehrere Fotos (z. B. Teller und Packungen) – zusammen ausgewertet
	}
	if !requireAI(w) || !readJSON(w, r, &req) {
		return
	}
	if req.Image != "" {
		req.Images = append(req.Images, req.Image)
	}
	size := 0
	for _, img := range req.Images {
		size += len(img)
	}
	if (strings.TrimSpace(req.Text) == "" && len(req.Images) == 0) || len(req.Text) > 2000 || len(req.Images) > 6 || size > 12<<20 {
		http.Error(w, "Beschreibung fehlt oder ist zu lang", http.StatusBadRequest)
		return
	}
	system := `Du zerlegst Essensbeschreibungen in einzelne Lebensmittel mit realistischen Nährwerten für die genannte bzw. eine übliche Menge
(deutsche Lebensmittel und Portionsgrößen, z. B. ein Berliner ≈ 70 g ≈ 250 kcal). Alle Getränke gehören dazu (auch Wasser, Kaffee, Bier).
Erkenne die Mahlzeit jedes Lebensmittels aus dem Text (Frühstück → breakfast, Mittag → lunch, Abend → dinner, Snack/Zwischendurch → snack),
sonst nutze den Hinweis. Eine Beschreibung kann mehrere Mahlzeiten enthalten. Saucen und Beilagen sind eigene Einträge.
Bezieht sich die Beschreibung auf frühere Mahlzeiten (z. B. „das Gleiche wie gestern“, „wie heute Mittag“, „nochmal den Toast“),
übernimm die passenden Lebensmittel mit Mengen und Nährwerten aus dem Verlauf und ordne sie der genannten Mahlzeit zu.
Fehlt dir dafür der Verlauf, antworte nur mit {"needHistory": true}. Ist die Beschreibung so unklar, dass du raten müsstest
(z. B. welches von mehreren Gerichten gemeint ist), antworte nur mit {"question": "kurze Rückfrage"} – sonst schätze üblich.
Antworte ausschließlich mit JSON:
{"items": [{"meal": "breakfast|lunch|dinner|snack", "name": "kurze Bezeichnung", "amount": "Menge, z. B. 2 Stück (140 g)", "kcal": Zahl, "protein": g, "carbs": g, "fat": g}]}
Bei Getränken (auch Wasser, Kaffee, Bier) zusätzlich "ml": Menge in ml (z. B. 330 für ein 0,33er), "caffeine": mg, "alcohol": Gramm reiner Alkohol.
Wenn eine Uhrzeit genannt oder klar ableitbar ist („um 10“, „nach dem Aufstehen“, „vorhin“ = vor etwa einer Stunde), zusätzlich "time": "HH:MM" (24 Stunden), sonst weglassen.
Bezeichnungen in ` + langName(req.Lang) + `.`
	prompt := "Jetzt: " + req.Now + " Uhr\nHinweis auf die Mahlzeit (nach Uhrzeit): " + req.Hint + "\nBeschreibung: " + req.Text
	if h := strings.TrimSpace(req.History); h != "" {
		prompt = "Bisherige Mahlzeiten:\n" + truncate(h, 6000) + "\n\n" + prompt
	} else {
		prompt = "(Verlauf nicht mitgeschickt – bei Bedarf mit needHistory anfordern.)\n" + prompt
	}
	blocks := []anthropic.BetaContentBlockParamUnion{anthropic.NewBetaTextBlock(prompt)}
	if len(req.Images) > 0 {
		// Fotos: Teller → Lebensmittel und Mengen schätzen; Packung/Nährwerttabelle → Werte pro 100 g ablesen
		// und auf die beschriebene Menge umrechnen (z. B. „halbe Packung“). Mehrere Fotos = mehrere Zutaten einer Mahlzeit.
		blocks = nil
		for _, img := range req.Images {
			blocks = append(blocks, anthropic.NewBetaImageBlock(anthropic.BetaBase64ImageSourceParam{Data: img, MediaType: anthropic.BetaBase64ImageSourceMediaTypeImageJPEG}))
		}
		blocks = append(blocks, anthropic.NewBetaTextBlock(prompt+"\nZu den Fotos: Zeigt eines einen Teller, erkenne die einzelnen Lebensmittel und schätze die Mengen. "+
			"Zeigt eines eine Verpackung oder Nährwerttabelle, lies Produkt, Packungsgröße und Werte pro 100 g ab und rechne auf die beschriebene Menge um "+
			"(ohne Angabe: die ganze Packung bzw. eine übliche Portion; nenne die Menge in amount). Mehrere Fotos gehören zusammen – "+
			"ein Eintrag je Lebensmittel, nichts doppelt zählen (z. B. Packung und Teller mit demselben Produkt)."))
	}
	out, err := askModel(r.Context(), env("KK_MODEL_SMALL", "claude-haiku-5-5"), system, anthropic.BetaOutputConfigEffortLow,
		[]anthropic.BetaMessageParam{anthropic.NewBetaUserMessage(blocks...)})
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeObject(w, out)
}
