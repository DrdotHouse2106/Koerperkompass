package main

// Getränke (id bleibt „water“): ein Eintrag pro Getränk, zusätzlich „drink“, „name“, „ml“, „carbs“.
// Ältere Einträge haben nur „ml“.
var water = Module{ID: "water", Name: "Getränke", Symbol: "drop.fill", Fields: []Field{
	{"hydration", "Flüssigkeit", "ml", "sum"},
	{"kcal", "Kalorien aus Getränken", "kcal", "sum"},
	{"caffeine", "Koffein", "mg", "sum"},
	{"alcohol", "Alkohol", "g", "sum"},
}}
