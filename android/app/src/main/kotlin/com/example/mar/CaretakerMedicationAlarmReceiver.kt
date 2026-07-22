// android/app/src/main/kotlin/com/example/mar/CaretakerMedicationAlarmReceiver.kt

package com.example.mar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class CaretakerMedicationAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val LOG_TAG = "MAR_ALERTS"

        private const val EXTRA_ALERT_ID = "alertId"
        private const val EXTRA_PATIENT_ID = "patientId"
        private const val EXTRA_PATIENT_NAME = "patientName"
        private const val EXTRA_SCHEDULE_ID = "scheduleId"
        private const val EXTRA_MEDICATION_ID = "medicationId"
        private const val EXTRA_SCHEDULED_FOR_MILLIS =
            "scheduledForMillis"
        private const val EXTRA_ORIGINAL_SCHEDULED_FOR_MILLIS =
            "originalScheduledForMillis"
        private const val EXTRA_MESSAGE = "message"
        private const val EXTRA_ALERT_TYPE = "alertType"
        private const val EXTRA_TTS_REPEAT_COUNT =
            "ttsRepeatCount"

        private const val ALERT_TYPE_DUE =
            "caretaker_medication_due"

        private const val ALERT_TYPE_NOT_TAKEN =
            "caretaker_medication_not_taken"
    }

    override fun onReceive(
        context: Context,
        intent: Intent
    ) {
        val alertId =
            intent.getStringExtra(EXTRA_ALERT_ID)
                ?.trim()
                .orEmpty()

        val patientId =
            intent.getStringExtra(EXTRA_PATIENT_ID)
                ?.trim()
                .orEmpty()

        val patientName =
            intent.getStringExtra(EXTRA_PATIENT_NAME)
                ?.trim()
                .orEmpty()
                .ifBlank {
                    "the patient"
                }

        val scheduleId =
            intent.getStringExtra(EXTRA_SCHEDULE_ID)
                ?.trim()
                .orEmpty()

        val medicationId =
            intent.getStringExtra(EXTRA_MEDICATION_ID)
                ?.trim()
                .orEmpty()

        val scheduledForMillis =
            intent.getLongExtra(
                EXTRA_SCHEDULED_FOR_MILLIS,
                0L
            )

        val originalScheduledForMillis =
            intent.getLongExtra(
                EXTRA_ORIGINAL_SCHEDULED_FOR_MILLIS,
                scheduledForMillis
            )

        val alertType =
            intent.getStringExtra(EXTRA_ALERT_TYPE)
                ?.trim()
                .orEmpty()
                .ifBlank {
                    ALERT_TYPE_DUE
                }

        val repeatCount =
            intent.getIntExtra(
                EXTRA_TTS_REPEAT_COUNT,
                1
            ).coerceIn(1, 3)

        val suppliedMessage =
            intent.getStringExtra(EXTRA_MESSAGE)
                ?.trim()
                .orEmpty()

        if (alertId.isBlank() ||
            patientId.isBlank() ||
            scheduleId.isBlank() ||
            medicationId.isBlank() ||
            scheduledForMillis <= 0L
        ) {
            Log.e(
                LOG_TAG,
                "Invalid caretaker medication alarm payload: " +
                        "alertId=$alertId, " +
                        "patientId=$patientId, " +
                        "scheduleId=$scheduleId, " +
                        "medicationId=$medicationId, " +
                        "scheduledFor=$scheduledForMillis"
            )
            return
        }

        val message =
            suppliedMessage.ifBlank {
                when (alertType) {
                    ALERT_TYPE_NOT_TAKEN ->
                        "The medication for $patientName " +
                                "scheduled at " +
                                formatTime(
                                    originalScheduledForMillis
                                ) +
                                " has not been taken. " +
                                "Please check on them."

                    else ->
                        "It is time for $patientName " +
                                "to take the medication. " +
                                "Kindly monitor them."
                }
            }

        Log.d(
            LOG_TAG,
            "Caretaker medication alert received: " +
                    "alertId=$alertId, " +
                    "type=$alertType, " +
                    "patient=$patientName"
        )

        val serviceIntent =
            Intent(
                context,
                TtsSpeakService::class.java
            ).apply {
                action =
                    TtsSpeakService.ACTION_START

                /*
                 * These values identify the caretaker medication alert.
                 * TtsSpeakService must handle the caretaker medication mode
                 * as TTS-only: no MP3, no vibration and no flashlight.
                 */
                putExtra(
                    "alertMode",
                    TtsSpeakService.MODE_CARETAKER_MEDICATION
                )

                putExtra(
                    "message",
                    message
                )

                putExtra(
                    "payload",
                    ""
                )

                putExtra(
                    "soundResource",
                    ""
                )

                putExtra(
                    "loopSound",
                    false
                )

                putExtra(
                    "launchScanner",
                    false
                )

                putExtra(
                    "vibrationMode",
                    TtsSpeakService.VIBRATION_NONE
                )

                putExtra(
                    "ttsRepeatCount",
                    repeatCount
                )

                putExtra(
                    "alertId",
                    alertId
                )

                putExtra(
                    "patientId",
                    patientId
                )

                putExtra(
                    "patientName",
                    patientName
                )

                putExtra(
                    "scheduleId",
                    scheduleId
                )

                putExtra(
                    "medicationId",
                    medicationId
                )

                putExtra(
                    "scheduledForMillis",
                    scheduledForMillis
                )

                putExtra(
                    "originalScheduledForMillis",
                    originalScheduledForMillis
                )

                putExtra(
                    "alertType",
                    alertType
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
                @Suppress("DEPRECATION")
                context.startService(
                    serviceIntent
                )
            }

            Log.d(
                LOG_TAG,
                "Caretaker medication TTS service started"
            )
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "Could not start caretaker medication TTS",
                error
            )
        }
    }

    private fun formatTime(
        milliseconds: Long
    ): String {
        if (milliseconds <= 0L) {
            return "the scheduled time"
        }

        val calendar =
            java.util.Calendar.getInstance().apply {
                timeInMillis = milliseconds
            }

        val hour =
            calendar.get(java.util.Calendar.HOUR)

        val minute =
            calendar.get(java.util.Calendar.MINUTE)
                .toString()
                .padStart(2, '0')

        val period =
            if (
                calendar.get(java.util.Calendar.AM_PM) ==
                java.util.Calendar.AM
            ) {
                "AM"
            } else {
                "PM"
            }

        val displayHour =
            if (hour == 0) 12 else hour

        return "$displayHour:$minute $period"
    }
}