package main

// Stimmung (seelisches Wohlbefinden): Stufe 1–7 wie „Gemütszustand“ in Apple Health, dazu Gefühle und Lebensbereiche.
var mood = Module{ID: "mood", Name: "Stimmung", Symbol: "face.smiling", Fields: []Field{
	{"mood", "Stimmung", "(1–7)", "avg"},
}}
