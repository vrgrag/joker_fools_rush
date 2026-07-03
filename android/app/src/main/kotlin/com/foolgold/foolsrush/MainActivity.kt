package com.foolgold.foolsrush

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.foolgold.foolsrush/webview_native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Walks the current view hierarchy, finds every native
                    // WebView instance created by webview_flutter_android and
                    // forces the settings that make it render like Chrome
                    // Mobile (respect meta viewport, fit content to screen).
                    "applyChromeLikeSettings" -> {
                        val root = window?.decorView as? ViewGroup
                        val count = if (root != null) configureWebViews(root) else 0
                        result.success(count)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureWebViews(root: ViewGroup): Int {
        var count = 0
        for (i in 0 until root.childCount) {
            val child: View = root.getChildAt(i)
            if (child is WebView) {
                val s = child.settings
                // Respect the site's own <meta viewport>. This alone makes
                // WebView render at the same CSS scale as Chrome Mobile.
                s.useWideViewPort = true
                // Explicitly disable overview-fit — it shrinks the page to
                // fit inside a legacy 980px viewport, which is exactly the
                // "zoomed out" look we do NOT want.
                s.loadWithOverviewMode = false
                s.domStorageEnabled = true
                s.javaScriptEnabled = true
                s.textZoom = 100
                count++
            } else if (child is ViewGroup) {
                count += configureWebViews(child)
            }
        }
        return count
    }
}
