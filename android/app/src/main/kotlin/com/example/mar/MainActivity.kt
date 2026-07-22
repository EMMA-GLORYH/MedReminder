// android/app/src/main/kotlin/com/example/mar/MainActivity.kt

package com.example.mar

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.absoluteValue

class MainActivity : FlutterActivity() {

    companion object {
        private const val ALERT_CHANNEL_NAME =
            "medication_tts_background"

        private const val SCANNER_ROUTE_CHANNEL =
            "medication_scanner_route"

        private const val SOS_REALTIME_CHANNEL =
            "sos_realtime_background"

        private const val SOS_SMS_CHANNEL =
            "sos_sms_fallback"

        private const val CARETAKER_MEDICATION_CHANNEL =
            "caretaker_medication_alerts"

        private const val ACTION_OPEN_SCANNER =
            "com.example.mar.OPEN_SCANNER"

        private const val LOG_TAG =
            "MAR_ALERTS"

        private const val SMS_PERMISSION_REQUEST_CODE =
            7001

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

    private var scannerRouteChannel: MethodChannel? =
        null

    /*
     * When Android launches MainActivity from a terminated state,
     * Flutter may not yet have registered its route handler. Keep the
     * scanner payload until Flutter explicitly requests it.
     */
    private var pendingScannerPayload: String? =
        null

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        configureAlertChannel(flutterEngine)
        configureScannerRouteChannel(flutterEngine)
        configureSosRealtimeChannel(flutterEngine)
        configureSosSmsChannel(flutterEngine)
        configureCaretakerMedicationChannel(flutterEngine)

        extractScannerPayload(intent)?.let { payload ->
            pendingScannerPayload = payload

            Log.d(
                LOG_TAG,
                "Stored initial scanner payload until Flutter is ready"
            )
        }
    }

    override fun onNewIntent(
        intent: Intent
    ) {
        super.onNewIntent(intent)

        setIntent(intent)

        val payload =
            extractScannerPayload(intent)
                ?: return

        pendingScannerPayload = payload

        Log.d(
            LOG_TAG,
            "Received OPEN_SCANNER through onNewIntent"
        )

        dispatchPendingScannerPayload()
    }

    // ══════════════════════════════════════════════════════════════
    // MEDICATION ALERT CHANNEL
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
                            call.argument<Number>(
                                "alarmId"
                            )
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
                    "Alert method-channel error for ${call.method}",
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
    // SCANNER ROUTE CHANNEL
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
                        val payload =
                            pendingScannerPayload

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

    private fun extractScannerPayload(
        sourceIntent: Intent?
    ): String? {
        if (sourceIntent?.action != ACTION_OPEN_SCANNER) {
            return null
        }

        return sourceIntent
            .getStringExtra("payload")
            ?.trim()
            ?.takeIf {
                it.isNotBlank()
            }
    }

