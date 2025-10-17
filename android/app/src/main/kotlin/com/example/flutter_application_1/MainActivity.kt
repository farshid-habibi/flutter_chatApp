package com.example.flutter_application_1

import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.flutter/notifications"
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "playNotification") {
                try {
                    if (mediaPlayer == null) {
                        mediaPlayer = MediaPlayer.create(this, R.raw.notify)
                    }
                    mediaPlayer?.start()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to play sound", e)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
