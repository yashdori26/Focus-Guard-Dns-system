package auth

import (
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"regexp"
	"strings"
	"sync"
	"time"
)

var (
	ErrInvalidPhone         = errors.New("ERR_INVALID_PHONE_FORMAT")
	ErrRateLimitExceeded    = errors.New("ERR_RATE_LIMIT_EXCEEDED")
	ErrOTPNotFound          = errors.New("ERR_OTP_EXPIRED_OR_NOT_FOUND")
	ErrInvalidOTP           = errors.New("ERR_INVALID_OTP_CODE")
	ErrMaxAttemptsExceeded  = errors.New("ERR_MAX_ATTEMPTS_EXCEEDED")
)

type otpRecord struct {
	code      string
	expiresAt time.Time
	attempts  int
}

type rateLimitRecord struct {
	requestCount int
	windowStart  time.Time
}

// PhoneAuthManager handles rate-limited phone OTP generation and verification.
type PhoneAuthManager struct {
	mu           sync.Mutex
	otps         map[string]*otpRecord
	rateLimits   map[string]*rateLimitRecord
	tokenManager *TokenManager
}

// NewPhoneAuthManager initializes a thread-safe PhoneAuthManager.
func NewPhoneAuthManager(tokenManager *TokenManager) *PhoneAuthManager {
	return &PhoneAuthManager{
		otps:         make(map[string]*otpRecord),
		rateLimits:   make(map[string]*rateLimitRecord),
		tokenManager: tokenManager,
	}
}

// NormalizePhone checks and formats phone number to standard E.164 format.
func NormalizePhone(phone string) (string, error) {
	cleaned := strings.TrimSpace(phone)
	cleaned = strings.ReplaceAll(cleaned, " ", "")
	cleaned = strings.ReplaceAll(cleaned, "-", "")
	cleaned = strings.ReplaceAll(cleaned, "(", "")
	cleaned = strings.ReplaceAll(cleaned, ")", "")

	if !strings.HasPrefix(cleaned, "+") {
		cleaned = "+" + cleaned
	}

	// Validate E.164 pattern: + followed by 7 to 15 digits
	re := regexp.MustCompile(`^\+[1-9]\d{6,14}$`)
	if !re.MatchString(cleaned) {
		return "", ErrInvalidPhone
	}
	return cleaned, nil
}

// SendOTP generates a 6-digit cryptographic OTP for the given phone number with rate limits.
func (pam *PhoneAuthManager) SendOTP(rawPhone string) (string, error) {
	phone, err := NormalizePhone(rawPhone)
	if err != nil {
		return "", err
	}

	pam.mu.Lock()
	defer pam.mu.Unlock()

	now := time.Now()

	// 1. Check rate limit: Max 5 requests per 15-minute window
	rl, exists := pam.rateLimits[phone]
	if !exists || now.Sub(rl.windowStart) > 15*time.Minute {
		pam.rateLimits[phone] = &rateLimitRecord{
			requestCount: 1,
			windowStart:  now,
		}
	} else {
		if rl.requestCount >= 5 {
			return "", ErrRateLimitExceeded
		}
		rl.requestCount++
	}

	// 2. Generate 6-digit cryptographic OTP (100000 to 999999)
	nBig, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return "", fmt.Errorf("failed to generate random OTP: %w", err)
	}
	otpCode := fmt.Sprintf("%06d", nBig.Int64()+100000)

	// 3. Store OTP record (valid for 5 minutes)
	pam.otps[phone] = &otpRecord{
		code:      otpCode,
		expiresAt: now.Add(5 * time.Minute),
		attempts:  0,
	}

	return otpCode, nil
}

// VerifyOTP checks the entered 6-digit OTP code and issues a JWT session token.
func (pam *PhoneAuthManager) VerifyOTP(rawPhone, code string, deviceID string) (string, error) {
	phone, err := NormalizePhone(rawPhone)
	if err != nil {
		return "", err
	}

	cleanCode := strings.TrimSpace(code)
	if len(cleanCode) != 6 {
		return "", ErrInvalidOTP
	}

	pam.mu.Lock()
	defer pam.mu.Unlock()

	record, exists := pam.otps[phone]
	if !exists || time.Now().After(record.expiresAt) {
		delete(pam.otps, phone)
		return "", ErrOTPNotFound
	}

	// Max 3 verification attempts per OTP
	if record.attempts >= 3 {
		delete(pam.otps, phone)
		return "", ErrMaxAttemptsExceeded
	}

	record.attempts++

	if record.code != cleanCode {
		return "", ErrInvalidOTP
	}

	// OTP matched: consume the OTP
	delete(pam.otps, phone)

	// Issue JWT token valid for 30 days
	userID := fmt.Sprintf("usr_phone_%d", time.Now().UnixNano())
	token, err := pam.tokenManager.GenerateToken(userID, phone, deviceID, 30*24*time.Hour)
	if err != nil {
		return "", fmt.Errorf("failed to issue JWT token: %w", err)
	}

	return token, nil
}
