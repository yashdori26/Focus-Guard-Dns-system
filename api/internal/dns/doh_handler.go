package dns

import (
	"bytes"
	"encoding/base64"
	"io"
	"net/http"
	"strings"
)

type DoHHandler struct {
	blocklist       *DomainBlocklist
	upstreamDoHURL string
	httpClient      *http.Client
}

func NewDoHHandler(blocklist *DomainBlocklist, upstreamURL string) *DoHHandler {
	if upstreamURL == "" {
		upstreamURL = "https://1.1.1.1/dns-query"
	}
	return &DoHHandler{
		blocklist:       blocklist,
		upstreamDoHURL: upstreamURL,
		httpClient:      &http.Client{},
	}
}

func (h *DoHHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var dnsMsg []byte
	var err error

	if r.Method == http.MethodPost {
		dnsMsg, err = io.ReadAll(r.Body)
		if err != nil || len(dnsMsg) < 12 {
			http.Error(w, "invalid dns message", http.StatusBadRequest)
			return
		}
	} else if r.Method == http.MethodGet {
		dnsParam := r.URL.Query().Get("dns")
		if dnsParam == "" {
			http.Error(w, "missing dns query param", http.StatusBadRequest)
			return
		}
		dnsMsg, err = base64.RawURLEncoding.DecodeString(dnsParam)
		if err != nil || len(dnsMsg) < 12 {
			http.Error(w, "invalid base64 dns message", http.StatusBadRequest)
			return
		}
	} else {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	domain, questionEnd := extractDomainFromDNS(dnsMsg)
	if domain != "" && h.blocklist.IsBlocked(domain) {
		// Synthesize NXDOMAIN (RCODE 3)
		resp := synthesizeNXDOMAIN(dnsMsg, questionEnd)
		w.Header().Set("Content-Type", "application/dns-message")
		w.WriteHeader(http.StatusOK)
		w.Write(resp)
		return
	}

	// Forward upstream
	req, err := http.NewRequest(http.MethodPost, h.upstreamDoHURL, bytes.NewReader(dnsMsg))
	if err != nil {
		http.Error(w, "upstream request creation failed", http.StatusInternalServerError)
		return
	}
	req.Header.Set("Content-Type", "application/dns-message")
	req.Header.Set("Accept", "application/dns-message")

	resp, err := h.httpClient.Do(req)
	if err != nil {
		http.Error(w, "upstream resolution failed", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", "application/dns-message")
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func extractDomainFromDNS(packet []byte) (string, int) {
	if len(packet) < 12 {
		return "", 0
	}

	qdcount := int(packet[4])<<8 | int(packet[5])
	if qdcount == 0 {
		return "", 12
	}

	idx := 12
	var labels []string

	for idx < len(packet) {
		length := int(packet[idx])
		idx++

		if length == 0 {
			break
		}
		if (length & 0xc0) == 0xc0 {
			// Compression pointer
			idx++
			break
		}
		if idx+length > len(packet) {
			return "", 0
		}
		labels = append(labels, string(packet[idx:idx+length]))
		idx += length
	}

	questionEnd := idx + 4 // Skip QTYPE (2) + QCLASS (2)
	return strings.Join(labels, "."), questionEnd
}

func synthesizeNXDOMAIN(query []byte, questionEnd int) []byte {
	if questionEnd > len(query) || questionEnd < 12 {
		questionEnd = len(query)
	}

	resp := make([]byte, questionEnd)
	copy(resp, query[:questionEnd])

	// Flags: QR=1 (response), AA=0, TC=0, RD=1, RA=1, RCODE=3 (NXDOMAIN)
	// 0x8183 in Big Endian
	resp[2] = 0x81
	resp[3] = 0x83

	// QDCOUNT: 1, ANCOUNT: 0, NSCOUNT: 0, ARCOUNT: 0
	resp[4] = 0x00
	resp[5] = 0x01
	resp[6] = 0x00
	resp[7] = 0x00
	resp[8] = 0x00
	resp[9] = 0x00
	resp[10] = 0x00
	resp[11] = 0x00

	return resp
}
