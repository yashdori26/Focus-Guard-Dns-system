package com.focusdns.app.surgical

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * SurgicalViewHierarchyInspector scans live AccessibilityNodeInfo view hierarchies
 * in real time to detect addictive sub-feature views (Reels, Shorts, Explore) inside
 * hybrid applications (Instagram, YouTube, Reddit, TikTok, etc.) while allowing
 * chat/messaging fragments to function unhindered.
 */
class SurgicalViewHierarchyInspector(private val service: AccessibilityService) {

    companion object {
        const val TAG = "SurgicalInspector"
        private const val MAX_TREE_DEPTH = 8
        private const val DEBOUNCE_WINDOW_MS = 1000L

        // Known high-hazard package names
        const val PKG_INSTAGRAM = "com.instagram.android"
        const val PKG_YOUTUBE = "com.google.android.youtube"
        const val PKG_REDDIT = "com.reddit.frontpage"
        const val PKG_TIKTOK = "com.zhiliaoapp.musically"
        const val PKG_TIKTOK_LITE = "com.zhiliaoapp.musically.go"
        const val PKG_TWITTER = "com.twitter.android"
        const val PKG_LINKEDIN = "com.linkedin.android"
        const val PKG_SNAPCHAT = "com.snapchat.android"
        const val PKG_FACEBOOK = "com.facebook.katana"
    }

    data class InspectionTarget(
        val targetId: String,
        val packageName: String,
        val subfeature: String,
        val resourceIdPatterns: List<String>,
        val contentDescriptionPatterns: List<String>,
        val textPatterns: List<String>,
        val defaultAction: String,
        val description: String
    )

    private val targetRegistry = ConcurrentHashMap<String, MutableList<InspectionTarget>>()
    private val subfeatureToggles = ConcurrentHashMap<String, Boolean>() // "pkg:subfeature" -> isBlocked
    private val mainHandler = Handler(Looper.getMainLooper())

    private var lastInterceptionSignature: String? = null
    private var lastInterceptionTimeMs: Long = 0L

    val totalNodesScanned = AtomicLong(0)
    val totalViewsIntercepted = AtomicLong(0)
    val totalDebounceDrops = AtomicLong(0)

    var onInterceptionListener: ((packageName: String, subfeature: String, targetId: String, action: String) -> Unit)? = null

    init {
        registerDefaultBuiltInTargets()
    }

    /**
     * Registers default built-in view node signatures for leading social platforms.
     */
    private fun registerDefaultBuiltInTargets() {
        // Instagram Reels
        registerTarget(
            InspectionTarget(
                targetId = "ig_reels_tab",
                packageName = PKG_INSTAGRAM,
                subfeature = "reelsOrShorts",
                resourceIdPatterns = listOf("clips_viewer", "tab_reels", "clips_video_container", "clips_viewer_container"),
                contentDescriptionPatterns = listOf("Reels", "Reels tab", "Clips"),
                textPatterns = listOf("Reels"),
                defaultAction = "navigateBack",
                description = "Instagram Reels vertical video viewer"
            )
        )

        // Instagram Explore
        registerTarget(
            InspectionTarget(
                targetId = "ig_explore_tab",
                packageName = PKG_INSTAGRAM,
                subfeature = "explore",
                resourceIdPatterns = listOf("explore_tab", "search_tab", "explore_recycler_view"),
                contentDescriptionPatterns = listOf("Explore", "Search and explore", "Explore tab"),
                textPatterns = emptyList(),
                defaultAction = "navigateBack",
                description = "Instagram Explore discovery grid"
            )
        )

        // YouTube Shorts
        registerTarget(
            InspectionTarget(
                targetId = "yt_shorts_tab",
                packageName = PKG_YOUTUBE,
                subfeature = "reelsOrShorts",
                resourceIdPatterns = listOf("reel_recycler", "reel_player_fragment", "pivot_shorts", "reel_video_view"),
                contentDescriptionPatterns = listOf("Shorts", "Shorts tab", "YouTube Shorts"),
                textPatterns = listOf("Shorts"),
                defaultAction = "navigateBack",
                description = "YouTube Shorts vertical player"
            )
        )

        // Reddit Popular / All
        registerTarget(
            InspectionTarget(
                targetId = "reddit_popular_tab",
                packageName = PKG_REDDIT,
                subfeature = "feed",
                resourceIdPatterns = listOf("popular_list", "feed_recycler_view", "tab_popular"),
                contentDescriptionPatterns = listOf("Popular", "r/popular"),
                textPatterns = listOf("Popular"),
                defaultAction = "navigateBack",
                description = "Reddit infinite popular feed"
            )
        )

        // TikTok For You Page
        registerTarget(
            InspectionTarget(
                targetId = "tiktok_fyp",
                packageName = PKG_TIKTOK,
                subfeature = "reelsOrShorts",
                resourceIdPatterns = listOf("viewpager", "main_view_pager", "vertical_view_pager"),
                contentDescriptionPatterns = listOf("For You", "For You page"),
                textPatterns = listOf("For You"),
                defaultAction = "navigateBack",
                description = "TikTok For You algorithmic video feed"
            )
        )

        // Enable default blocking for reels and explore
        subfeatureToggles["$PKG_INSTAGRAM:reelsOrShorts"] = true
        subfeatureToggles["$PKG_INSTAGRAM:explore"] = true
        subfeatureToggles["$PKG_YOUTUBE:reelsOrShorts"] = true
        subfeatureToggles["$PKG_REDDIT:feed"] = true
        subfeatureToggles["$PKG_TIKTOK:reelsOrShorts"] = true
    }

