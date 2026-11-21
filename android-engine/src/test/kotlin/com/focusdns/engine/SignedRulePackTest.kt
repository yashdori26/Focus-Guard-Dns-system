package com.focusdns.engine

import com.focusdns.engine.rules.RulesEngine
import com.focusdns.engine.rules.SignedRulePackParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class SignedRulePackTest {

    private lateinit var rulesEngine: RulesEngine

    @Before
    fun setUp() {
        rulesEngine = RulesEngine()
        SignedRulePackParser.currentActiveVersion = 1L
    }

    @Test
    fun testAntiRollbackRejectsOlderVersion() {
        SignedRulePackParser.currentActiveVersion = 10L

        // Attempt to apply older version 4
        val fakeOlderJson = """
            {
                "packId": "pack_test_downgrade",
                "version": 4,
                "publishedAtEpochMs": 1732104000000,
                "killSwitchActive": false,
                "signature": "fake_sig",
                "categoryDomainRules": {}
            }
        """.trimIndent()

        val result = SignedRulePackParser.parseAndVerify(fakeOlderJson, "fake_pub_key", enforceAntiRollback = true)
        assertTrue(result.isFailure)
        val ex = result.exceptionOrNull()
        assertTrue(ex is SecurityException)
        assertTrue(ex?.message?.contains("ERR_RULE_PACK_ROLLBACK_ATTEMPT_DETECTED") == true)
        assertEquals(10L, SignedRulePackParser.currentActiveVersion)
    }

    @Test
    fun testValidNewerVersionAccepted() {
        SignedRulePackParser.currentActiveVersion = 5L

        // Apply newer version 6
        val fakeNewerJson = """
            {
                "packId": "pack_test_upgrade",
                "version": 6,
                "publishedAtEpochMs": 1732104100000,
                "killSwitchActive": false,
                "signature": "fake_sig",
                "categoryDomainRules": {
                    "custom": {
                        "exactDomains": ["newdistraction.com"],
                        "wildcardSuffixes": ["badgames.org"]
                    }
                }
            }
        """.trimIndent()

        val result = SignedRulePackParser.parseAndVerify(fakeNewerJson, "fake_pub_key", enforceAntiRollback = true)
        assertTrue(result.isSuccess)
        val pack = result.getOrNull()!!
        assertEquals(6L, pack.version)
        assertEquals(6L, SignedRulePackParser.currentActiveVersion)

        // Apply to rules engine
        rulesEngine.applyRulePack(pack)
        assertTrue(rulesEngine.isDomainBlocked("newdistraction.com"))
        assertTrue(rulesEngine.isDomainBlocked("play.badgames.org"))
    }

    @Test
    fun testKillSwitchSafeFallback() {
        val killSwitchJson = """
            {
                "packId": "pack_test_killswitch",
                "version": 7,
                "publishedAtEpochMs": 1732104200000,
                "killSwitchActive": true,
                "signature": "fake_sig",
                "categoryDomainRules": {}
            }
        """.trimIndent()

        val result = SignedRulePackParser.parseAndVerify(killSwitchJson, "fake_pub_key")
        assertTrue(result.isSuccess)
        val pack = result.getOrNull()!!
        assertTrue(pack.killSwitchActive)

        // When applied, base safety rules MUST remain intact
        rulesEngine.applyRulePack(pack)
        assertTrue(rulesEngine.isDomainBlocked("instagram.com"))
        assertTrue(rulesEngine.isDomainBlocked("pornhub.com"))
    }
}
