package com.example.mar

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "medication_tts_background"
        private const val LOG_TAG = "MAR_ALERTS"

        const val MODE_MEDICATION_DUE = "medication_due"
        const val MODE_PRIOR_REMINDER = "prior_reminder"
        const val MODE_CARETAKER_SOS = "caretaker_sos"

        const val VIBRATION_CONTINUOUS = "continuous"
        const val VIBRATION_FIVE_PULSES = "five_pulses"
        const val VIBRATION_NONE = "none"
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "scheduleStart" -> {
                        handleScheduleStart(call)
                        result.success(null)
                    }

                    "cancelAlarm" -> {
                        val alarmId =
                            call.argument<Number>("alarmId")
                                ?.toInt()
                                ?: 0

                        cancelTtsAlarm(alarmId)
                        result.success(null)
                    }

                    "start" -> {
                        handleImmediateStart(call)
                        result.success(null)
                    }

                    "stop" -> {
                        stopTtsService()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                Log.e(
                    LOG_TAG,
                    "Method channel error for ${call.method}",
                    error
                )

                result.error(
                    "NATIVE_ALERT_ERROR",
                    error.message ?: "Native alert operation failed",
                    null
                )
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // SCHEDULED ALERT
    // ══════════════════════════════════════════════════════════════

    private fun handleScheduleStart(call: MethodCall) {
        val alarmId =
            call.argument<Number>("alarmId")
                ?.toInt()
                ?: 0

        val startAtMillis =
            call.argument<Number>("startAtMillis")
                ?.toLong()
                ?: 0L

        val message =
            call.argument<String>("message")
                ?: ""

        val payload =
            call.argument<String>("payload")
                ?: ""

        val alertMode =
            call.argument<String>("alertMode")
                ?: MODE_MEDICATION_DUE

        val soundResource =
            call.argument<String>("soundResource")
                ?: defaultSoundResource(alertMode)

        val loopSound =
            call.argument<Boolean>("loopSound")
                ?: defaultLoopSound(alertMode)

        val launchScanner =
            call.argument<Boolean>("launchScanner")
                ?: defaultLaunchScanner(
                    alertMode = alertMode,
                    payload = payload
                )

        val vibrationMode =
            call.argument<String>("vibrationMode")
                ?: defaultVibrationMode(alertMode)

        val ttsRepeatCount =
            (
                    call.argument<Number>("ttsRepeatCount")
                        ?.toInt()
                        ?: 3
                    ).coerceIn(0, 10)

        require(alarmId != 0) {
            "A valid alarmId is required"
        }

        require(startAtMillis > 0L) {
            "A valid startAtMillis is required"
        }

        scheduleTtsAlarm(
            alarmId = alarmId,
            startAtMillis = startAtMillis,
            message = message,
            payload = payload,
            alertMode = alertMode,
            soundResource = soundResource,
            loopSound = loopSound,
            launchScanner = launchScanner,
            vibrationMode = vibrationMode,
            ttsRepeatCount = ttsRepeatCount
        )
    }

    private fun scheduleTtsAlarm(
        alarmId: Int,
        startAtMillis: Long,
        message: String,
        payload: String,
        alertMode: String,
        soundResource: String,
        loopSound: Boolean,
        launchScanner: Boolean,
        vibrationMode: String,
        ttsRepeatCount: Int
    ) {
        val alarmManager =
            getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent =
            Intent(this, TtsAlarmReceiver::class.java).apply {
                putExtra("alarmId", alarmId)
                putExtra("message", message)
                putExtra("payload", payload)

                // New optional configuration.
                putExtra("alertMode", alertMode)
                putExtra("soundResource", soundResource)
                putExtra("loopSound", loopSound)
                putExtra("launchScanner", launchScanner)
                putExtra("vibrationMode", vibrationMode)
                putExtra("ttsRepeatCount", ttsRepeatCount)
            }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId,
            intent,
            pendingIntentFlags()
        )

        Log.d(
            LOG_TAG,
            "Scheduling alert: " +
                    "id=$alarmId, " +
                    "mode=$alertMode, " +
                    "time=$startAtMillis, " +
                    "sound=$soundResource, " +
                    "loop=$loopSound, " +
                    "scanner=$launchScanner, " +
                    "vibration=$vibrationMode, " +
                    "ttsRepeats=$ttsRepeatCount"
        )

        try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        !alarmManager.canScheduleExactAlarms() -> {
                    // Safe fallback when the user has not granted exact alarm
                    // permission. This may be slightly delayed by Android.
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        startAtMillis,
                        pendingIntent
                    )

                    Log.w(
                        LOG_TAG,
                        "Exact alarm permission unavailable; " +
                                "using inexact fallback"
                    )
                }

                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        startAtMillis,
                        pendingIntent
                    )
                }

                else -> {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        startAtMillis,
                        pendingIntent
                    )
                }
            }
        } catch (error: SecurityException) {
            Log.e(
                LOG_TAG,
                "Exact alarm rejected; using fallback",
                error
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    startAtMillis,
                    pendingIntent
                )
            } else {
                alarmManager.set(
                    AlarmManager.RTC_WAKEUP,
                    startAtMillis,
                    pendingIntent
                )
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // IMMEDIATE ALERT
    // ══════════════════════════════════════════════════════════════

    private fun handleImmediateStart(call: MethodCall) {
        val message =
            call.argument<String>("message")
                ?: ""

        val payload =
            call.argument<String>("payload")
                ?: ""

        val alertMode =
            call.argument<String>("alertMode")
                ?: MODE_MEDICATION_DUE

        val soundResource =
            call.argument<String>("soundResource")
                ?: defaultSoundResource(alertMode)

        val loopSound =
            call.argument<Boolean>("loopSound")
                ?: defaultLoopSound(alertMode)

        val launchScanner =
            call.argument<Boolean>("launchScanner")
                ?: defaultLaunchScanner(
                    alertMode = alertMode,
                    payload = payload
                )

        val vibrationMode =
            call.argument<String>("vibrationMode")
                ?: defaultVibrationMode(alertMode)

        val ttsRepeatCount =
            (
                    call.argument<Number>("ttsRepeatCount")
                        ?.toInt()
                        ?: 3
                    ).coerceIn(0, 10)

        startTtsService(
            message = message,
            payload = payload,
            alertMode = alertMode,
            soundResource = soundResource,
            loopSound = loopSound,
            launchScanner = launchScanner,
            vibrationMode = vibrationMode,
            ttsRepeatCount = ttsRepeatCount
        )
    }

    private fun startTtsService(
        message: String,
        payload: String,
        alertMode: String,
        soundResource: String,
        loopSound: Boolean,
        launchScanner: Boolean,
        vibrationMode: String,
        ttsRepeatCount: Int
    ) {
        val intent =
            Intent(this, TtsSpeakService::class.java).apply {
                action = TtsSpeakService.ACTION_START

                putExtra("message", message)
                putExtra("payload", payload)

                putExtra("alertMode", alertMode)
                putExtra("soundResource", soundResource)
                putExtra("loopSound", loopSound)
                putExtra("launchScanner", launchScanner)
                putExtra("vibrationMode", vibrationMode)
                putExtra("ttsRepeatCount", ttsRepeatCount)
            }

        Log.d(
            LOG_TAG,
            "Starting immediate alert: " +
                    "mode=$alertMode, " +
                    "sound=$soundResource, " +
                    "loop=$loopSound, " +
                    "scanner=$launchScanner, " +
                    "vibration=$vibrationMode, " +
                    "ttsRepeats=$ttsRepeatCount"
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    // ══════════════════════════════════════════════════════════════
    // CANCELLATION
    // ══════════════════════════════════════════════════════════════

    private fun cancelTtsAlarm(alarmId: Int) {
        if (alarmId == 0) return

        val alarmManager =
            getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent =
            Intent(this, TtsAlarmReceiver::class.java)

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId,
            intent,
            pendingIntentFlags()
        )

        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()

        Log.d(
            LOG_TAG,
            "Cancelled native alert alarm: $alarmId"
        )
    }

    private fun stopTtsService() {
        // Stopping the service invokes onDestroy(), which already calls
        // stopEverything() in your working TtsSpeakService.
        stopService(
            Intent(
                this,
                TtsSpeakService::class.java
            )
        )

        Log.d(
            LOG_TAG,
            "Stopped TTS alert service"
        )
    }

    // ══════════════════════════════════════════════════════════════
    // BACKWARD-COMPATIBLE DEFAULTS
    // ══════════════════════════════════════════════════════════════

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

    private fun pendingIntentFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
    }
}