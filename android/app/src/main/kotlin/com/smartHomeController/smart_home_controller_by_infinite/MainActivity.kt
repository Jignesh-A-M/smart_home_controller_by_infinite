package com.smartHomeController.smart_home_controller_by_infinite

import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.service.quicksettings.TileService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingRequest: Map<String, String>? = null

    // Capture an explicit tile request before Flutter starts its connection flow.
    override fun onCreate(savedInstanceState: Bundle?) {
        captureRequest(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "infinite_home/quick_tile")
        channel?.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("favourite_scene_tile", MODE_PRIVATE)
            when (call.method) {
                "isSupported" -> result.success(true)
                "consumeRequest" -> {
                    val request = pendingRequest
                    pendingRequest = null
                    request?.get("token")?.let { prefs.edit().putString("last_consumed_token", it).apply() }
                    result.success(request)
                }
                "setSelection" -> {
                    prefs.edit()
                        .putString("scene_id", call.argument<String>("sceneId") ?: "")
                        .putString("scene_name", call.argument<String>("sceneName") ?: "Favourite scene")
                        .apply()
                    TileService.requestListeningState(this, ComponentName(this, FavouriteSceneTileService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Deliver a new tile tap to the existing app without restarting its scene state.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureRequest(intent)
        if (pendingRequest != null) channel?.invokeMethod("quickSceneRequested", null)
    }

    private fun captureRequest(intent: Intent?) {
        if (intent?.action != FavouriteSceneTileService.RUN_SCENE) return
        val token = intent.getStringExtra("request_token") ?: return
        val prefs = getSharedPreferences("favourite_scene_tile", MODE_PRIVATE)
        if (token == prefs.getString("last_consumed_token", null)) return
        pendingRequest = mapOf("sceneId" to (intent.getStringExtra("scene_id") ?: ""), "token" to token)
    }
}
