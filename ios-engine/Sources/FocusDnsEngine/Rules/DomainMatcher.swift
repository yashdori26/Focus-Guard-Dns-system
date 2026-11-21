import Foundation

/// High-performance on-device domain matching with Double Verification (Tier 1 Blocklist + Tier 2 Category Lexical Analysis).
public final class DomainMatcher: @unchecked Sendable {
    private let lock = NSLock()
    private var exactDenyList = Set<String>()
    private var wildcardDenySuffixes = Set<String>()
    
    // TLD Priors strongly indicating specific blocked categories
    private let tldPriors: [String: String] = [
        "xxx": "ADULT_CONTENT",
        "porn": "ADULT_CONTENT",
        "adult": "ADULT_CONTENT",
        "sexy": "ADULT_CONTENT",
        "cam": "ADULT_CONTENT",
        "casino": "CRYPTO_GAMBLING",
        "bet": "CRYPTO_GAMBLING",
        "poker": "CRYPTO_GAMBLING",
        "game": "GAMING",
        "games": "GAMING",
        "gg": "GAMING"
    ]
    
    // Weighted Category Keywords
    private let categoryKeywords: [String: String] = [
        "porn": "ADULT_CONTENT",
        "pornhub": "ADULT_CONTENT",
        "xvideos": "ADULT_CONTENT",
        "xnxx": "ADULT_CONTENT",
        "stripchat": "ADULT_CONTENT",
        "erotic": "ADULT_CONTENT",
        "casino": "CRYPTO_GAMBLING",
        "bet": "CRYPTO_GAMBLING",
        "betting": "CRYPTO_GAMBLING",
        "bet365": "CRYPTO_GAMBLING",
        "stake": "CRYPTO_GAMBLING",
        "1xbet": "CRYPTO_GAMBLING",
        "poker": "CRYPTO_GAMBLING",
        "slots": "CRYPTO_GAMBLING",
        "roulette": "CRYPTO_GAMBLING",
        "steam": "GAMING",
        "roblox": "GAMING",
        "riotgames": "GAMING",
        "epicgames": "GAMING",
        "minecraft": "GAMING",
        "twitch": "GAMING",
        "instagram": "SOCIAL_MEDIA",
        "tiktok": "SOCIAL_MEDIA",
        "reddit": "SOCIAL_MEDIA",
        "facebook": "SOCIAL_MEDIA",
        "reels": "SOCIAL_MEDIA",
        "shorts": "SOCIAL_MEDIA",
        "torrent": "PIRACY",
        "1337x": "PIRACY",
        "piratebay": "PIRACY"
    ]
    
    public init() {
        registerBuiltInRules()
    }
    
    private func registerBuiltInRules() {
        exactDenyList.formUnion([
            "youtube.com", "youtu.be", "googlevideo.com", "ytimg.com",
            "instagram.com", "cdninstagram.com", "threads.net",
            "tiktok.com", "byteoversea.com", "ibytedtos.com",
            "reddit.com", "redd.it", "redditmedia.com",
            "facebook.com", "fbcdn.net",
            "pornhub.com", "xvideos.com", "xnxx.com", "stripchat.com",
            "stake.com", "bet365.com", "1xbet.com",
            "1337x.to", "thepiratebay.org", "torrentfreak.com"
        ])
        
        wildcardDenySuffixes.formUnion([
            "youtube.com",
            "googlevideo.com",
            "instagram.com",
            "cdninstagram.com",
            "tiktok.com",
            "byteoversea.com",
            "tiktokv.com",
            "reddit.com",
            "facebook.com",
            "pornhub.com"
        ])
    }
    
    public func addExactBlock(domain: String) {
        lock.lock()
        defer { lock.unlock() }
        exactDenyList.insert(canonicalize(domain))
    }
    
    public func addWildcardSuffix(suffix: String) {
        lock.lock()
        defer { lock.unlock() }
        wildcardDenySuffixes.insert(canonicalize(suffix))
    }
    
    /// Executes Double Verification:
    /// Tier 1: Exact blocklist and wildcard suffixes.
    /// Tier 2: Category lexical verification against address, labels, and TLD.
    public func doubleVerifyDomain(_ rawDomain: String) -> (isBlocked: Bool, reason: String) {
        if rawDomain.isEmpty { return (false, "Empty domain") }
        let domain = canonicalize(rawDomain)
        
        lock.lock()
        defer { lock.unlock() }
        
        // Tier 1: Exact match
        if exactDenyList.contains(domain) {
            return (true, "Double Verification Tier 1: Exact match in blocklist (\(domain))")
        }
        
        // Tier 1: Wildcard match
        for suffix in wildcardDenySuffixes {
            if domain == suffix || domain.hasSuffix("." + suffix) {
                return (true, "Double Verification Tier 1: Wildcard match (*.\(suffix))")
            }
        }
        
        // Tier 2: Category Lexical Verification
        let parts = domain.split(separator: ".").map(String.init)
        if let tld = parts.last, let cat = tldPriors[tld] {
            return (true, "Double Verification Tier 2: TLD matches blocked category \(cat)")
        }
        
        for part in parts {
            let subTokens = part.split(separator: "-").map(String.init)
            for token in subTokens {
                if token.count >= 3, let cat = categoryKeywords[token] {
                    return (true, "Double Verification Tier 2: Token '\(token)' matches blocked category \(cat)")
                }
            }
        }
        
        return (false, "Double Verification Passed: Domain clean")
    }
    
    public func isDomainBlocked(_ rawDomain: String) -> Bool {
        return doubleVerifyDomain(rawDomain).isBlocked
    }
    
    private func canonicalize(_ domain: String) -> String {
        return domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
