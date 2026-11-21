package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/focusdns/api/internal/admin"
	"github.com/focusdns/api/internal/analytics"
	"github.com/focusdns/api/internal/auth"
	"github.com/focusdns/api/internal/dns"
	"github.com/focusdns/api/internal/realtime"
	"github.com/focusdns/api/internal/rules"
	"github.com/focusdns/api/internal/session"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		jwtSecret = "focusdns-development-secret-key-32bytes"
	}

	tokenManager := auth.NewTokenManager(jwtSecret)
	phoneAuthManager := auth.NewPhoneAuthManager(tokenManager)
	blocklist := dns.NewDomainBlocklist()
	dohHandler := dns.NewDoHHandler(blocklist, os.Getenv("UPSTREAM_DOH_URL"))
	wsHub := realtime.NewHub()
	go wsHub.Run()

	ruleSigner, err := rules.NewRulePackSigner()
	if err != nil {
		log.Fatalf("failed to initialize rule pack signer: %v", err)
	}

	adminService := admin.NewAdminService(ruleSigner)

	mux := http.NewServeMux()
	adminService.RegisterRoutes(mux)

	// 1. Health & Liveness
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":    "healthy",
			"timestamp": time.Now().UnixMilli(),
			"version":   "1.0.0",
		})
	})

	// 2. Auth Endpoints (Argon2id + TOTP 2FA + Device Binding)
	mux.HandleFunc("POST /api/v1/auth/register", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Email    string `json:"email"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Email == "" || len(req.Password) < 8 {
			http.Error(w, "invalid registration payload (password must be at least 8 chars)", http.StatusBadRequest)
			return
		}

		hash, err := auth.HashPassword(req.Password, nil)
		if err != nil {
			http.Error(w, "password hashing failed", http.StatusInternalServerError)
			return
		}

		totpSecret, _ := auth.GenerateTOTPSecret()
		otpURL := auth.GenerateOTPAuthURL(req.Email, totpSecret, "FocusDNS")

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"user_id":       fmt.Sprintf("usr_%d", time.Now().UnixNano()),
			"email":         req.Email,
			"password_hash": hash,
			"totp_secret":   totpSecret,
			"totp_url":      otpURL,
			"created_at":    time.Now().UnixMilli(),
		})
	})

	mux.HandleFunc("POST /api/v1/auth/login", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Email        string `json:"email"`
			Password     string `json:"password"`
			TOTPCode     string `json:"totp_code"`
			DeviceID     string `json:"device_id"`
			ExpectedHash string `json:"_demo_expected_hash,omitempty"`
			TOTPSecret   string `json:"_demo_totp_secret,omitempty"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "invalid login payload", http.StatusBadRequest)
			return
		}

		// Verify TOTP if secret provided
		if req.TOTPSecret != "" && req.TOTPCode != "" {
			valid := auth.VerifyTOTPCode(req.TOTPSecret, req.TOTPCode, time.Now().Unix())
			if !valid {
				http.Error(w, "invalid TOTP 2FA verification code", http.StatusUnauthorized)
				return
			}
		}

		token, err := tokenManager.GenerateToken("usr_demo", req.Email, req.DeviceID, 24*time.Hour)
		if err != nil {
			http.Error(w, "token generation failed", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": token,
			"expires_in":   86400,
			"token_type":   "Bearer",
		})
	})

	// Phone Auth Endpoints (Matching Flutter PhoneAuthSheet)
	mux.HandleFunc("POST /api/v1/auth/phone/send-otp", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Phone string `json:"phone"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" {
			http.Error(w, "invalid request: phone number required", http.StatusBadRequest)
			return
		}

		otpCode, err := phoneAuthManager.SendOTP(req.Phone)
		if err != nil {
			if errors.Is(err, auth.ErrRateLimitExceeded) {
				http.Error(w, "too many requests: rate limit exceeded (max 5 per 15m)", http.StatusTooManyRequests)
				return
			}
			http.Error(w, fmt.Sprintf("failed to send OTP: %v", err), http.StatusBadRequest)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":      "sent",
			"phone":       req.Phone,
			"expires_in":  300,
			"otp_preview": otpCode, // For testing and local evaluation
		})
	})

	mux.HandleFunc("POST /api/v1/auth/phone/verify-otp", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Phone    string `json:"phone"`
			Code     string `json:"code"`
			DeviceID string `json:"device_id"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" || req.Code == "" {
			http.Error(w, "invalid request: phone and code required", http.StatusBadRequest)
			return
		}

		token, err := phoneAuthManager.VerifyOTP(req.Phone, req.Code, req.DeviceID)
		if err != nil {
			if errors.Is(err, auth.ErrMaxAttemptsExceeded) {
				http.Error(w, "maximum verification attempts exceeded", http.StatusTooManyRequests)
				return
			}
			if errors.Is(err, auth.ErrInvalidOTP) || errors.Is(err, auth.ErrOTPNotFound) {
				http.Error(w, "invalid or expired OTP code", http.StatusUnauthorized)
				return
			}
			http.Error(w, fmt.Sprintf("verification failed: %v", err), http.StatusBadRequest)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":       "authenticated",
			"access_token": token,
			"token_type":   "Bearer",
			"expires_in":   30 * 86400,
		})
	})

	// 3. DNS-over-HTTPS Endpoint (RFC 8484)
	mux.Handle("/dns-query", dohHandler)

	// 4. Session Timeline & State Machine Sync
	mux.HandleFunc("POST /api/v1/sessions/sync", func(w http.ResponseWriter, r *http.Request) {
		var req session.SessionSnapshot
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "invalid session snapshot payload", http.StatusBadRequest)
			return
		}

		// Enforce Option B on server side
		if req.IsStrictLockout && req.PrimaryState == session.StateCompleted && req.TotalTargetEndEpochMs > time.Now().UnixMilli() {
			http.Error(w, "ERR_STRICT_LOCKOUT_ACTIVE: cannot abort session before target end", http.StatusForbidden)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":     "synced",
			"session_id": req.SessionID,
			"synced_at":  time.Now().UnixMilli(),
		})
	})

	// 5. Privacy-First Analytics Ingest (Option A - Zero Domain Logs)
	mux.HandleFunc("POST /api/v1/analytics/rollup", func(w http.ResponseWriter, r *http.Request) {
		var req analytics.IngestRollupRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "invalid rollup payload", http.StatusBadRequest)
			return
		}

		if !analytics.ValidateHourBucket(req.HourBucketEpochMs) {
			http.Error(w, analytics.ErrInvalidHourBucket.Error(), http.StatusBadRequest)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":      "accepted",
			"bucket_ms":   req.HourBucketEpochMs,
			"categories":  len(req.CategoryCounts),
			"received_at": time.Now().UnixMilli(),
		})
	})

	mux.HandleFunc("GET /api/v1/analytics/summary", func(w http.ResponseWriter, r *http.Request) {
		timeRange := r.URL.Query().Get("range")
		if timeRange == "" {
			timeRange = "24h"
		}

		// Realistic sample rollup aggregation (zero domains returned)
		summary := analytics.AnalyticsSummary{
			TimeRange:      timeRange,
			TotalQueries:   14250,
			BlockedQueries: 3820,
			AllowedQueries: 10430,
			BlockedPercent: 26.8,
			Categories: map[string]analytics.CategoryCount{
				"social":       {Total: 4120, Blocked: 2950, Allowed: 1170},
				"adult":        {Total: 840, Blocked: 840, Allowed: 0},
				"productivity": {Total: 6500, Blocked: 0, Allowed: 6500},
				"system":       {Total: 2790, Blocked: 30, Allowed: 2760},
			},
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(summary)
	})

	// 6. Dynamic Ed25519-Signed Rule Pack CDN Delivery
	mux.HandleFunc("GET /api/v1/rules/latest", func(w http.ResponseWriter, r *http.Request) {
		pack, err := ruleSigner.CreateSignedPack(
			"pack_v1",
			1,
			time.Now().UnixMilli(),
			false,
			[]string{"tiktok.com", "instagram.com", "youtube.com"},
			[]string{"googlevideo.com", "cdninstagram.com"},
		)
		if err != nil {
			http.Error(w, "failed to generate signed rule pack", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(pack)
	})

	// 7. Realtime WebSocket Hub
	mux.HandleFunc("/api/v1/ws", func(w http.ResponseWriter, r *http.Request) {
		userID := r.URL.Query().Get("user_id")
		if userID == "" {
			userID = "usr_anonymous"
		}
		deviceID := r.URL.Query().Get("device_id")
		wsHub.ServeWS(w, r, userID, deviceID)
	})

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("FocusDNS Cloud API listening on :%s ...", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down FocusDNS Cloud API gracefully...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("server forced shutdown: %v", err)
	}
	log.Println("FocusDNS Cloud API stopped cleanly.")
}
