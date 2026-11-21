package auth

import (
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"errors"
	"fmt"
)

var (
	ErrInvalidDeviceSignature = errors.New("invalid cryptographic device signature")
	ErrInvalidPublicKey       = errors.New("invalid Ed25519 public key length")
)

// GenerateDeviceChallenge creates a 32-byte cryptographic nonce for device authentication.
func GenerateDeviceChallenge() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

// VerifyDeviceSignature checks if client signed challengeNonce with registered Ed25519 public key.
func VerifyDeviceSignature(publicKeyHex, challengeNonceHex, signatureHex string) (bool, error) {
	pubKeyBytes, err := hex.DecodeString(publicKeyHex)
	if err != nil || len(pubKeyBytes) != ed25519.PublicKeySize {
		return false, ErrInvalidPublicKey
	}

	nonceBytes, err := hex.DecodeString(challengeNonceHex)
	if err != nil {
		return false, fmt.Errorf("invalid nonce hex: %w", err)
	}

	sigBytes, err := hex.DecodeString(signatureHex)
	if err != nil || len(sigBytes) != ed25519.SignatureSize {
		return false, fmt.Errorf("invalid signature hex: %w", err)
	}

	isValid := ed25519.Verify(pubKeyBytes, nonceBytes, sigBytes)
	if !isValid {
		return false, ErrInvalidDeviceSignature
	}

	return true, nil
}

// VerifyDeviceSignatureP256 verifies an ECDSA NIST P-256 (secp256r1) signature from Apple Secure Enclave or Android KeyStore.
func VerifyDeviceSignatureP256(publicKeyHex, challengeNonceHex, signatureDerHex string) (bool, error) {
	pubKeyBytes, err := hex.DecodeString(publicKeyHex)
	if err != nil {
		return false, fmt.Errorf("invalid public key hex: %w", err)
	}

	var pubKey *ecdsa.PublicKey
	if len(pubKeyBytes) == 65 && pubKeyBytes[0] == 0x04 {
		x, y := elliptic.Unmarshal(elliptic.P256(), pubKeyBytes)
		if x == nil || y == nil {
			return false, errors.New("invalid P-256 uncompressed public key point")
		}
		pubKey = &ecdsa.PublicKey{
			Curve: elliptic.P256(),
			X:     x,
			Y:     y,
		}
	} else {
		parsedKey, err := x509.ParsePKIXPublicKey(pubKeyBytes)
		if err != nil {
			return false, fmt.Errorf("failed to parse PKIX public key: %w", err)
		}
		ecKey, ok := parsedKey.(*ecdsa.PublicKey)
		if !ok || ecKey.Curve != elliptic.P256() {
			return false, errors.New("public key is not an ECDSA P-256 key")
		}
		pubKey = ecKey
	}

	nonceBytes, err := hex.DecodeString(challengeNonceHex)
	if err != nil {
		return false, fmt.Errorf("invalid nonce hex: %w", err)
	}

	sigBytes, err := hex.DecodeString(signatureDerHex)
	if err != nil {
		return false, fmt.Errorf("invalid signature hex: %w", err)
	}

	// ECDSA verifies the SHA-256 hash of the challenge nonce
	hash := sha256.Sum256(nonceBytes)
	isValid := ecdsa.VerifyASN1(pubKey, hash[:], sigBytes)
	if !isValid {
		return false, ErrInvalidDeviceSignature
	}

	return true, nil
}

