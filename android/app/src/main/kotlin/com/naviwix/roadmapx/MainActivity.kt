package com.naviwix.roadmapx

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Receives text shared from other apps ("Share → RoadmapX") and hands it to
 * Flutter, which opens quick capture pre-filled with it.
 */
class MainActivity : FlutterActivity() {
    private var sharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureShare(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "roadmapx/share")
            .setMethodCallHandler { call, result ->
                if (call.method == "takeSharedText") {
                    // Hand it over once, so it is not captured twice.
                    result.success(sharedText)
                    sharedText = null
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShare(intent)
    }

    private fun captureShare(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()
            sharedText = listOfNotNull(subject, text)
                .filter { it.isNotEmpty() }
                .distinct()
                .joinToString(" — ")
                .ifEmpty { null }
        }
    }
}
