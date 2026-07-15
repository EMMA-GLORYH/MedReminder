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

        private const val MODE_MEDICATION_DUE =
            "medication_due"

        private const val MODE_PRIOR_REMINDER =
            "prior_reminder"

        private const val MODE_CARETAKER_SOS =
            "caretaker_sos"

        private const val VIBRATION_CONTINUOUS =
            "continuous"

        private const val VIBRATION_FIVE_PULSES =
            "five_pulses"

        private const val VIBRATION_NONE =
            "none"

        private const val DEFAULT_TTS_REPEAT_COUNT = 3
    }

    override fun onReceive(
        context: Context,
        intent: Intent
    ) {
        val alarmId =
            intent.getIntExtra(
                "alarmId",
                0
            )

        val payload =
            intent.getStringExtra("payload")
                ?.trim()
                .orEmpty()

        val alertMode = normalizeAlertMode(
            intent.getStringExtra("alertMode")
        )

        val message =
            intent.getStringExtra("message")
                ?.trim()
                ?.takeIf { it.isNotBlank() }
                ?: defaultMessage(alertMode)

        val soundResource =
            intent.getStringExtra("soundResource")
                ?.trim()
                ?.lowercase()
                ?.takeIf { it.isNotBlank() }
                ?: defaultSoundResource(alertMode)

        val loopSound =
            if (intent.hasExtra("loopSound")) {
                intent.getBooleanExtra(
                    "loopSound",
                    defaultLoopSound(alertMode)
                )
            } else {
                defaultLoopSound(alertMode)
            }

        /*
         * Only an exact medication-due alarm is allowed to launch the
         * medication confirmation screen.
         *
         * Prior reminders and caretaker SOS alerts cannot launch the
         * scanner, even if malformed or legacy extras incorrectly request
         * scanner opening.
         */
        val requestedScannerLaunch =
            if (intent.hasExtra("launchScanner")) {
                intent.getBooleanExtra(
                    "launchScanner",
                    defaultLaunchScanner(
                        alertMode,
                        payload
                    )
                )
            } else {
                defaultLaunchScanner(
                    alertMode,
                    payload
                )
            }

        val launchScanner =
            alertMode == MODE_MEDICATION_DUE &&
                    payload.isNotBlank() &&
                    requestedScannerLaunch

        val vibrationMode = normalizeVibrationMode(
            intent.getStringExtra("vibrationMode"),
            alertMode
        )

        val ttsRepeatCount =
            intent.getIntExtra(
                "ttsRepeatCount",
                DEFAULT_TTS_REPEAT_COUNT
            ).coerceIn(0, 10)

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
                    "ttsRepeats=$ttsRepeatCount"
        )

        val serviceIntent = Intent(
            context,
            TtsSpeakService::class.java
        ).apply {
            action = TtsSpeakService.ACTION_START

            putExtra(
                "alarmId",
                alarmId
            )

            putExtra(
                "message",
                message
            )

            /*
             * The due-dose payload contains the medicine identity,
             * scheduled time, dosage and pillImageUrl. TtsSpeakService
             * passes it to MainActivity so Flutter can open the screen
             * independently of the user's login state.
             */
            putExtra(
                "payload",
                payload
            )

            putExtra(
                "alertMode",
                alertMode
            )

            putExtra(
                "soundResource",
                soundResource
            )

            putExtra(
                "loopSound",
                loopSound
            )

            putExtra(
                "launchScanner",
                launchScanner
            )

            putExtra(
                "vibrationMode",
                vibrationMode
            )

            putExtra(
                "ttsRepeatCount",
                ttsRepeatCount
            )
        }

        try {
            if (Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.O
            ) {
                context.startForegroundService(
                    serviceIntent
                )
            } else {
                context.startService(
                    serviceIntent
                )
            }

            Log.d(
                LOG_TAG,
                "TtsSpeakService started for " +
                        "alarm $alarmId, mode=$alertMode"
            )
        } catch (error: Exception) {
            /*
             * This should not crash the BroadcastReceiver. Some Android
             * manufacturers may restrict foreground-service starts under
             * aggressive battery-management settings.
             */
            Log.e(
                LOG_TAG,
                "Failed to start TtsSpeakService for " +
                        "alarm $alarmId, mode=$alertMode",
                error
            )
        }
    }

    // ══════════════════════════════════════════════════════════════
    // VALUE NORMALIZATION
    // ══════════════════════════════════════════════════════════════

    private fun normalizeAlertMode(
        rawMode: String?
    ): String {
        return when (
            rawMode
                ?.trim()
                ?.lowercase()
        ) {
            MODE_PRIOR_REMINDER ->
                MODE_PRIOR_REMINDER

            MODE_CARETAKER_SOS ->
                MODE_CARETAKER_SOS

            MODE_MEDICATION_DUE ->
                MODE_MEDICATION_DUE

            else ->
                MODE_MEDICATION_DUE
        }
    }

    private fun normalizeVibrationMode(
        rawMode: String?,
        alertMode: String
    ): String {
        return when (
            rawMode
                ?.trim()
                ?.lowercase()
        ) {
            VIBRATION_CONTINUOUS ->
                VIBRATION_CONTINUOUS

            VIBRATION_FIVE_PULSES ->
                VIBRATION_FIVE_PULSES

            VIBRATION_NONE ->
                VIBRATION_NONE

            else ->
                defaultVibrationMode(alertMode)
        }
    }

    // ══════════════════════════════════════════════════════════════
    // BACKWARD-COMPATIBLE DEFAULTS
    // ══════════════════════════════════════════════════════════════

    private fun defaultMessage(
        alertMode: String
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
        alertMode: String
    ): String {
        return when (alertMode) {
            MODE_PRIOR_REMINDER ->
                "prior_reminder"

            MODE_CARETAKER_SOS ->
                "caretaker_sos"

            else ->
                "alarm"
        }
    }

    private fun defaultLoopSound(
        alertMode: String
    ): Boolean {
        return when (alertMode) {
            MODE_PRIOR_REMINDER ->
                false

            MODE_CARETAKER_SOS ->
                true

            else ->
                true
        }
    }

    private fun defaultLaunchScanner(
        alertMode: String,
        scannerPayload: String
    ): Boolean {
        return alertMode == MODE_MEDICATION_DUE &&
                scannerPayload.isNotBlank()
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