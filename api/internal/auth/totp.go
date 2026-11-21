package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"strings"
	"time"
)

const (
	TOTPPeriod = 30 // 30 seconds interval
	TOTPDigits = 6
)

// GenerateTOTPSecret generates a cryptographically secure random base32 TOTP secret.
func GenerateTOTPSecret() (string, error) {
	bytes := make([]byte, 20)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(bytes), nil
}

// GenerateTOTPCode generates a 6-digit TOTP code for the given secret and timestamp.
func GenerateTOTPCode(secretBase32 string, timestamp int64) (string, error) {
	secretBytes, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(strings.ToUpper(strings.TrimSpace(secretBase32)))
	if err != nil {
		return "", fmt.Errorf("invalid base32 secret: %w", err)
	}

	counter := uint64(timestamp / TOTPPeriod)
	buf := make([]byte, 8)
	binary.BigEndian.PutUint64(buf, counter)

	mac := hmac.New(sha1.New, secretBytes)
	mac.Write(buf)
	hash := mac.Sum(nil)

	offset := hash[len(hash)-1] & 0x0f
	truncated := binary.BigEndian.Uint32(hash[offset : offset+4])
	truncated &= 0x7fffffff

	code := truncated % 1000000
	return fmt.Sprintf("%06d", code), nil
}

// VerifyTOTPCode verifies a 6-digit TOTP code against a secret, allowing +-1 interval clock drift.
func VerifyTOTPCode(secretBase32, candidateCode string, nowEpochSec int64) bool {
	candidate := strings.TrimSpace(candidateCode)
	if len(candidate) != TOTPDigits {
		return false
	}

	// Check intervals: t-1, t, t+1 (drift allowance of 30 seconds)
	intervals := []int64{
		nowEpochSec - TOTPPeriod,
		nowEpochSec,
		nowEpochSec + TOTPPeriod,
	}

	for _, ts := range intervals {
		expected, err := GenerateTOTPCode(secretBase32, ts)
		if err == nil && expected == candidate {
			return true
		}
	}
	return false
}

// GenerateOTPAuthURL creates a standard otpauth URI for QR code scanning in Google/Apple Authenticator.
func GenerateOTPAuthURL(email, secretBase32, issuer string) string {
	if issuer == "" {
		issuer = "FocusDNS"
	}
	label := fmt.Sprintf("%s:%s", issuer, email)
	u := url.URL{
		Scheme: "otpauth",
		Host:   "totp",
		Path:   "/" + label,
	}
	q := u.Query()
	q.Set("secret", secretBase32)
	q.Set("issuer", issuer)
	q.Set("period", fmt.Sprintf("%d", TOTPPeriod))
	q.Set("digits", fmt.Sprintf("%d", TOTPDigits))
	q.Set("algorithm", "SHA1")
	u.RawQuery = q.Encode()

	return u.String()
}
