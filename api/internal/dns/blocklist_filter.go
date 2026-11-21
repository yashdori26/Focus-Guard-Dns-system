package dns

import (
	"strings"
	"sync"
)

type DomainBlocklist struct {
	mu                   sync.RWMutex
	exactDeny            map[string]bool
	wildcardDenySuffixes []string
}

func NewDomainBlocklist() *DomainBlocklist {
	b := &DomainBlocklist{
		exactDeny: make(map[string]bool),
		wildcardDenySuffixes: []string{
			"youtube.com",
			"googlevideo.com",
			"instagram.com",
			"cdninstagram.com",
			"tiktok.com",
			"byteoversea.com",
			"tiktokv.com",
			"reddit.com",
			"facebook.com",
			"pornhub.com",
		},
	}

	b.registerDefaults()
	return b
}

func (b *DomainBlocklist) registerDefaults() {
	defaults := []string{
		"youtube.com", "youtu.be", "googlevideo.com", "ytimg.com",
		"instagram.com", "cdninstagram.com", "threads.net",
		"tiktok.com", "byteoversea.com", "ibytedtos.com",
		"reddit.com", "redd.it", "redditmedia.com",
		"facebook.com", "fbcdn.net",
		"pornhub.com", "xvideos.com", "xnxx.com", "stripchat.com",
		"stake.com", "bet365.com", "1xbet.com",
		"1337x.to", "thepiratebay.org", "torrentfreak.com",
	}
	for _, d := range defaults {
		b.exactDeny[d] = true
	}
}

func (b *DomainBlocklist) IsBlocked(rawDomain string) bool {
	domain := strings.ToLower(strings.Trim(strings.TrimSpace(rawDomain), "."))
	if domain == "" {
		return false
	}

	b.mu.RLock()
	defer b.mu.RUnlock()

	// 1. Exact match
	if b.exactDeny[domain] {
		return true
	}

	// 2. Wildcard subdomain matching
	for _, suffix := range b.wildcardDenySuffixes {
		if domain == suffix || strings.HasSuffix(domain, "."+suffix) {
			return true
		}
	}

	return false
}

func (b *DomainBlocklist) ApplyDelta(exact []string, wildcards []string) {
	b.mu.Lock()
	defer b.mu.Unlock()

	for _, d := range exact {
		b.exactDeny[strings.ToLower(strings.TrimSpace(d))] = true
	}
	for _, w := range wildcards {
		b.wildcardDenySuffixes = append(b.wildcardDenySuffixes, strings.ToLower(strings.TrimSpace(w)))
	}
}
