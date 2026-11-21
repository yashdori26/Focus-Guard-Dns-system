import Foundation

/// Implements Option B (Network-Only Freeze) policy for iOS.
/// Allows apps to open and show cached items, while sinking all outgoing network lookups
/// to 0.0.0.0 / NXDOMAIN, freezing new feeds on an infinite loading spinner.
public final class NetworkFreezeEngine: @unchecked Sendable {
    public static let shared = NetworkFreezeEngine()
    
    public struct AppFreezePolicy: Sendable {
        public let appName: String
        public let bundleId: String
        public let frozenDomains: [String]
    }
    
    private let policies: [String: AppFreezePolicy]
    
    public init() {
        self.policies = [
            "com.burbn.instagram": AppFreezePolicy(
                appName: "Instagram",
                bundleId: "com.burbn.instagram",
                frozenDomains: ["instagram.com", "cdninstagram.com", "threads.net", "i.instagram.com"]
            ),
            "com.google.ios.youtube": AppFreezePolicy(
                appName: "YouTube",
                bundleId: "com.google.ios.youtube",
                frozenDomains: ["youtube.com", "googlevideo.com", "youtu.be", "ytimg.com"]
            ),
            "com.zhiliaoapp.musically": AppFreezePolicy(
                appName: "TikTok",
                bundleId: "com.zhiliaoapp.musically",
                frozenDomains: ["tiktok.com", "byteoversea.com", "ibytedtos.com", "tiktokv.com"]
            ),
            "com.reddit.Reddit": AppFreezePolicy(
                appName: "Reddit",
                bundleId: "com.reddit.Reddit",
                frozenDomains: ["reddit.com", "redd.it", "redditmedia.com"]
            ),
            "com.atebits.Tweetie2": AppFreezePolicy(
                appName: "X / Twitter",
                bundleId: "com.atebits.Tweetie2",
                frozenDomains: ["twitter.com", "x.com", "twimg.com"]
            )
        ]
    }
    
    public func isDomainFrozen(domain: String) -> (isFrozen: Bool, appName: String?) {
        let clean = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (_, policy) in policies {
            for fd in policy.frozenDomains {
                if clean == fd || clean.hasSuffix("." + fd) {
                    return (true, policy.appName)
                }
            }
        }
        return (false, nil)
    }
    
    public func getSinkholeAddress() -> String {
        return "0.0.0.0"
    }
}
