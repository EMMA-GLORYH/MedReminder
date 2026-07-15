// android/app/src/main/kotlin/com/example/mar/BootRescheduleReceiver.kt

package com.example.mar

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONObject

class BootRescheduleReceiver : BroadcastReceiver() {

    companion object {
        private const val LOG_TAG = "MAR_ALERTS"

        private const val SHARED_PREFERENCES_FILE =
            "FlutterSharedPreferences"

        /*
         * shared_preferences stores Dart keys with the "flutter." prefix
         * in the Android SharedPreferences file.
         */
        private const val PAYLOAD_KEY_PREFIX =
            "flutter.cached_dose_payload_"

        private const val PRIOR_REMINDER_OFFSET_MS =
            10L * 60L * 1000L

        private const val MODE_MEDICATION_DUE =
            "medication_due"

        private const val MODE_PRIOR_REMINDER =
            "prior_reminder"

        private const val VIBRATION_CONTINUOUS =
            "continuous"

        private const val VIBRATION_FIVE_PULSES =
            "five_pulses"

        private const val DEFAULT_TTS_REPEAT_COUNT = 3
    }

    override fun onReceive(
        context: Context,
        intent: Intent
    ) {
        val validActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )

        if (intent.action !in validActions) {
            return
        }

        Log.d(
            LOG_TAG,
            "Boot/update event received: ${intent.action}"
        )

        /*
         * onReceive should finish quickly, but SharedPreferences iteration
         * and alarm registration can still take some time. goAsync allows
         * the work to continue safely outside the immediate callback.
         */
        val pendingResult = goAsync()

