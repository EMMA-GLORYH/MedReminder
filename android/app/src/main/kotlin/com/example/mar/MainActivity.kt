// android/app/src/main/kotlin/com/example/mar/MainActivity.kt

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
        private const val ALERT_CHANNEL_NAME =
            "medication_tts_background"

        private const val SCANNER_ROUTE_CHANNEL =
            "medication_scanner_route"

        // ✅ NEW: SOS Realtime channel name.
        // Must match SosRealtimeNativeService._channel in Dart.
        private const val SOS_REALTIME_CHANNEL =
            "sos_realtime_background"

        private const val ACTION_OPEN_SCANNER =
            "com.example.mar.OPEN_SCANNER"

        private const val LOG_TAG = "MAR_ALERTS"

        const val MODE_MEDICATION_DUE =
            "medication_due"

        const val MODE_PRIOR_REMINDER =
            "prior_reminder"

        const val MODE_CARETAKER_SOS =
            "caretaker_sos"

        const val VIBRATION_CONTINUOUS =
            "continuous"

        const val VIBRATION_FIVE_PULSES =
            "five_pulses"

        const val VIBRATION_NONE =
            "none"
    }

    private var scannerRouteChannel: MethodChannel? = null

    /*
     * When Android starts MainActivity from a terminated state, Dart may
     * not have registered its MethodChannel handler yet. Keep the payload
     * here until Flutter explicitly requests it.
     */
    private var pendingScannerPayload: String? = null

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        configureAlertChannel(flutterEngine)
        configureScannerRouteChannel(flutterEngine)

        // ✅ NEW: SOS Realtime background WebSocket control.
        configureSosRealtimeChannel(flutterEngine)

        /*
         * Do not immediately call Flutter for a cold-start intent.
         * Flutter may not yet have initialized LocalNotificationService,
         * the global navigator, or its MethodChannel handler.
         */
        extractScannerPayload(intent)?.let { payload ->
            pendingScannerPayload = payload

            Log.d(
                LOG_TAG,
                "Stored initial scanner payload until Flutter is ready"
            )
        }
    }

    /*
     * Called when MainActivity already exists because the activity uses
     * singleTop and the alarm sends another OPEN_SCANNER intent.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)

        val payload = extractScannerPayload(intent)
            ?: return

        pendingScannerPayload = payload

        Log.d(
            LOG_TAG,
            "Received OPEN_SCANNER through onNewIntent"
        )

        dispatchPendingScannerPayload()
    }

    // ══════════════════════════════════════════════════════════════
    // FLUTTER ALERT METHOD CHANNEL
    // ══════════════════════════════════════════════════════════════

    private fun configureAlertChannel(
        flutterEngine: FlutterEngine
    ) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ALERT_CHANNEL_NAME
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

                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (error: Exception) {
                Log.e(
                    LOG_TAG,
                    "Method channel error for ${call.method}",
                    error
                )

                result.error(
                    "NATIVE_ALERT_ERROR",
                    error.message
                        ?: "Native alert operation failed",
                    null
                )
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // SCANNER ROUTE METHOD CHANNEL
    // ══════════════════════════════════════════════════════════════

    private fun configureScannerRouteChannel(
        flutterEngine: FlutterEngine
    ) {
        scannerRouteChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCANNER_ROUTE_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialScannerPayload" -> {
                        val payload = pendingScannerPayload

                        if (!payload.isNullOrBlank()) {
                            pendingScannerPayload = null

                            Log.d(
                                LOG_TAG,
                                "Initial scanner payload delivered to Flutter"
                            )
                        }

                        result.success(payload)
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // SOS REALTIME BACKGROUND CHANNEL ✅ NEW
    //
    // Flutter calls startSosRealtime to launch SosRealtimeService,
    // which maintains a native OkHttp WebSocket to Supabase Realtime.
    // When a new SOS INSERT arrives, SosRealtimeService fires
    // TtsSpeakService directly — no Flutter needed.
    // ══════════════════════════════════════════════════════════════

    private fun configureSosRealtimeChannel(
        flutterEngine: FlutterEngine
    ) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SOS_REALTIME_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startSosRealtime" -> {
                        val caregiverId =
                            call.argument<String>("caregiverId")
                                ?.trim()
                                .orEmpty()

                        val supabaseUrl =
                            call.argument<String>("supabaseUrl")
                                ?.trim()
                                .orEmpty()

                        val supabaseAnonKey =
                            call.argument<String>("supabaseAnonKey")
                                ?.trim()
                                .orEmpty()

                        if (caregiverId.isBlank()) {
                            result.error(
                                "INVALID_ARGUMENT",
                                "caregiverId is required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        if (supabaseUrl.isBlank()) {
                            result.error(
                                "INVALID_ARGUMENT",
                                "supabaseUrl is required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        if (supabaseAnonKey.isBlank()) {
                            result.error(
                                "INVALID_ARGUMENT",
                                "supabaseAnonKey is required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        // ✅ Read the user's session JWT that Dart now sends.
                        // Row Level Security needs this on the socket so the
                        // caretaker only receives their own SOS alerts.
                        val accessToken =
                            call.argument<String>("accessToken")
                                ?.trim()
                                .orEmpty()

                        SosRealtimeService.start(
                            context = this,
                            caregiverId = caregiverId,
                            supabaseUrl = supabaseUrl,
                            supabaseAnonKey = supabaseAnonKey,
                            accessToken = accessToken   // ✅ 5th parameter
                        )

                        Log.d(
                            LOG_TAG,
                            "SOS Realtime service started for " +
                                    "caregiver $caregiverId"
                        )

                        result.success(null)
                    }

                    "stopSosRealtime" -> {
                        SosRealtimeService.stop(this)

                        Log.d(
                            LOG_TAG,
                            "SOS Realtime service stopped"
                        )

                        result.success(null)
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (error: Exception) {
                Log.e(
                    LOG_TAG,
                    "SOS Realtime channel error for ${call.method}",
                    error
                )

                result.error(
                    "SOS_REALTIME_ERROR",
                    error.message
                        ?: "SOS Realtime operation failed",
                    null
                )
            }
        }
    }

    private fun extractScannerPayload(
        sourceIntent: Intent?
    ): String? {
        if (sourceIntent?.action != ACTION_OPEN_SCANNER) {
            return null
        }

        return sourceIntent
            .getStringExtra("payload")
            ?.trim()
            ?.takeIf { it.isNotBlank() }
    }

    private fun dispatchPendingScannerPayload() {
        val payload = pendingScannerPayload
            ?.takeIf { it.isNotBlank() }
            ?: return

        val channel = scannerRouteChannel
            ?: return

        channel.invokeMethod(
            "openScanner",
            payload,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (pendingScannerPayload == payload) {
                        pendingScannerPayload = null
                    }

                    Log.d(
                        LOG_TAG,
                        "Scanner payload forwarded to Flutter"
                    )
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?
                ) {
                    Log.e(
                        LOG_TAG,
                        "Flutter rejected scanner payload: " +
                                "$errorCode, $errorMessage"
                    )
                }

                override fun notImplemented() {
                    Log.w(
                        LOG_TAG,
                        "Flutter scanner route handler is not ready"
                    )
                }
            }
        )
    }

    // ══════════════════════════════════════════════════════════════
    // SCHEDULED ALERT
    // ══════════════════════════════════════════════════════════════

    private fun handleScheduleStart(
        call: MethodCall
    ) {
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
            getSystemService(
                Context.ALARM_SERVICE
            ) as AlarmManager

        val alarmIntent =
            Intent(
                this,
                TtsAlarmReceiver::class.java
            ).apply {
                putExtra("alarmId", alarmId)
                putExtra("message", message)
                putExtra("payload", payload)
                putExtra("alertMode", alertMode)
                putExtra("soundResource", soundResource)
                putExtra("loopSound", loopSound)
                putExtra("launchScanner", launchScanner)
                putExtra("vibrationMode", vibrationMode)
                putExtra("ttsRepeatCount", ttsRepeatCount)
            }

        val pendingIntent =
            PendingIntent.getBroadcast(
                this,
                alarmId,
                alarmIntent,
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
                Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.S &&
                        !alarmManager
                            .canScheduleExactAlarms() -> {
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

                Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.M -> {
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

            if (Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.M
            ) {
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

    private fun handleImmediateStart(
        call: MethodCall
    ) {
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
        val serviceIntent =
            Intent(
                this,
                TtsSpeakService::class.java
            ).apply {
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

        if (Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.O
        ) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    // ══════════════════════════════════════════════════════════════
    // CANCELLATION
    // ══════════════════════════════════════════════════════════════

    private fun cancelTtsAlarm(
        alarmId: Int
    ) {
        if (alarmId == 0) return

        val alarmManager =
            getSystemService(
                Context.ALARM_SERVICE
            ) as AlarmManager

        val alarmIntent =
            Intent(
                this,
                TtsAlarmReceiver::class.java
            )

        val pendingIntent =
            PendingIntent.getBroadcast(
                this,
                alarmId,
                alarmIntent,
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
        val stopIntent =
            Intent(
                this,
                TtsSpeakService::class.java
            ).apply {
                action = TtsSpeakService.ACTION_STOP
            }

        try {
            startService(stopIntent)
        } catch (error: Exception) {
            Log.w(
                LOG_TAG,
                "Could not send ACTION_STOP; stopping service directly",
                error
            )

            stopService(
                Intent(
                    this,
                    TtsSpeakService::class.java
                )
            )
        }

        Log.d(
            LOG_TAG,
            "Requested TTS alert service stop"
        )
    }

    // ══════════════════════════════════════════════════════════════
    // BACKWARD-COMPATIBLE DEFAULTS
    // ══════════════════════════════════════════════════════════════

    private fun defaultSoundResource(
        alertMode: String
    ): String {
        return when (
            alertMode.trim().lowercase()
        ) {
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
        return when (
            alertMode.trim().lowercase()
        ) {
            MODE_PRIOR_REMINDER -> false
            MODE_CARETAKER_SOS -> true
            else -> true
        }
    }

    private fun defaultLaunchScanner(
        alertMode: String,
        payload: String
    ): Boolean {
        return alertMode
            .trim()
            .lowercase() ==
                MODE_MEDICATION_DUE &&
                payload.isNotBlank()
    }

    private fun defaultVibrationMode(
        alertMode: String
    ): String {
        return when (
            alertMode.trim().lowercase()
        ) {
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