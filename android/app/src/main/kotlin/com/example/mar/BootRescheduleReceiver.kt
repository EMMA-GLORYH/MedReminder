package com.example.mar

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject

class BootRescheduleReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val validActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )
        if (intent.action !in validActions) return

        // Default file used by the shared_preferences plugin on Android.
        // If you're on a newer shared_preferences_android version that has
        // migrated storage, double-check this file name matches — you can
        // confirm via `adb shell run-as <pkg> ls shared_prefs`.
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        for ((key, value) in prefs.all) {
            if (!key.startsWith("flutter.cached_dose_payload_")) continue
            val payload = value as? String ?: continue

            try {
                val json = JSONObject(payload)
                val scheduledForMillis = json.optLong("scheduledForMillis", -1L)
                val ttsAlarmId = json.optInt("ttsAlarmId", -1)
                if (scheduledForMillis <= now || ttsAlarmId == -1) continue

                val medicationName = json.optString("medicationName", "your medicine")
                val dosageDisplay  = json.optString("dosageDisplay", "")
                val message = "It is time to take $medicationName. " +
                        "Dosage: $dosageDisplay. Please scan the medicine now."

                val alarmIntent = Intent(context, TtsAlarmReceiver::class.java).apply {
                    putExtra("alarmId", ttsAlarmId)
                    putExtra("message", message)
                    putExtra("payload", payload)
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context, ttsAlarmId, alarmIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, scheduledForMillis, pendingIntent
                    )
                } else {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP, scheduledForMillis, pendingIntent
                    )
                }
            } catch (_: Exception) {
                // Skip malformed/legacy cached entries rather than crash the receiver
            }
        }
    }
}