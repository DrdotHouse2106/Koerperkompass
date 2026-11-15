package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"strings"
	"time"
)

// Kopplungscodes: 8 Zeichen ohne verwechselbare Zeichen, einmalig, 24 Stunden gültig.
// user_id 0 = neuer Nutzer, sonst weiteres Gerät desselben Nutzers.
const codeChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func newCode(userID int64) (string, error) {
	b := make([]byte, 8)
	rand.Read(b)
	for i := range b {
		b[i] = codeChars[int(b[i])%len(codeChars)]
	}
	code := string(b[:4]) + "-" + string(b[4:])
	_, err := db.Exec(`INSERT INTO codes(code, user_id, expires) VALUES(?,?,?)`, code, userID, time.Now().Add(24*time.Hour).Unix())
	return code, err
}

// firstStartCode liefert einen gültigen Code, solange noch kein Nutzer existiert.
func firstStartCode() string {
	var n int
	db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&n)
	if n > 0 {
		return ""
	}
	var code string
	if db.QueryRow(`SELECT code FROM codes WHERE user_id=0 AND expires>?`, time.Now().Unix()).Scan(&code) == nil {
		return code
	}
	code, _ = newCode(0)
	return code
}

func hashToken(t string) string {
	h := sha256.Sum256([]byte(t))
	return hex.EncodeToString(h[:])
}

// pair löst einen Kopplungscode ein und gibt ein Token zurück.
func pair(code, name, device string) (token string, userID int64, err error) {
	code = strings.ToUpper(strings.TrimSpace(code))
	tx, err := db.Begin()
	if err != nil {
		return
	}
	defer tx.Rollback()
	if err = tx.QueryRow(`DELETE FROM codes WHERE code=? AND expires>? RETURNING user_id`, code, time.Now().Unix()).Scan(&userID); err != nil {
		return
	}
	now := time.Now().Unix()
	if userID == 0 {
		res, e := tx.Exec(`INSERT INTO users(name, created) VALUES(?,?)`, name, now)
		if e != nil {
			return "", 0, e
		}
		userID, _ = res.LastInsertId()
	}
	b := make([]byte, 32)
	rand.Read(b)
	token = hex.EncodeToString(b)
	if _, err = tx.Exec(`INSERT INTO tokens(hash, user_id, device, created) VALUES(?,?,?,?)`, hashToken(token), userID, device, now); err != nil {
		return
	}
	return token, userID, tx.Commit()
}

type ctxKey struct{}

// auth prüft das Bearer-Token und legt die Nutzer-ID im Kontext ab.
func auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var userID int64
		t := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if t == "" || db.QueryRow(`SELECT user_id FROM tokens WHERE hash=?`, hashToken(t)).Scan(&userID) != nil {
			http.Error(w, "nicht gekoppelt", http.StatusUnauthorized)
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, userID)))
	}
}

func uid(r *http.Request) int64 { return r.Context().Value(ctxKey{}).(int64) }
