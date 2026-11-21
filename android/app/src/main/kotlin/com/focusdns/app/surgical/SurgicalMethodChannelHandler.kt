package com.focusdns.app.surgical

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * SurgicalMethodChannelHandler acts as the bidirectional bridge between
 * Flutter Surgical Studio and native Android packet filtering / accessibility services.
 */
class SurgicalMethodChannelHandler(
    private val context: Context,
    private val viewHierarchyInspector: SurgicalViewHierarchyInspector?,
    private val packetInterceptor: SurgicalPacketInterceptor?
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val TAG = "SurgicalChannel"
        const val METHOD_CHANNEL_NAME = "com.focusdns.app/surgical"
        const val EVENT_CHANNEL_NAME = "com.focusdns.app/surgical_events"

        @Volatile
        var instance: SurgicalMethodChannelHandler? = null
            private set

        fun registerWith(
            messenger: BinaryMessenger,
            context: Context,
            viewInspector: SurgicalViewHierarchyInspector?,
            packetFilter: SurgicalPacketInterceptor?
        ): SurgicalMethodChannelHandler {
            val handler = SurgicalMethodChannelHandler(context, viewInspector, packetFilter)
            instance = handler

            val methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
            methodChannel.setMethodCallHandler(handler)

            val eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)
            eventChannel.setStreamHandler(handler)

            Log.i(TAG, "SurgicalMethodChannelHandler registered successfully.")
            return handler
        }
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val isGlobalEnabled = AtomicBoolean(true)

    init {
        // Wire live view interception events to Flutter EventSink
        viewHierarchyInspector?.onInterceptionListener = { pkg, subfeature, targetId, action ->
            sendLiveEventToFlutter(
                mapOf(
                    "eventType" to "viewInterception",
                    "timestamp" to System.currentTimeMillis(),
                    "packageName" to pkg,
                    "subfeature" to subfeature,
                    "targetId" to targetId,
                    "actionApplied" to action
                )
            )
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSurgicalEnabled" -> {
                result.success(isGlobalEnabled.get())
            }

            "setGlobalSurgicalEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                isGlobalEnabled.set(enabled)
                result.success(true)
            }

            "updateSubfeatureToggle" -> {
                val pkg = call.argument<String>("packageName") ?: ""
                val subfeature = call.argument<String>("subfeature") ?: ""
                val blocked = call.argument<Boolean>("blocked") ?: true

                viewHierarchyInspector?.setSubfeatureToggle(pkg, subfeature, blocked)
                result.success(true)
            }

            "querySurgicalStats" -> {
                val stats = mapOf(
                    "totalPacketsInspected" to (packetInterceptor?.totalPacketsInspected?.get() ?: 0L),
                    "totalCdnPacketsBlocked" to (packetInterceptor?.totalCdnPacketsBlocked?.get() ?: 0L),
                    "totalChatPacketsAllowed" to (packetInterceptor?.totalChatPacketsAllowed?.get() ?: 0L),
                    "totalBytesIntercepted" to (packetInterceptor?.totalBytesIntercepted?.get() ?: 0L),
                    "totalNodesScanned" to (viewHierarchyInspector?.totalNodesScanned?.get() ?: 0L),
                    "totalViewsIntercepted" to (viewHierarchyInspector?.totalViewsIntercepted?.get() ?: 0L),
                    "totalDebounceDrops" to (viewHierarchyInspector?.totalDebounceDrops?.get() ?: 0L),
                    "isGlobalEnabled" to isGlobalEnabled.get()
                )
                result.success(stats)
            }

            "registerCustomTarget" -> {
                val targetId = call.argument<String>("targetId") ?: "custom_${System.currentTimeMillis()}"
                val packageName = call.argument<String>("packageName") ?: ""
                val subfeature = call.argument<String>("subfeature") ?: "feed"
                val resPatterns = call.argument<List<String>>("resourceIdPatterns") ?: emptyList()
                val descPatterns = call.argument<List<String>>("contentDescriptionPatterns") ?: emptyList()
                val textPatterns = call.argument<List<String>>("textPatterns") ?: emptyList()
                val action = call.argument<String>("defaultAction") ?: "navigateBack"
                val description = call.argument<String>("description") ?: "Custom surgical rule"

                viewHierarchyInspector?.registerTarget(
                    SurgicalViewHierarchyInspector.InspectionTarget(
                        targetId = targetId,
                        packageName = packageName,
                        subfeature = subfeature,
                        resourceIdPatterns = resPatterns,
                        contentDescriptionPatterns = descPatterns,
                        textPatterns = textPatterns,
                        defaultAction = action,
                        description = description
                    )
                )
                result.success(true)
            }

            "addSeveredDomain" -> {
                val domain = call.argument<String>("domain") ?: ""
                if (domain.isNotEmpty()) {
                    packetInterceptor?.addSeveredDomain(domain)
                }
                result.success(true)
            }

            "addAllowedChatGateway" -> {
                val domain = call.argument<String>("domain") ?: ""
                if (domain.isNotEmpty()) {
                    packetInterceptor?.addAllowedChatGateway(domain)
                }
                result.success(true)
            }

            "simulateViewInterception" -> {
                val pkg = call.argument<String>("packageName") ?: "com.instagram.android"
                val sub = call.argument<String>("subfeature") ?: "reelsOrShorts"
                val target = call.argument<String>("targetId") ?: "simulated_target"
                val act = call.argument<String>("action") ?: "navigateBack"

                sendLiveEventToFlutter(
                    mapOf(
                        "eventType" to "viewInterception",
                        "timestamp" to System.currentTimeMillis(),
                        "packageName" to pkg,
                        "subfeature" to sub,
                        "targetId" to target,
                        "actionApplied" to act,
                        "isSimulated" to true
                    )
                )
                result.success(true)
            }

            "clearAllRules" -> {
                viewHierarchyInspector?.clearAll()
                packetInterceptor?.clearAll()
                result.success(true)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        Log.i(TAG, "Flutter EventSink subscribed to surgical live stream.")
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        Log.i(TAG, "Flutter EventSink unsubscribed from surgical live stream.")
    }

    private fun sendLiveEventToFlutter(data: Map<String, Any?>) {
        mainHandler.post {
            try {
                eventSink?.success(data)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send live surgical event to Flutter: ${e.message}")
            }
        }
    }
}
