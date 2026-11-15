package main

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// Module beschreibt ein Modul – dasselbe Schema wie in der App (app/Koerperkompass/Modules).
// Neues Modul: Datei module_<id>.go anlegen und in der Liste unten eintragen.
type Module struct {
	ID     string  `json:"id"`
	Name   string  `json:"name"`
	Symbol string  `json:"symbol"` // SF-Symbol in der App
	Fields []Field `json:"fields"`
}

// Field ist ein Zahlenfeld eines Moduls. Agg legt fest, wie es zusammengefasst wird:
// "sum"  = pro Tag addieren, dann Tagesdurchschnitt (z. B. Kalorien),
// "avg"  = Durchschnitt aller Werte (z. B. Ruhepuls),
// "last" = Verlauf erster → letzter Wert (z. B. Gewicht).
type Field struct {
	Key  string `json:"key"`
	Name string `json:"name"`
	Unit string `json:"unit"`
	Agg  string `json:"agg"`
}

// modules: die Liste aller Module. Reihenfolge = Reihenfolge in der Analyse.
var modules = []Module{quests, nutrition, body, activity, water, training}

func moduleByID(id string) *Module {
	for i := range modules {
		if modules[i].ID == id {
			return &modules[i]
		}
	}
	return nil
}

// Summary fasst die Einträge eines Moduls als kurzen Text für die Analyse zusammen.
func (m Module) Summary(es []Entry) string {
	sort.Slice(es, func(i, j int) bool { return es[i].Date < es[j].Date })
	days := map[string]bool{}
	var b strings.Builder
	for _, f := range m.Fields {
		var vals []float64
		perDay := map[string]float64{}
		for _, e := range es {
			var d map[string]any
			json.Unmarshal(e.Data, &d)
			if v, ok := d[f.Key].(float64); ok {
				vals = append(vals, v)
				perDay[e.Date] += v
				days[e.Date] = true
			}
		}
		if len(vals) == 0 {
			continue
		}
		switch f.Agg {
		case "sum":
			sum := 0.0
			for _, v := range perDay {
				sum += v
			}
			fmt.Fprintf(&b, "- %s: Ø %.1f %s pro erfasstem Tag (%d Tage)\n", f.Name, sum/float64(len(perDay)), f.Unit, len(perDay))
		case "avg":
			sum := 0.0
			for _, v := range vals {
				sum += v
			}
			fmt.Fprintf(&b, "- %s: Ø %.1f %s (%d Werte)\n", f.Name, sum/float64(len(vals)), f.Unit, len(vals))
		default:
			fmt.Fprintf(&b, "- %s: %.1f → %.1f %s (%d Messungen)\n", f.Name, vals[0], vals[len(vals)-1], f.Unit, len(vals))
		}
	}
	if b.Len() == 0 {
		return ""
	}
	return fmt.Sprintf("%s (%d Tage mit Daten):\n%s", m.Name, len(days), b.String())
}
