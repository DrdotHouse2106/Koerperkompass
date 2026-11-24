package main

// Beschwerden und Krankheitssymptome (verstopfte Nase, Husten, Fieber …): ein Eintrag pro Symptom mit Stärke 1–3.
var symptoms = Module{ID: "symptoms", Name: "Beschwerden", Symbol: "cross.case.fill", Fields: []Field{
	{"severity", "Stärke", "(1–3)", "avg"},
}}
