package main

// Aktivität und Schlaf aus Apple Health: ein Eintrag pro Tag (id „activity-JJJJ-MM-TT“).
var activity = Module{ID: "activity", Name: "Aktivität & Schlaf", Symbol: "figure.walk", Fields: []Field{
	{"steps", "Schritte", "", "avg"},
	{"activeEnergy", "Aktive Energie", "kcal", "avg"},
	{"sleepHours", "Schlaf", "h", "avg"},
	{"restingHR", "Ruhepuls", "bpm", "avg"},
	{"workoutMinutes", "Training", "min", "avg"},
}}
