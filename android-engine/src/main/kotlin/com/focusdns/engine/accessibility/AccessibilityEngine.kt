package com.focusdns.engine.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.focusdns.engine.rules.SignedRulePackParser
import com.focusdns.engine.session.EvaluationTarget
import com.focusdns.engine.session.SessionStateMachineEngine
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

/**
 * Android Accessibility Service Engine with Adaptive Layout Heuristics.
 * Enforces feed-only sub-feature blocking, application foreground shields,
 * and app termination sweeps with resilience against third-party app updates.
 */
class AccessibilityEngine : AccessibilityService() {

    companion object {
        const val TAG = "FocusAccessibility"
        private const val MAX_TREE_DEPTH = 8
        private const val DEBOUNCE_MS = 300L

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var instance: AccessibilityEngine? = null
            private set

        var stateMachineEngine: SessionStateMachineEngine? = null

        // Dynamically updatable subfeature rules from signed rule packs
        val dynamicSelectors = CopyOnWriteArrayList<SignedRulePackParser.SubfeatureRule>()

        fun closeForegroundApp(): Boolean {
            val s = instance ?: return false
            return s.performGlobalAction(GLOBAL_ACTION_HOME)
        }

        fun navigateBack(): Boolean {
            val s = instance ?: return false
            return s.performGlobalAction(GLOBAL_ACTION_BACK)
        }

        fun updateDynamicSelectors(rules: List<SignedRulePackParser.SubfeatureRule>) {
            dynamicSelectors.clear()
            dynamicSelectors.addAll(rules)
            Log.i(TAG, "Loaded ${rules.size} dynamic accessibility selectors.")
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingDebounceRunnable: Runnable? = null
    private var lastInterceptedTimeMs = 0L

    val totalNodesScanned = AtomicLong(0)
    val totalInterventions = AtomicLong(0)

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
        instance = this
        Log.i(TAG, "FocusDNS Accessibility Engine connected with Adaptive Heuristics.")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return // Never block FocusDNS itself

        val eventType = event.eventType
        if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            handleWindowStateChanged(event, pkg)
        } else if (eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            handleWindowContentChanged(event, pkg)
        }
    }

    private fun handleWindowStateChanged(event: AccessibilityEvent, pkg: String) {
        pendingDebounceRunnable?.let { mainHandler.removeCallbacks(it) }

        // Double Verification for Applications:
        // Tier 1: State Machine & Explicit App Blocklist
        val target = EvaluationTarget(packageName = pkg)
        val decision = stateMachineEngine?.isBlocked(target)

        // Tier 2: Lexical Category Verification on Package & Window Title
        val windowTitle = event.text.joinToString(" ")
        val categoryVerdict = com.focusdns.engine.rules.CategoryVerifier.verifyAppCategory(pkg, windowTitle)

        val isSessionActive = stateMachineEngine?.currentSnapshot?.primaryState?.let {
            it != com.focusdns.engine.session.PrimaryState.INACTIVE &&
            it != com.focusdns.engine.session.PrimaryState.COMPLETED &&
            it != com.focusdns.engine.session.PrimaryState.PAUSED
        } ?: false

        val shouldBlockApp = (decision?.isBlocked == true) || (isSessionActive && categoryVerdict.isMatched)

        if (shouldBlockApp) {
            val reason = if (decision?.isBlocked == true) decision.reason else "Double Verification Tier 2: App matches blocked category (${categoryVerdict.matchedCategory})"
            Log.i(TAG, "Shield Blocked Foreground Package: $pkg ($reason)")
            totalInterventions.incrementAndGet()
            performGlobalAction(GLOBAL_ACTION_HOME)
            return
        }

        // Check sub-feature feed targets in Mode 4 or active sessions
        inspectViewHierarchyForFeeds(pkg)
    }

    private fun handleWindowContentChanged(event: AccessibilityEvent, pkg: String) {
        val isTargetApp = pkg in listOf(
            "com.google.android.youtube",
            "com.instagram.android",
            "com.zhiliaoapp.musically",
            "com.reddit.frontpage"
        )
        if (!isTargetApp) return

        pendingDebounceRunnable?.let { mainHandler.removeCallbacks(it) }
        val runnable = Runnable {
            inspectViewHierarchyForFeeds(pkg)
        }
        pendingDebounceRunnable = runnable
        mainHandler.postDelayed(runnable, DEBOUNCE_MS)
    }

