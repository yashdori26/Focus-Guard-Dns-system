import XCTest
@testable import FocusDnsEngine

final class DomainMatcherTests: XCTestCase {
    
    private var matcher: DomainMatcher!
    
    override func setUp() {
        super.setUp()
        matcher = DomainMatcher()
    }
    
    func testExactDomainMatching() {
        XCTAssertTrue(matcher.isDomainBlocked("youtube.com"))
        XCTAssertTrue(matcher.isDomainBlocked("instagram.com"))
        XCTAssertTrue(matcher.isDomainBlocked("tiktok.com"))
        XCTAssertTrue(matcher.isDomainBlocked("pornhub.com"))
        XCTAssertTrue(matcher.isDomainBlocked("stake.com"))
        XCTAssertFalse(matcher.isDomainBlocked("wikipedia.org"))
        XCTAssertFalse(matcher.isDomainBlocked("github.com"))
    }
    
    func testWildcardAndSubdomainMatching() {
        // googlevideo subdomains
        XCTAssertTrue(matcher.isDomainBlocked("rr1---sn-cvh76nez.googlevideo.com"))
        XCTAssertTrue(matcher.isDomainBlocked("video.googlevideo.com"))
        
        // instagram subdomains
        XCTAssertTrue(matcher.isDomainBlocked("scontent-bom1-1.cdninstagram.com"))
        XCTAssertTrue(matcher.isDomainBlocked("edge-chat.instagram.com"))
        
        // Allowed roots should allow subdomains
        XCTAssertFalse(matcher.isDomainBlocked("en.wikipedia.org"))
        XCTAssertFalse(matcher.isDomainBlocked("api.github.com"))
    }
    
    func testNormalization() {
        XCTAssertTrue(matcher.isDomainBlocked("  YOUTUBE.COM  "))
        XCTAssertTrue(matcher.isDomainBlocked("Instagram.Com"))
    }
}
