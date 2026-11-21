package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

var (
	ErrTokenExpired = errors.New("jwt token has expired")
	ErrTokenInvalid = errors.New("jwt token signature is invalid")
)

type Claims struct {
	UserID    string `json:"uid"`
	Email     string `json:"email"`
	DeviceID  string `json:"dev_id,omitempty"`
	IssuedAt  int64  `json:"iat"`
	ExpiresAt int64  `json:"exp"`
}

type TokenManager struct {
	secret []byte
}

func NewTokenManager(secret string) *TokenManager {
	return &TokenManager{secret: []byte(secret)}
}

func (tm *TokenManager) GenerateToken(userID, email, deviceID string, ttl time.Duration) (string, error) {
	now := time.Now().Unix()
	claims := Claims{
		UserID:    userID,
		Email:     email,
		DeviceID:  deviceID,
		IssuedAt:  now,
		ExpiresAt: now + int64(ttl.Seconds()),
	}

	headerJSON := `{"alg":"HS256","typ":"JWT"}`
	b64Header := base64.RawURLEncoding.EncodeToString([]byte(headerJSON))

	payloadBytes, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	b64Payload := base64.RawURLEncoding.EncodeToString(payloadBytes)

	signingInput := b64Header + "." + b64Payload
	mac := hmac.New(sha256.New, tm.secret)
	mac.Write([]byte(signingInput))
	signature := mac.Sum(nil)
	b64Sig := base64.RawURLEncoding.EncodeToString(signature)

	return signingInput + "." + b64Sig, nil
}

func (tm *TokenManager) ValidateToken(tokenStr string) (*Claims, error) {
	parts := strings.Split(tokenStr, ".")
	if len(parts) != 3 {
		return nil, ErrTokenInvalid
	}

	signingInput := parts[0] + "." + parts[1]
	expectedSig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return nil, ErrTokenInvalid
	}

	mac := hmac.New(sha256.New, tm.secret)
	mac.Write([]byte(signingInput))
	actualSig := mac.Sum(nil)

	if !hmac.Equal(actualSig, expectedSig) {
		return nil, ErrTokenInvalid
	}

	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, ErrTokenInvalid
	}

	var claims Claims
	if err := json.Unmarshal(payloadBytes, &claims); err != nil {
		return nil, fmt.Errorf("malformed token claims: %w", err)
	}

	if time.Now().Unix() > claims.ExpiresAt {
		return nil, ErrTokenExpired
	}

	return &claims, nil
}