    fun registerTarget(target: InspectionTarget) {
        val list = targetRegistry.getOrPut(target.packageName) { ArrayList() }
        synchronized(list) {
            list.removeAll { it.targetId == target.targetId }
            list.add(target)
        }
    }

    fun setSubfeatureToggle(packageName: String, subfeature: String, blocked: Boolean) {
        subfeatureToggles["$packageName:$subfeature"] = blocked
    }

    fun isSubfeatureBlocked(packageName: String, subfeature: String): Boolean {
        return subfeatureToggles["$packageName:$subfeature"] ?: true
    }

    /**
     * Inspects the view hierarchy of an incoming accessibility event.
     */
    fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkg = event.packageName?.toString() ?: return

        val targets = targetRegistry[pkg] ?: return
        if (targets.isEmpty()) return

        val rootNode = service.rootInActiveWindow ?: event.source ?: return

        try {
            traverseAndInspectNode(rootNode, targets, pkg, 0)
        } catch (e: Exception) {
            Log.e(TAG, "Error inspecting view node hierarchy: ${e.message}")
        } finally {
            // Note: do not recycle rootNode directly if from service.rootInActiveWindow in modern Android
        }
    }

    /**
     * Recursive DFS traversal with bounded depth.
     */
    private fun traverseAndInspectNode(
        node: AccessibilityNodeInfo?,
        targets: List<InspectionTarget>,
        pkg: String,
        depth: Int
    ) {
        if (node == null || depth > MAX_TREE_DEPTH) return
        totalNodesScanned.incrementAndGet()

        val resId = node.viewIdResourceName?.lowercase()
        val desc = node.contentDescription?.toString()?.lowercase()
        val text = node.text?.toString()?.lowercase()

        for (target in targets) {
            if (!isSubfeatureBlocked(pkg, target.subfeature)) {
                continue
            }

            var matched = false

            // 1. Check resource IDs
            if (resId != null && target.resourceIdPatterns.isNotEmpty()) {
                if (target.resourceIdPatterns.any { resId.contains(it.lowercase()) }) {
                    matched = true
                }
            }

            // 2. Check content descriptions
            if (!matched && desc != null && target.contentDescriptionPatterns.isNotEmpty()) {
                if (target.contentDescriptionPatterns.any { desc.contains(it.lowercase()) }) {
                    matched = true
                }
            }

            // 3. Check visible text
            if (!matched && text != null && target.textPatterns.isNotEmpty()) {
                if (target.textPatterns.any { text.contains(it.lowercase()) }) {
                    matched = true
                }
            }

            if (matched) {
                handleMatchedTarget(target, pkg)
                return // Short-circuit further traversal once subfeature is caught
            }
        }

        // Recursively visit children
        val childCount = node.childCount
        for (i in 0 until childCount) {
            val child = node.getChild(i) ?: continue
            traverseAndInspectNode(child, targets, pkg, depth + 1)
        }
    }

    private fun handleMatchedTarget(target: InspectionTarget, pkg: String) {
        val now = System.currentTimeMillis()
        val signature = "$pkg:${target.targetId}"

        if (signature == lastInterceptionSignature && (now - lastInterceptionTimeMs) < DEBOUNCE_WINDOW_MS) {
            totalDebounceDrops.incrementAndGet()
            return
        }

        lastInterceptionSignature = signature
        lastInterceptionTimeMs = now
        totalViewsIntercepted.incrementAndGet()

        Log.i(TAG, "Surgically intercepted view target: ${target.targetId} in $pkg. Action: ${target.defaultAction}")

        mainHandler.post {
            executeInterceptionAction(target.defaultAction)
            onInterceptionListener?.invoke(pkg, target.subfeature, target.targetId, target.defaultAction)
        }
    }

    private fun executeInterceptionAction(action: String) {
        when (action) {
            "navigateBack" -> {
                service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            }
            "navigateToHome" -> {
                service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            }
            "redirectToDirectMessages" -> {
                // If the app has a direct messages backstack, back action returns there
                service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            }
            "killToHome" -> {
                service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            }
            else -> {
                service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            }
        }
    }

    fun clearAll() {
        targetRegistry.clear()
        subfeatureToggles.clear()
        lastInterceptionSignature = null
        lastInterceptionTimeMs = 0L
    }
}
