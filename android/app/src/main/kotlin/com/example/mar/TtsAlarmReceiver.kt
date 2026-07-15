// android/app/src/main/kotlin/com/example/mar/TtsAlarmReceiver.kt

package com.example.mar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class TtsAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val LOG_TAG = "MAR_ALERTS"

        private const val MODE_MEDICATION_DUE = "medication_due"
        private const val MODE_PRIOR_REMINDER = "prior_reminder"
        private const val MODE_CARETAKER_SOS = "caretaker_sos"

        private const val VIBRATION_CONTINUOUS = "continuous"
        private const val VIBRATION_FIVE_PULSES = "five_pulses"
    }

    override fun onReceive(
        context: Context,
        intent: Intent
    ) {
        val alarmId = intent.getIntExtra("alarmId", 0)

        val message = intent
            .getStringExtra("message")
            .orEmpty()
            .ifBlank {
                "It is time to check your medication reminder."
            }

        val payload = intent
            .getStringExtra("payload")
            .orEmpty()

        /*
         * Backward compatibility:
         *
         * Old alarms do not contain alertMode. They should continue
         * working as normal medication-due alerts.
         */
        val alertMode = intent
            .getStringExtra("alertMode")
            ?: MODE_MEDICATION_DUE

        val soundResource = intent
            .getStringExtra("soundResource")
            ?: defaultSoundResource(alertMode)

        val loopSound = if (intent.hasExtra("loopSound")) {
            intent.getBooleanExtra("loopSound", true)
        } else {
            defaultLoopSound(alertMode)
        }

        val launchScanner = if (intent.hasExtra("launchScanner")) {
            intent.getBooleanExtra("launchScanner", false)
        } else {
            defaultLaunchScanner(
                alertMode = alertMode,
                payload = payload
            )
        }

        val vibrationMode = intent
            .getStringExtra("vibrationMode")
            ?: defaultVibrationMode(alertMode)

        val ttsRepeatCount = intent
            .getIntExtra("ttsRepeatCount", 3)
            .coerceIn(0, 10)

        Log.d(
            LOG_TAG,
            "Alarm received: " +
                    "id=$alarmId, " +
                    "mode=$alertMode, " +
                    "sound=$soundResource, " +
                    "loop=$loopSound, " +
                    "scanner=$launchScanner, " +
                    "vibration=$vibrationMode, " +
                    "ttsRepeats=$ttsRepeatCount"
        )

        val startIntent = Intent(
            context,
            TtsSpeakService::class.java
        ).apply {
            action = TtsSpeakService.ACTION_START

            putExtra("alarmId", alarmId)
            putExtra("message", message)
            putExtra("payload", payload)

            // New alert configuration.
            putExtra("alertMode", alertMode)
            putExtra("soundResource", soundResource)
            putExtra("loopSound", loopSound)
            putExtra("launchScanner", launchScanner)
            putExtra("vibrationMode", vibrationMode)
            putExtra("ttsRepeatCount", ttsRepeatCount)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(startIntent)
            } else {
                context.startService(startIntent)
            }

            Log.d(
                LOG_TAG,
                "TTS foreground service started for $alertMode"
            )
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "Failed to start TTS service for $alertMode",
                error
            )
        }
    }

    // ══════════════════════════════════════════════════════════
    // BACKWARD-COMPATIBLE DEFAULTS
    // ══════════════════════════════════════════════════════════

    private fun defaultSoundResource(
        alertMode: String
    ): String {
        return when (alertMode) {
            MODE_PRIOR_REMINDER -> "prior_reminder"
            MODE_CARETAKER_SOS -> "caretaker_sos"
            else -> "alarm"
        }
    }

    private fun defaultLoopSound(
        alertMode: String
    ): Boolean {
        return when (alertMode) {
            MODE_PRIOR_REMINDER -> false
            MODE_CARETAKER_SOS -> true
            else -> true
        }
    }

    private fun defaultLaunchScanner(
        alertMode: String,
        payload: String
    ): Boolean {
        return alertMode == MODE_MEDICATION_DUE &&
                payload.isNotBlank()
    }

    private fun defaultVibrationMode(
        alertMode: String
    ): String {
        return when (alertMode) {
            MODE_PRIOR_REMINDER ->
                VIBRATION_FIVE_PULSES

            MODE_CARETAKER_SOS ->
                VIBRATION_CONTINUOUS

            else ->
                VIBRATION_CONTINUOUS
        }
    }
}