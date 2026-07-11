// android/app/src/main/kotlin/com/example/mar/TtsAlarmReceiver.kt

package com.example.mar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TtsAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val message = intent.getStringExtra("message") ?: return

        val startIntent = Intent(context, TtsSpeakService::class.java).apply {
            action = TtsSpeakService.ACTION_START
            putExtra("message", message)
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(startIntent)
        } else {
            context.startService(startIntent)
        }
    }
}