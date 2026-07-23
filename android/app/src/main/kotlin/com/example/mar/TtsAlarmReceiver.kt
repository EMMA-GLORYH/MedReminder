// android/app/src/main/kotlin/com/example/mar/TtsAlarmReceiver.kt

package com.example.mar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

class TtsAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val LOG_TAG = "MAR_ALERTS"

        private const val MODE_MEDICATION_DUE = "medication_due"
        private const val MODE_PRIOR_REMINDER = "prior_reminder"
        private const val MODE_CARETAKER_SOS = "caretaker_sos"

        private const val VIBRATION_CONTINUOUS = "continuous"
        private const val VIBRATION_FIVE_PULSES = "five_pulses"
        private const val VIBRATION_NONE = "none"

        private const val DEFAULT_TTS_REPEAT_COUNT = 3
    }

    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val alarmId = intent.getIntExtra("alarmId", 0)

        val payload = intent
            .getStringExtra("payload")
            ?.trim()
            .orEmpty()

        val alertMode = normalizeAlertMode(
            intent.getStringExtra("alertMode"),
        )

        val message = intent
            .getStringExtra("message")
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: defaultMessage(alertMode)

        val soundResource = intent
            .getStringExtra("soundResource")
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotBlank() }
            ?: defaultSoundResource(alertMode)

        val loopSound = if (intent.hasExtra("loopSound")) {
            intent.getBooleanExtra(
                "loopSound",
                defaultLoopSound(alertMode),
            )
        } else {
            defaultLoopSound(alertMode)
        }

        /*
         * Only medication_due alerts may open the scanner/confirmation
         * screen. Prior reminder and SOS alerts can never trigger it.
         */
        val requestedScannerLaunch = if (intent.hasExtra("launchScanner")) {
            intent.getBooleanExtra(
                "launchScanner",
                defaultLaunchScanner(alertMode, payload),
            )
        } else {
            defaultLaunchScanner(alertMode, payload)
        }

        val launchScanner = alertMode == MODE_MEDICATION_DUE &&
                payload.isNotBlank() &&
                requestedScannerLaunch

        val vibrationMode = normalizeVibrationMode(
            intent.getStringExtra("vibrationMode"),
            alertMode,
        )

        val ttsRepeatCount = intent
            .getIntExtra(
                "ttsRepeatCount",
                DEFAULT_TTS_REPEAT_COUNT,
            )
            .coerceIn(0, 10)

        /*
         * Flashlight defaults:
         *
         * - medication_due: true
         * - prior_reminder: false
         * - caretaker_sos: true
         *
         * TtsSpeakService must treat this as a best-effort feature.
         * If Android denies torch access, TTS, vibration, and sound
         * must continue without crashing.
         */
        val flashlight = if (intent.hasExtra("flashlight")) {
            intent.getBooleanExtra(
                "flashlight",
                defaultFlashlightEnabled(alertMode),
            )
        } else {
            defaultFlashlightEnabled(alertMode)
        }

        Log.d(
            LOG_TAG,
            "Alarm received: " +
                    "id=$alarmId, " +
                    "mode=$alertMode, " +
                    "sound=$soundResource, " +
                    "loop=$loopSound, " +
                    "scanner=$launchScanner, " +
                    "payload=${payload.isNotBlank()}, " +
                    "vibration=$vibrationMode, " +
                    "flashlight=$flashlight, " +
                    "ttsRepeats=$ttsRepeatCount",
        )

        val serviceIntent = Intent(
            context,
            TtsSpeakService::class.java,
        ).apply {
            action = TtsSpeakService.ACTION_START

            putExtra("alarmId", alarmId)
            putExtra("message", message)
            putExtra("payload", payload)
            putExtra("alertMode", alertMode)
            putExtra("soundResource", soundResource)
            putExtra("loopSound", loopSound)
            putExtra("launchScanner", launchScanner)
            putExtra("vibrationMode", vibrationMode)
            putExtra("ttsRepeatCount", ttsRepeatCount)

            // ✅ Forward flashlight request to TtsSpeakService.
            putExtra("flashlight", flashlight)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(
                    context,
                    serviceIntent,
                )
            } else {
                context.startService(serviceIntent)
            }

            Log.d(
                LOG_TAG,
                "TtsSpeakService started for alarm=$alarmId, " +
                        "mode=$alertMode, flashlight=$flashlight",
            )
        } catch (error: Exception) {
            /*
             * The BroadcastReceiver must never crash the app process.
             * Some devices may restrict background foreground-service starts.
             */
            Log.e(
                LOG_TAG,
                "Failed to start TtsSpeakService for " +
                        "alarm=$alarmId, mode=$alertMode",
                error,
            )
        }
    }

    // ══════════════════════════════════════════════════════════════
    // VALUE NORMALIZATION
    // ══════════════════════════════════════════════════════════════

    private fun normalizeAlertMode(
        rawMode: String?,
    ): String {
        return when (rawMode?.trim()?.lowercase()) {
            MODE_PRIOR_REMINDER -> MODE_PRIOR_REMINDER
            MODE_CARETAKER_SOS -> MODE_CARETAKER_SOS
            MODE_MEDICATION_DUE -> MODE_MEDICATION_DUE
            else -> MODE_MEDICATION_DUE
        }
    }

    private fun normalizeVibrationMode(
        rawMode: String?,
        alertMode: String,
    ): String {
        return when (rawMode?.trim()?.lowercase()) {
            VIBRATION_CONTINUOUS -> VIBRATION_CONTINUOUS
            VIBRATION_FIVE_PULSES -> VIBRATION_FIVE_PULSES
            VIBRATION_NONE -> VIBRATION_NONE
            else -> defaultVibrationMode(alertMode)
        }
    }

    // ══════════════════════════════════════════════════════════════
    // DEFAULTS
    // ══════════════════════════════════════════════════════════════

    private fun defaultMessage(
        alertMode: String,
    ): String {
        return when (alertMode) {
            MODE_PRIOR_REMINDER ->
                "A medication dose is due soon."

            MODE_CARETAKER_SOS ->
                "Urgent patient SOS. Please respond immediately."

            else ->
                "It is time to check your medication reminder."
        }
    }

    private fun defaultSoundResource(
        alertMode: String,
    ): String {
        return when (alertMode) {
            MODE_PRIOR_REMINDER -> "prior_reminder"
            MODE_CARETAKER_SOS -> "caretaker_sos"
            else -> "alarm"
        }
    }

    private fun defaultLoopSound(
        alertMode: String,
    ): Boolean {
        return when (alertMode) {
            MODE_PRIOR_REMINDER -> false
            MODE_CARETAKER_SOS -> true
            else -> true
        }
    }

    private fun defaultLaunchScanner(
        alertMode: String,
        scannerPayload: String,
    ): Boolean {
        return alertMode == MODE_MEDICATION_DUE &&
                scannerPayload.isNotBlank()
    }

    private fun defaultVibrationMode(
        alertMode: String,
    ): String {
        return when (alertMode) {
            MODE_PRIOR_REMINDER -> VIBRATION_FIVE_PULSES
            MODE_CARETAKER_SOS -> VIBRATION_CONTINUOUS
            else -> VIBRATION_CONTINUOUS
        }
    }

    private fun defaultFlashlightEnabled(
        alertMode: String,
    ): Boolean {
        return when (alertMode) {
            MODE_MEDICATION_DUE -> true
            MODE_CARETAKER_SOS -> true
            MODE_PRIOR_REMINDER -> false
            else -> false
        }
    }
}