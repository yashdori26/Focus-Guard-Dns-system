package com.focusdns.engine

import com.focusdns.engine.rules.CategoryVerifier
import com.focusdns.engine.rules.RulesEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class RulesEngineTest {

    private lateinit var rules: RulesEngine

    @Before
    fun setUp() {
        rules = RulesEngine()
    }

    @Test
    fun testExactDomainMatching() {
        assertTrue(rules.isDomainBlocked("youtube.com"))
        assertTrue(rules.isDomainBlocked("instagram.com"))
        assertTrue(rules.isDomainBlocked("tiktok.com"))
        assertTrue(rules.isDomainBlocked("pornhub.com"))
        assertTrue(rules.isDomainBlocked("stake.com"))
        assertFalse(rules.isDomainBlocked("wikipedia.org"))
        assertFalse(rules.isDomainBlocked("github.com"))
    }

    @Test
    fun testWildcardAndSubdomainMatching() {
        // googlevideo subdomains
        assertTrue(rules.isDomainBlocked("rr1---sn-cvh76nez.googlevideo.com"))
        assertTrue(rules.isDomainBlocked("video.googlevideo.com"))

        // cdninstagram subdomains
        assertTrue(rules.isDomainBlocked("scontent-bom1-1.cdninstagram.com"))
        assertTrue(rules.isDomainBlocked("edge-chat.instagram.com"))

        // clean subdomain of allowed root
        assertFalse(rules.isDomainBlocked("en.wikipedia.org"))
        assertFalse(rules.isDomainBlocked("api.github.com"))
    }

    @Test
    fun testPunycodeCanonicalization() {
        // Uppercase and whitespace normalizations
        assertTrue(rules.isDomainBlocked("  YOUTUBE.COM  "))
        assertTrue(rules.isDomainBlocked("Instagram.Com"))
    }

    @Test
    fun testDoubleVerificationTier1ExplicitList() {
        val verdict = rules.doubleVerifyDomain("instagram.com")
        assertTrue(verdict.isBlocked)
        assertEquals(1, verdict.tier)
        assertTrue(verdict.reason.contains("Tier 1"))
    }

    @Test
    fun testDoubleVerificationTier2CategoryAndName() {
        // Domain not on explicit blocklist, but name/tokens match Gambling category
        val gamblingVerdict = rules.doubleVerifyDomain("royal-crypto-casino.io")
        assertTrue(gamblingVerdict.isBlocked)
        assertEquals(2, gamblingVerdict.tier)
        assertEquals(CategoryVerifier.CAT_GAMBLING, gamblingVerdict.matchedCategory)
        assertTrue(gamblingVerdict.reason.contains("Tier 2"))

        // Adult TLD match
        val adultVerdict = rules.doubleVerifyDomain("random-new-gallery.xxx")
        assertTrue(adultVerdict.isBlocked)
        assertEquals(2, adultVerdict.tier)
        assertEquals(CategoryVerifier.CAT_ADULT, adultVerdict.matchedCategory)

        // Clean educational domain: both checks pass
        val cleanVerdict = rules.doubleVerifyDomain("mit.edu")
        assertFalse(cleanVerdict.isBlocked)
        assertEquals(0, cleanVerdict.tier)
    }

    @Test
    fun testDoubleVerificationAppCategory() {
        // App package containing blocked category keywords
        val casinoApp = CategoryVerifier.verifyAppCategory("com.grand.vegas.casino.slots")
        assertTrue(casinoApp.isMatched)
        assertEquals(CategoryVerifier.CAT_GAMBLING, casinoApp.matchedCategory)

        // Clean utility app: unblocked
        val calcApp = CategoryVerifier.verifyAppCategory("com.google.android.calculator")
        assertFalse(calcApp.isMatched)
    }
}
