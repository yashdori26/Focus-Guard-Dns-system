package admin

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/focusdns/api/internal/rules"
)

type FleetOverview struct {
	TotalDevices       int     `json:"total_devices"`
	OnlineDevices      int     `json:"online_devices"`
	ActiveStrictLocks  int     `json:"active_strict_locks"`
	TotalQueriesToday  int64   `json:"total_queries_today"`
	BlockedPercentage  float64 `json:"blocked_percentage"`
	KillSwitchEngaged  bool    `json:"kill_switch_engaged"`
}

type AdminService struct {
	ruleSigner *rules.RulePackSigner
	killSwitch bool
}

func NewAdminService(signer *rules.RulePackSigner) *AdminService {
	return &AdminService{
		ruleSigner: signer,
		killSwitch: false,
	}
}

func (s *AdminService) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/admin/overview", s.handleOverview)
	mux.HandleFunc("POST /api/v1/admin/rules/publish", s.handlePublishRules)
	mux.HandleFunc("POST /api/v1/admin/kill-switch", s.handleKillSwitch)
}

func (s *AdminService) handleOverview(w http.ResponseWriter, r *http.Request) {
	overview := FleetOverview{
		TotalDevices:      24,
		OnlineDevices:     19,
		ActiveStrictLocks: 5,
		TotalQueriesToday: 48920,
		BlockedPercentage: 27.4,
		KillSwitchEngaged: s.killSwitch,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(overview)
}

func (s *AdminService) handlePublishRules(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ExactDomains []string `json:"exact_domains"`
		Wildcards    []string `json:"wildcards"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid payload", http.StatusBadRequest)
		return
	}

	pack, err := s.ruleSigner.CreateSignedPack(
		"pack_"+time.Now().Format("20060102150405"),
		int(time.Now().Unix()),
		time.Now().UnixMilli(),
		s.killSwitch,
		req.ExactDomains,
		req.Wildcards,
	)
	if err != nil {
		http.Error(w, "signing failed", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(pack)
}

func (s *AdminService) handleKillSwitch(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Engage bool `json:"engage"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid payload", http.StatusBadRequest)
		return
	}

	s.killSwitch = req.Engage
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":      "success",
		"kill_switch": s.killSwitch,
		"updated_at":  time.Now().UnixMilli(),
	})
}