        Thread {
            try {
                restoreCachedMedicationAlarms(context)
            } catch (error: Exception) {
                Log.e(
                    LOG_TAG,
                    "Unexpected boot alarm restoration failure",
                    error
                )
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun restoreCachedMedicationAlarms(
        context: Context
    ) {
        val preferences = context.getSharedPreferences(
            SHARED_PREFERENCES_FILE,
            Context.MODE_PRIVATE
        )

        val alarmManager = context.getSystemService(
            Context.ALARM_SERVICE
        ) as AlarmManager

        val now = System.currentTimeMillis()

        var restoredPriorCount = 0
        var restoredDueCount = 0
        var skippedCount = 0

        /*
         * Work from a snapshot because expired or malformed entries may be
         * removed from SharedPreferences during this loop.
         */
        val cachedEntries = preferences.all.toMap()

        for ((key, value) in cachedEntries) {
            if (!key.startsWith(PAYLOAD_KEY_PREFIX)) {
                continue
            }

            val cachedPayload = value as? String

            if (cachedPayload.isNullOrBlank()) {
                preferences.edit()
                    .remove(key)
                    .apply()

                skippedCount++
                continue
            }

            try {
                val payloadJson = JSONObject(
                    cachedPayload
                )

                val scheduledForMillis =
                    payloadJson.optLong(
                        "scheduledForMillis",
                        -1L
                    )

                val dueAlarmId =
                    payloadJson.optInt(
                        "ttsAlarmId",
                        -1
                    )

                val priorAlarmId =
                    payloadJson.optInt(
                        "priorTtsAlarmId",
                        -1
                    )

                /*
                 * Old or malformed payloads cannot be restored safely.
                 */
                if (scheduledForMillis <= 0L ||
                    dueAlarmId <= 0
                ) {
                    Log.w(
                        LOG_TAG,
                        "Removing malformed cached dose payload: $key"
                    )

                    preferences.edit()
                        .remove(key)
                        .apply()

                    skippedCount++
                    continue
                }

                /*
                 * A dose already in the past should not be scheduled again
                 * after reboot. Removing it also prevents it from being
                 * restored on every future restart.
                 */
                if (scheduledForMillis <= now) {
                    Log.d(
                        LOG_TAG,
                        "Removing expired cached dose payload: $key"
                    )

                    preferences.edit()
                        .remove(key)
                        .apply()

                    skippedCount++
                    continue
                }

                val medicationName =
                    payloadJson.optString(
                        "medicationName",
                        "your medication"
                    )
                        .trim()
                        .ifBlank {
                            "your medication"
                        }

                val dosageDisplay =
                    payloadJson.optString(
                        "dosageDisplay",
                        ""
                    ).trim()

                // ══════════════════════════════════════════════
                // RESTORE TEN-MINUTE PRIOR REMINDER
                // ══════════════════════════════════════════════

                val priorReminderMillis =
                    scheduledForMillis -
                            PRIOR_REMINDER_OFFSET_MS

                if (priorAlarmId > 0 &&
                    priorReminderMillis > now
                ) {
                    /*
                     * Use a prior-reminder payload copy so its semantic type
                     * remains correct if this payload is inspected later.
                     */
                    val priorPayloadJson =
                        JSONObject(cachedPayload).apply {
                            put(
                                "alertType",
                                MODE_PRIOR_REMINDER
                            )
                        }

                    val priorMessage =
                        if (dosageDisplay.isBlank()) {
                            "Medication reminder. " +
                                    "$medicationName is due in " +
                                    "10 minutes."
                        } else {
                            "Medication reminder. " +
                                    "$medicationName, dosage " +
                                    "$dosageDisplay, is due in " +
                                    "10 minutes."
                        }

                    val priorIntent = Intent(
                        context,
                        TtsAlarmReceiver::class.java
                    ).apply {
                        putExtra(
                            "alarmId",
                            priorAlarmId
                        )

                        putExtra(
                            "message",
                            priorMessage
                        )

                        putExtra(
                            "payload",
                            priorPayloadJson.toString()
                        )

                        putExtra(
                            "alertMode",
                            MODE_PRIOR_REMINDER
                        )

                        putExtra(
                            "soundResource",
                            "prior_reminder"
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
                            VIBRATION_FIVE_PULSES
                        )

                        putExtra(
                            "ttsRepeatCount",
                            DEFAULT_TTS_REPEAT_COUNT
                        )
                    }

                    if (
                        scheduleAlarm(
                            context = context,
                            alarmManager = alarmManager,
                            alarmId = priorAlarmId,
                            triggerAtMillis =
                                priorReminderMillis,
                            alarmIntent = priorIntent
                        )
                    ) {
                        restoredPriorCount++

                        Log.d(
                            LOG_TAG,
                            "Restored prior reminder: " +
                                    "id=$priorAlarmId, " +
                                    "time=$priorReminderMillis, " +
                                    "medication=$medicationName"
                        )
                    }
                } else {
                    Log.d(
                        LOG_TAG,
                        "Prior reminder not restored because " +
                                "its time has passed or its ID is missing: " +
                                "id=$priorAlarmId, " +
                                "time=$priorReminderMillis"
                    )
                }

                // ══════════════════════════════════════════════
                // RESTORE EXACT DUE-TIME ALERT
                // ══════════════════════════════════════════════

                val duePayloadJson =
                    JSONObject(cachedPayload).apply {
                        put(
                            "alertType",
                            MODE_MEDICATION_DUE
                        )
                    }

                val dueMessage =
                    if (dosageDisplay.isBlank()) {
                        "It is time to take " +
                                "$medicationName. " +
                                "Please confirm your medicine now."
                    } else {
                        "It is time to take " +
                                "$medicationName. " +
                                "Dosage: $dosageDisplay. " +
                                "Please confirm your medicine now."
                    }

                val dueIntent = Intent(
                    context,
                    TtsAlarmReceiver::class.java
                ).apply {
                    putExtra(
                        "alarmId",
                        dueAlarmId
                    )

                    putExtra(
                        "message",
                        dueMessage
                    )

                    /*
                     * This payload contains the medication information and
                     * pillImageUrl required to open the screen without
                     * querying the logged-in user.
                     */
                    putExtra(
                        "payload",
                        duePayloadJson.toString()
                    )

                    putExtra(
                        "alertMode",
                        MODE_MEDICATION_DUE
                    )

                    putExtra(
                        "soundResource",
                        "alarm"
                    )

                    putExtra(
                        "loopSound",
                        true
                    )

                    putExtra(
                        "launchScanner",
                        true
                    )

                    putExtra(
                        "vibrationMode",
                        VIBRATION_CONTINUOUS
                    )

                    putExtra(
                        "ttsRepeatCount",
                        DEFAULT_TTS_REPEAT_COUNT
                    )
                }

                if (
                    scheduleAlarm(
                        context = context,
                        alarmManager = alarmManager,
                        alarmId = dueAlarmId,
                        triggerAtMillis =
                            scheduledForMillis,
                        alarmIntent = dueIntent
                    )
                ) {
                    restoredDueCount++

                    Log.d(
                        LOG_TAG,
                        "Restored due medication alert: " +
                                "id=$dueAlarmId, " +
                                "time=$scheduledForMillis, " +
                                "medication=$medicationName"
                    )
                }
            } catch (error: Exception) {
                Log.e(
                    LOG_TAG,
                    "Could not restore cached payload: $key",
                    error
                )

                /*
                 * Remove malformed JSON so the same invalid entry does not
                 * fail again after every device restart.
                 */
                preferences.edit()
                    .remove(key)
                    .apply()

                skippedCount++
            }
        }

        Log.d(
            LOG_TAG,
            "Boot alarm restoration finished: " +
                    "prior=$restoredPriorCount, " +
                    "due=$restoredDueCount, " +
                    "skipped=$skippedCount"
        )
    }

    private fun scheduleAlarm(
        context: Context,
        alarmManager: AlarmManager,
        alarmId: Int,
        triggerAtMillis: Long,
        alarmIntent: Intent
    ): Boolean {
        val pendingIntent =
            PendingIntent.getBroadcast(
                context,
                alarmId,
                alarmIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
            )

        return try {
            when {
                /*
                 * Android 12+ may deny exact-alarm access. Restore an inexact
                 * alarm rather than losing the medication reminder.
                 */
                Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.S &&
                        !alarmManager
                            .canScheduleExactAlarms() -> {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )

                    Log.w(
                        LOG_TAG,
                        "Exact-alarm access unavailable; " +
                                "restored alarm $alarmId using fallback"
                    )
                }

                Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.M -> {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }

                else -> {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }
            }

            true
        } catch (securityError: SecurityException) {
            Log.e(
                LOG_TAG,
                "Exact alarm rejected for $alarmId; " +
                        "attempting fallback",
                securityError
            )

            try {
                if (Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.M
                ) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                } else {
                    alarmManager.set(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }

                true
            } catch (fallbackError: Exception) {
                Log.e(
                    LOG_TAG,
                    "Fallback scheduling failed for alarm $alarmId",
                    fallbackError
                )

                false
            }
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "Could not restore alarm $alarmId",
                error
            )

            false
        }
    }
}