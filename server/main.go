// Körperkompass-Server: eine Binary, eine SQLite-Datei, keine externen Dienste.
// Konfiguration nur über Umgebungsvariablen (siehe README.md).
package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	_ "modernc.org/sqlite"
)

var (
	db      *sql.DB
	version = "dev" // wird beim Docker-Build gesetzt
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	// Zweite Rolle derselben Binary: zentrales KI-Relais (siehe relay.go)
	if len(os.Args) > 1 && os.Args[1] == "relay" {
		runRelay()
		return
	}
	if len(os.Args) > 1 && os.Args[1] == "relay-key" {
		relayKeyCmd(os.Args[2:])
		return
	}
	var err error
	db, err = sql.Open("sqlite", env("KK_DB", "data/koerperkompass.db")+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)")
	if err != nil {
		log.Fatal(err)
	}
	db.SetMaxOpenConns(1)
	if _, err = db.Exec(schema); err != nil {
		log.Fatal("Datenbank: ", err)
	}
	db.Exec(`ALTER TABLE codes ADD COLUMN name TEXT NOT NULL DEFAULT ''`) // ältere Datenbanken nachrüsten
	migrateAppLog()
	// „Meine Clips“ gibt es nicht mehr: alte Tabelle und Tondateien entfernen
	db.Exec(`DROP TABLE IF EXISTS clips`)
	os.RemoveAll(filepath.Join(filepath.Dir(env("KK_DB", "data/koerperkompass.db")), "clips"))
	migrateUsage()
	migrateMCP()
	go translateAll()                                                      // Übungsbibliothek einmal komplett ins Deutsche übersetzen (nur mit ANTHROPIC_API_KEY)
	db.Exec(`ALTER TABLE users ADD COLUMN vault TEXT NOT NULL DEFAULT ''`) // Ende-zu-Ende-Verschlüsselung
	if err = migrateFriends(); err != nil {
		log.Fatal("Datenbank: ", err)
	}

	// „koerperkompass invite [Name]“ erzeugt einen Kopplungscode für einen neuen Nutzer
	if len(os.Args) > 1 && os.Args[1] == "invite" {
		code, err := newCode(0, strings.Join(os.Args[2:], " "))
		if err != nil {
			log.Fatal(err)
		}
		fmt.Println("Kopplungscode für neuen Nutzer:", code)
		return
	}

	// Beim ersten Start (noch kein Nutzer) einen Kopplungscode erzeugen
	if code := firstStartCode(); code != "" {
		log.Printf("Noch kein Nutzer gekoppelt. Kopplungscode: %s (auch als QR-Code auf der Weboberfläche)", code)
	}
	if aiEnabled() {
		log.Print("Claude API aktiv (Foto-Erkennung und Analyse)")
	} else {
		log.Print("Kein ANTHROPIC_API_KEY gesetzt – nur lokale Auswertung")
	}

	addr := ":" + env("PORT", "8080")
	log.Printf("Körperkompass-Server %s lauscht auf %s", version, addr)
	handler = routes()
	log.Fatal(http.ListenAndServe(addr, handler))
}

const schema = `
CREATE TABLE IF NOT EXISTS users   (id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT '', profile TEXT NOT NULL DEFAULT '{}', created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS tokens  (hash TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, device TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS codes   (code TEXT PRIMARY KEY, user_id INTEGER, expires INTEGER NOT NULL, name TEXT NOT NULL DEFAULT '');
CREATE TABLE IF NOT EXISTS entries (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL, module TEXT NOT NULL, date TEXT NOT NULL,
  data TEXT NOT NULL DEFAULT '{}', updated INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, rev INTEGER NOT NULL,
  PRIMARY KEY (user_id, id));
CREATE INDEX IF NOT EXISTS entries_rev ON entries(user_id, rev);`