    private fun dispatchPendingScannerPayload() {
        val payload =
            pendingScannerPayload
                ?.takeIf {
                    it.isNotBlank()
                }
                ?: return

        val channel =
            scannerRouteChannel
                ?: return

        channel.invokeMethod(
            "openScanner",
            payload,
            object : MethodChannel.Result {
                override fun success(
                    result: Any?
                ) {
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
    // SOS REALTIME CHANNEL
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
                            call.argument<String>(
                                "caregiverId"
                            )
                                ?.trim()
                                .orEmpty()

                        val supabaseUrl =
                            call.argument<String>(
                                "supabaseUrl"
                            )
                                ?.trim()
                                .orEmpty()

                        val supabaseAnonKey =
                            call.argument<String>(
                                "supabaseAnonKey"
                            )
                                ?.trim()
                                .orEmpty()

                        val accessToken =
                            call.argument<String>(
                                "accessToken"
                            )
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

                        SosRealtimeService.start(
                            context = this,
                            caregiverId = caregiverId,
                            supabaseUrl = supabaseUrl,
                            supabaseAnonKey = supabaseAnonKey,
                            accessToken = accessToken
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

    // ══════════════════════════════════════════════════════════════
    // SOS SMS FALLBACK CHANNEL
    // ══════════════════════════════════════════════════════════════

    private fun configureSosSmsChannel(
        flutterEngine: FlutterEngine
    ) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SOS_SMS_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestSmsPermission" -> {
                        if (hasSmsPermission()) {
                            result.success(true)
                        } else {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(
                                    Manifest.permission.SEND_SMS
                                ),
                                SMS_PERMISSION_REQUEST_CODE
                            )

                            /*
                             * Android permission requests are asynchronous.
                             * The caller should retry after the user grants
                             * permission.
                             */
                            result.success(false)
                        }
                    }

                    "sendSosSms" -> {
                        if (!hasSmsPermission()) {
                            result.error(
                                "SMS_PERMISSION_DENIED",
                                "SMS permission is required to send an SOS fallback message",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val recipients =
                            call.argument<List<String>>(
                                "recipients"
                            )
                                .orEmpty()
                                .map {
                                    it.trim()
                                }
                                .filter {
                                    it.isNotEmpty()
                                }
                                .distinct()

                        val message =
                            call.argument<String>(
                                "message"
                            )
                                ?.trim()
                                .orEmpty()

                        if (recipients.isEmpty()) {
                            result.error(
                                "INVALID_RECIPIENTS",
                                "At least one SMS recipient is required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        if (message.isBlank()) {
                            result.error(
                                "INVALID_MESSAGE",
                                "SMS message cannot be empty",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val sentCount =
                            sendSosSms(
                                recipients = recipients,
                                message = message
                            )

                        result.success(sentCount)
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (error: SecurityException) {
                Log.e(
                    LOG_TAG,
                    "SMS permission was not granted",
                    error
                )

                result.error(
                    "SMS_PERMISSION_DENIED",
                    "SMS permission is required to send an SOS fallback message",
                    null
                )
            } catch (error: Exception) {
                Log.e(
                    LOG_TAG,
                    "SOS SMS channel error",
                    error
                )

                result.error(
                    "SMS_SEND_ERROR",
                    error.message
                        ?: "Could not send SOS SMS",
                    null
                )
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // CARETAKER MEDICATION TTS CHANNEL
    // ══════════════════════════════════════════════════════════════

    private fun configureCaretakerMedicationChannel(
        flutterEngine: FlutterEngine
    ) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CARETAKER_MEDICATION_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "scheduleCaretakerMedicationAlert" -> {
                        val alertId =
                            call.argument<String>("alertId")
                                ?.trim()
                                .orEmpty()

                        val patientId =
                            call.argument<String>("patientId")
                                ?.trim()
                                .orEmpty()

                        val patientName =
                            call.argument<String>("patientName")
                                ?.trim()
                                .orEmpty()

                        val scheduleId =
                            call.argument<String>("scheduleId")
                                ?.trim()
                                .orEmpty()

                        val medicationId =
                            call.argument<String>("medicationId")
                                ?.trim()
                                .orEmpty()

                        val scheduledForMillis =
                            call.argument<Number>(
                                "scheduledForMillis"
                            )?.toLong() ?: 0L

                        val originalScheduledForMillis =
                            call.argument<Number>(
                                "originalScheduledForMillis"
                            )?.toLong() ?: scheduledForMillis

                        val message =
                            call.argument<String>("message")
                                ?.trim()
                                .orEmpty()

                        val alertType =
                            call.argument<String>("alertType")
                                ?.trim()
                                .orEmpty()

                        val repeatCount =
                            (
                                    call.argument<Number>(
                                        "ttsRepeatCount"
                                    )?.toInt() ?: 1
                                    ).coerceIn(1, 3)

                        if (alertId.isBlank() ||
                            patientId.isBlank() ||
                            scheduleId.isBlank() ||
                            medicationId.isBlank() ||
                            scheduledForMillis <= 0L ||
                            message.isBlank()
                        ) {
                            result.error(
                                "INVALID_ARGUMENT",
                                "Required caretaker medication alert data is missing",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        scheduleCaretakerMedicationAlarm(
                            alertId = alertId,
                            patientId = patientId,
                            patientName = patientName,
                            scheduleId = scheduleId,
                            medicationId = medicationId,
                            scheduledForMillis = scheduledForMillis,
                            originalScheduledForMillis =
                                originalScheduledForMillis,
                            message = message,
                            alertType = alertType,
                            ttsRepeatCount = repeatCount
                        )

                        result.success(null)
                    }

                    "cancelCaretakerMedicationAlert" -> {
                        val alertId =
                            call.argument<String>("alertId")
                                ?.trim()
                                .orEmpty()

                        if (alertId.isBlank()) {
                            result.error(
                                "INVALID_ARGUMENT",
                                "alertId is required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        cancelCaretakerMedicationAlarm(alertId)
                        result.success(null)
                    }

                    "cancelCaretakerPatientAlerts" -> {
                        val patientId =
                            call.argument<String>("patientId")
                                ?.trim()
                                .orEmpty()

                        /*
                         * Patient-wide cancellation will be completed after the
                         * receiver/service storage is added.
                         */
                        Log.d(
                            LOG_TAG,
                            "Caretaker patient alert cancellation requested: "
                                    + patientId
                        )

                        result.success(null)
                    }

                    "stopCaretakerMedicationAlert" -> {
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
                    "Caretaker medication channel error",
                    error
                )

                result.error(
                    "CARETAKER_MEDICATION_ERROR",
                    error.message
                        ?: "Caretaker medication alert failed",
                    null
                )
            }
        }
    }

    private fun scheduleCaretakerMedicationAlarm(
        alertId: String,
        patientId: String,
        patientName: String,
        scheduleId: String,
        medicationId: String,
        scheduledForMillis: Long,
        originalScheduledForMillis: Long,
        message: String,
        alertType: String,
        ttsRepeatCount: Int
    ) {
        val alarmManager =
            getSystemService(
                Context.ALARM_SERVICE
            ) as AlarmManager

        val alarmIntent = Intent(
            this,
            CaretakerMedicationAlarmReceiver::class.java
        ).apply {
            putExtra("alertId", alertId)
            putExtra("patientId", patientId)
            putExtra("patientName", patientName)
            putExtra("scheduleId", scheduleId)
            putExtra("medicationId", medicationId)
            putExtra(
                "scheduledForMillis",
                scheduledForMillis
            )
            putExtra(
                "originalScheduledForMillis",
                originalScheduledForMillis
            )
            putExtra("message", message)
            putExtra("alertType", alertType)
            putExtra("ttsRepeatCount", ttsRepeatCount)
        }

        val requestCode =
            alertId.hashCode().absoluteValue

        val pendingIntent =
            PendingIntent.getBroadcast(
                this,
                requestCode,
                alarmIntent,
                pendingIntentFlags()
            )

        try {
            when {
                Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.S &&
                        !alarmManager.canScheduleExactAlarms() -> {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        scheduledForMillis,
                        pendingIntent
                    )
                }

                Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.M -> {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        scheduledForMillis,
                        pendingIntent
                    )
                }

                else -> {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        scheduledForMillis,
                        pendingIntent
                    )
                }
            }

            Log.d(
                LOG_TAG,
                "Caretaker medication TTS scheduled: " +
                        "alertId=$alertId, " +
                        "time=$scheduledForMillis, " +
                        "type=$alertType"
            )
        } catch (error: SecurityException) {
            Log.e(
                LOG_TAG,
                "Could not schedule caretaker medication alert",
                error
            )

            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                scheduledForMillis,
                pendingIntent
            )
        }
    }

    private fun cancelCaretakerMedicationAlarm(
        alertId: String
    ) {
        val alarmManager =
            getSystemService(
                Context.ALARM_SERVICE
            ) as AlarmManager

        val intent = Intent(
            this,
            CaretakerMedicationAlarmReceiver::class.java
        )

        val requestCode =
            alertId.hashCode().absoluteValue

        val pendingIntent =
            PendingIntent.getBroadcast(
                this,
                requestCode,
                intent,
                pendingIntentFlags()
            )

        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()

        Log.d(
            LOG_TAG,
            "Cancelled caretaker medication alert: $alertId"
        )
    }

    private fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun sendSosSms(
        recipients: List<String>,
        message: String
    ): Int {
        @Suppress("DEPRECATION")
        val smsManager =
            SmsManager.getDefault()

        var sentCount = 0

        for (phoneNumber in recipients) {
            try {
                val parts =
                    smsManager.divideMessage(message)

                if (parts.size <= 1) {
                    smsManager.sendTextMessage(
                        phoneNumber,
                        null,
                        message,
                        null,
                        null
                    )
                } else {
                    smsManager.sendMultipartTextMessage(
                        phoneNumber,
                        null,
                        ArrayList(parts),
                        null,
                        null
                    )
                }

                sentCount++

                Log.d(
                    LOG_TAG,
                    "SOS SMS queued for $phoneNumber"
                )
            } catch (error: Exception) {
                Log.e(
                    LOG_TAG,
                    "Could not send SOS SMS to $phoneNumber",
                    error
                )
            }
        }

        if (sentCount == 0) {
            throw IllegalStateException(
                "No SOS SMS could be queued"
            )
        }

        return sentCount
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
                        "Exact alarm permission unavailable; using fallback"
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
                action =
                    TtsSpeakService.ACTION_START

                putExtra("message", message)
                putExtra("payload", payload)
                putExtra("alertMode", alertMode)
                putExtra(
                    "soundResource",
                    soundResource
                )
                putExtra("loopSound", loopSound)
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
    // DEFAULTS
    // ══════════════════════════════════════════════════════════════

    private fun defaultSoundResource(
        alertMode: String
    ): String {
        return when (alertMode.trim().lowercase()) {
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
        return when (alertMode.trim().lowercase()) {
            MODE_PRIOR_REMINDER -> false
            MODE_CARETAKER_SOS -> true
            else -> true
        }
    }

    private fun defaultLaunchScanner(
        alertMode: String,
        payload: String
    ): Boolean {
        return alertMode.trim().lowercase() ==
                MODE_MEDICATION_DUE &&
                payload.isNotBlank()
    }

    private fun defaultVibrationMode(
        alertMode: String
    ): String {
        return when (alertMode.trim().lowercase()) {
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