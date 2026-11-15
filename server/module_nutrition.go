package main

// Ernährung: ein Eintrag pro Lebensmittel/Mahlzeit; zusätzlich „meal“, „name“ und optional „photo“ (JPEG, Base64).
var nutrition = Module{ID: "nutrition", Name: "Ernährung", Symbol: "fork.knife", Fields: []Field{
	{"kcal", "Energie", "kcal", "sum"},
	{"protein", "Eiweiß", "g", "sum"},
	{"carbs", "Kohlenhydrate", "g", "sum"},
	{"fat", "Fett", "g", "sum"},
}}