    private fun inspectViewHierarchyForFeeds(pkg: String) {
        val root = rootInActiveWindow ?: return
        try {
            traverseNode(root, pkg, 0)
        } catch (e: Exception) {
            Log.e(TAG, "Error inspecting view node hierarchy: ${e.message}")
        }
    }

    private fun traverseNode(node: AccessibilityNodeInfo?, pkg: String, depth: Int) {
        if (node == null || depth > MAX_TREE_DEPTH) return
        totalNodesScanned.incrementAndGet()

        val viewId = node.viewIdResourceName?.lowercase() ?: ""
        val desc = node.contentDescription?.toString()?.lowercase() ?: ""
        val text = node.text?.toString()?.lowercase() ?: ""
        val className = node.className?.toString() ?: ""

        // 1. Dynamic selector rules matching (from downloaded signed rule packs)
        for (dyn in dynamicSelectors) {
            if (dyn.appId == pkg) {
                val idMatch = dyn.resourceIdPatterns.any { pattern -> viewId.contains(pattern) }
                val descMatch = dyn.contentDescPatterns.any { pattern -> desc.contains(pattern) }
                val textMatch = dyn.textPatterns.any { pattern -> text.contains(pattern) }
                if (idMatch || descMatch || textMatch) {
                    val target = EvaluationTarget(
                        packageName = pkg,
                        subfeature = dyn.subfeature
                    )
                    val decision = stateMachineEngine?.isBlocked(target)
                    if (decision?.isBlocked == true) {
                        triggerSurgicalIntervention("Dynamic Selector: ${dyn.subfeature}")
                        return
                    }
                }
            }
        }

        // 2. Adaptive Structural & Lexical Heuristics for YouTube Shorts
        if (pkg == "com.google.android.youtube") {
            val isShortsId = viewId.contains("reel") || viewId.contains("short")
            val isShortsDesc = desc == "shorts" || desc.contains("youtube shorts") || desc.contains("remix")
            val isShortsText = text == "shorts" || text.contains("shorts")

            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            val isVerticalSnapVideo = bounds.width() > 0 && bounds.height() > 0 &&
                (bounds.height().toDouble() / bounds.width() >= 1.7) &&
                (className.contains("ViewPager") || className.contains("RecyclerView") || className.contains("Player"))

            if (isShortsId || isShortsDesc || (isShortsText && isVerticalSnapVideo)) {
                val target = EvaluationTarget(
                    packageName = pkg,
                    domain = "youtube.com",
                    subfeature = "reelsOrShorts"
                )
                val decision = stateMachineEngine?.isBlocked(target)
                if (decision?.isBlocked == true) {
                    triggerSurgicalIntervention("YouTube Shorts (Adaptive Heuristic)")
                    return
                }
            }
        }

        // 3. Adaptive Structural & Lexical Heuristics for Instagram Reels / Explore
        if (pkg == "com.instagram.android") {
            val isReelsId = viewId.contains("clips") || viewId.contains("reel")
            val isReelsDesc = desc.contains("reels") || desc.contains("clips") || desc == "watch reels"
            val isReelsText = text.contains("reels")

            val isExplore = viewId.contains("explore_tab") || desc.contains("search and explore") || desc == "explore"

            if (isReelsId || isReelsDesc || isReelsText || isExplore) {
                val sub = if (isExplore) "explore" else "reelsOrShorts"
                val target = EvaluationTarget(
                    packageName = pkg,
                    domain = "instagram.com",
                    subfeature = sub
                )
                val decision = stateMachineEngine?.isBlocked(target)
                if (decision?.isBlocked == true) {
                    triggerSurgicalIntervention("Instagram $sub (Adaptive Heuristic)")
                    return
                }
            }
        }

        // Recurse child view nodes
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            traverseNode(child, pkg, depth + 1)
        }
    }

    private fun triggerSurgicalIntervention(featureName: String) {
        val now = System.currentTimeMillis()
        if (now - lastInterceptedTimeMs < 800L) return

        lastInterceptedTimeMs = now
        totalInterventions.incrementAndGet()
        Log.w(TAG, "Surgical Intervention: Navigating back out of $featureName")
        performGlobalAction(GLOBAL_ACTION_BACK)
    }

    override fun onInterrupt() {
        Log.w(TAG, "FocusDNS Accessibility Service interrupted.")
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        super.onDestroy()
    }
}
