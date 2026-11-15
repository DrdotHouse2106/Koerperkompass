package main

// Gewicht und Körpermaße: ein Eintrag pro Messung, nicht gemessene Felder bleiben leer.
var body = Module{ID: "body", Name: "Gewicht & Maße", Symbol: "scalemass", Fields: []Field{
	{"weight", "Gewicht", "kg", "last"},
	{"bodyFat", "Körperfett", "%", "last"},
	{"waist", "Taille", "cm", "last"},
	{"hip", "Hüfte", "cm", "last"},
	{"chest", "Brust", "cm", "last"},
}}
