package com.smartHomeController.smart_home_controller_by_infinite

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import java.util.UUID

class FavouriteSceneTileService : TileService() {
    companion object {
        const val RUN_SCENE = "com.smartHomeController.smart_home_controller_by_infinite.RUN_FAVOURITE_SCENE"
    }

    // A scene tile is an action, so its appearance does not pretend to show hub connectivity.
    override fun onStartListening() {
        super.onStartListening()
        val prefs = getSharedPreferences("favourite_scene_tile", MODE_PRIVATE)
        qsTile?.apply {
            label = prefs.getString("scene_name", "Favourite scene")
            state = Tile.STATE_INACTIVE
            if (Build.VERSION.SDK_INT >= 29) subtitle = "Tap to run in app"
            updateTile()
        }
    }

    // Open the app for bounded connection checks and the normal scene execution flow.
    override fun onClick() {
        super.onClick()
        val launch = Runnable {
            val prefs = getSharedPreferences("favourite_scene_tile", MODE_PRIVATE)
            val intent = Intent(this, MainActivity::class.java)
                .setAction(RUN_SCENE)
                .putExtra("scene_id", prefs.getString("scene_id", ""))
                .putExtra("request_token", UUID.randomUUID().toString())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        }
        if (isLocked) unlockAndRun(launch) else launch.run()
    }
}
