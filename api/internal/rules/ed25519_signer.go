package rules

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
)

type RulePackSigner struct {
	privateKey ed25519.PrivateKey
	publicKey  ed25519.PublicKey
}

func NewRulePackSigner() (*RulePackSigner, error) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, err
	}
	return &RulePackSigner{
		privateKey: priv,
		publicKey:  pub,
	}, nil
}

func NewRulePackSignerFromHex(privateKeyHex string) (*RulePackSigner, error) {
	privBytes, err := hex.DecodeString(privateKeyHex)
	if err != nil || len(privBytes) != ed25519.PrivateKeySize {
		return nil, fmt.Errorf("invalid Ed25519 private key hex")
	}
	priv := ed25519.PrivateKey(privBytes)
	pub := priv.Public().(ed25519.PublicKey)
	return &RulePackSigner{
		privateKey: priv,
		publicKey:  pub,
	}, nil
}

func (s *RulePackSigner) PublicKeyHex() string {
	return hex.EncodeToString(s.publicKey)
}

func (s *RulePackSigner) SignPayload(payloadData []byte) string {
	sig := ed25519.Sign(s.privateKey, payloadData)
	return hex.EncodeToString(sig)
}

type DynamicRulePack struct {
	PackID               string   `json:"pack_id"`
	Version              int      `json:"version"`
	TimestampEpochMs     int64    `json:"timestamp_epoch_ms"`
	KillSwitch           bool     `json:"kill_switch"`
	ExactBlockedDomains  []string `json:"exact_blocked_domains"`
	WildcardSuffixes     []string `json:"wildcard_suffixes"`
	SignatureEd25519Hex  string   `json:"signature_ed25519_hex"`
}

func (s *RulePackSigner) CreateSignedPack(
	packID string,
	version int,
	timestampEpochMs int64,
	killSwitch bool,
	exactDomains []string,
	wildcards []string,
) (*DynamicRulePack, error) {
	unsigned := struct {
		PackID              string   `json:"pack_id"`
		Version             int      `json:"version"`
		TimestampEpochMs    int64    `json:"timestamp_epoch_ms"`
		KillSwitch          bool     `json:"kill_switch"`
		ExactBlockedDomains []string `json:"exact_blocked_domains"`
		WildcardSuffixes    []string `json:"wildcard_suffixes"`
	}{
		PackID:              packID,
		Version:             version,
		TimestampEpochMs:    timestampEpochMs,
		KillSwitch:          killSwitch,
		ExactBlockedDomains: exactDomains,
		WildcardSuffixes:    wildcards,
	}

	data, err := json.Marshal(unsigned)
	if err != nil {
		return nil, err
	}

	sigHex := s.SignPayload(data)

	return &DynamicRulePack{
		PackID:              packID,
		Version:             version,
		TimestampEpochMs:    timestampEpochMs,
		KillSwitch:          killSwitch,
		ExactBlockedDomains: exactDomains,
		WildcardSuffixes:    wildcards,
		SignatureEd25519Hex: sigHex,
	}, nil
}
