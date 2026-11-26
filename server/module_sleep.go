package main

// Schlaf: eigenes Gefühl (1–5), Dauer und Störungen der letzten Nacht.
var sleep = Module{ID: "sleep", Name: "Schlaf", Symbol: "bed.double.fill", Fields: []Field{
	{"quality", "Schlafqualität", "(1–5)", "avg"},
	{"hours", "Schlafdauer", "h", "avg"},
}}
