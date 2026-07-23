// android/app/src/main/kotlin/com/example/mar/TtsSpeakService.kt

package com.example.mar

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Locale

class TtsSpeakService : Service(), TextToSpeech.OnInitListener {

    companion object {
        const val ACTION_START = "ACTION_START_TTS"
        const val ACTION_STOP = "ACTION_STOP_TTS"

        const val MODE_MEDICATION_DUE = "medication_due"
        const val MODE_PRIOR_REMINDER = "prior_reminder"
        const val MODE_CARETAKER_SOS = "caretaker_sos"
        const val MODE_CARETAKER_MEDICATION = "caretaker_medication"

        const val VIBRATION_CONTINUOUS = "continuous"
        const val VIBRATION_FIVE_PULSES = "five_pulses"
        const val VIBRATION_NONE = "none"

        private const val CHANNEL_ID = "tts_foreground_channel"
        private const val NOTIFICATION_ID = 9001
        private const val LOG_TAG = "MAR_ALERTS"

        private const val DEFAULT_TTS_REPEAT_COUNT = 3
        private const val GAP_BETWEEN_SPEAKS_MS = 600L
        private const val FLASH_TOGGLE_INTERVAL_MS = 400L
        private const val TTS_RETRY_INTERVAL_MS = 500L
        private const val MAX_TTS_RETRIES = 5

        private val CONTINUOUS_VIBRATION_PATTERN = longArrayOf(
            0L,
            900L, 300L,
            900L, 300L,
            900L, 300L,
            1300L, 400L,
            1300L,
        )

        private val FIVE_PULSE_VIBRATION_PATTERN = longArrayOf(
            0L,
            300L, 220L,
            300L, 220L,
            300L, 220L,
            300L, 220L,
            300L,
        )
    }

    private var tts: TextToSpeech? = null
    private var mediaPlayer: MediaPlayer? = null
    private var handler: Handler? = null
    private var vibrator: Vibrator? = null

    private var cameraManager: CameraManager? = null
    private var cameraId: String? = null
    private var isTorchOn = false
    private var flashRunnable: Runnable? = null

    private var message = ""
    private var payload = ""

    private var alertMode = MODE_MEDICATION_DUE
    private var soundResource = "alarm"
    private var vibrationMode = VIBRATION_CONTINUOUS

    private var loopSound = true
    private var launchScanner = true
    private var flashlightEnabled = false
    private var ttsRepeatCount = DEFAULT_TTS_REPEAT_COUNT

    private var isReady = false
    private var speakCount = 0
    private var ttsRetryCount = 0
    private var alertSessionId = 0L

    override fun onCreate() {
        super.onCreate()

        createNotificationChannel()
        handler = Handler(Looper.getMainLooper())
        vibrator = getVibrator()
        initCameraManager()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val action = intent?.action ?: ACTION_START

        if (action == ACTION_STOP) {
            stopEverything()
            stopSelf()
            return START_NOT_STICKY
        }

        alertSessionId = System.currentTimeMillis()
        ttsRetryCount = 0
        speakCount = 0

        message = intent?.getStringExtra("message")?.trim().orEmpty()
        payload = intent?.getStringExtra("payload").orEmpty()

        alertMode = intent
            ?.getStringExtra("alertMode")
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotBlank() }
            ?: MODE_MEDICATION_DUE

        soundResource = getValidResourceName(
            intent?.getStringExtra("soundResource")
                ?: defaultSoundResource(alertMode),
        )

        loopSound = if (intent?.hasExtra("loopSound") == true) {
            intent.getBooleanExtra("loopSound", defaultLoopSound(alertMode))
        } else {
            defaultLoopSound(alertMode)
        }

        launchScanner = if (intent?.hasExtra("launchScanner") == true) {
            intent.getBooleanExtra(
                "launchScanner",
                defaultLaunchScanner(alertMode, payload),
            )
        } else {
            defaultLaunchScanner(alertMode, payload)
        }

        vibrationMode = intent
            ?.getStringExtra("vibrationMode")
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: defaultVibrationMode(alertMode)

        flashlightEnabled = if (intent?.hasExtra("flashlight") == true) {
            intent.getBooleanExtra(
                "flashlight",
                defaultFlashlightEnabled(alertMode),
            )
        } else {
            defaultFlashlightEnabled(alertMode)
        }

        ttsRepeatCount = intent
            ?.getIntExtra("ttsRepeatCount", DEFAULT_TTS_REPEAT_COUNT)
            ?.coerceIn(0, 10)
            ?: DEFAULT_TTS_REPEAT_COUNT

        Log.d(
            LOG_TAG,
            "Starting alert: mode=$alertMode, sound=$soundResource, " +
                    "loop=$loopSound, launchScanner=$launchScanner, " +
                    "vibration=$vibrationMode, flashlight=$flashlightEnabled, " +
                    "ttsRepeats=$ttsRepeatCount",
        )

        /*
         * Critical:
         * Start as MEDIA_PLAYBACK only. Do not start a camera FGS from
         * a background alarm on Android 14+, otherwise Android can crash
         * the process with SecurityException.
         */
        try {
            startAlertForeground()
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Could not start medication foreground service", error)

            /*
             * Never crash the app because a foreground service failed.
             * The service is unable to safely run, so clean up.
             */
            stopEverything()
            stopSelf()
            return START_NOT_STICKY
        }

        stopAudioOnly()
        stopVibration()
        stopFlashlight()

        startVibration()

        /*
         * Flashlight is optional. TTS/vibration/sound must work even if
         * camera permission is missing or Android blocks torch access.
         */
        if (flashlightEnabled) {
            startFlashlightStrobe()
        }

        if (
            launchScanner &&
            payload.isNotBlank() &&
            alertMode != MODE_CARETAKER_MEDICATION
        ) {
            launchScannerScreen(payload)
        }

        if (alertMode == MODE_CARETAKER_MEDICATION) {
            if (ttsRepeatCount <= 0 || message.isBlank()) {
                stopEverything()
                stopSelf()
            } else {
                startTts()
            }
            return START_STICKY
        }

        if (ttsRepeatCount <= 0 || message.isBlank()) {
            startSelectedSound()
        } else {
            startTts()
        }

        return START_STICKY
    }

    private fun startAlertForeground() {
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Flashlight
    // ─────────────────────────────────────────────────────────────

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun initCameraManager() {
        try {
            cameraManager = getSystemService(Context.CAMERA_SERVICE) as? CameraManager

            val ids = cameraManager?.cameraIdList ?: emptyArray()

            for (id in ids) {
                val characteristics = cameraManager?.getCameraCharacteristics(id)
                val hasFlash = characteristics?.get(
                    CameraCharacteristics.FLASH_INFO_AVAILABLE,
                ) == true

                val facing = characteristics?.get(
                    CameraCharacteristics.LENS_FACING,
                )

                if (hasFlash && facing == CameraCharacteristics.LENS_FACING_BACK) {
                    cameraId = id
                    break
                }
            }

            Log.d(LOG_TAG, "Camera initialized: cameraId=$cameraId")
        } catch (error: Exception) {
            Log.w(LOG_TAG, "Camera flashlight unavailable", error)
        }
    }

    private fun startFlashlightStrobe() {
        /*
         * Android 14 can reject camera access from a background alert.
         * Skip it instead of crashing or interrupting the medication alert.
         */
        if (!hasCameraPermission()) {
            Log.w(LOG_TAG, "Flashlight skipped: CAMERA runtime permission is not granted")
            return
        }

        val targetCameraId = cameraId
        if (targetCameraId == null) {
            Log.w(LOG_TAG, "Flashlight skipped: no rear flash camera")
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            Log.w(LOG_TAG, "Flashlight skipped: API below Android M")
            return
        }

        flashRunnable?.let { handler?.removeCallbacks(it) }

        flashRunnable = object : Runnable {
            override fun run() {
                try {
                    isTorchOn = !isTorchOn
                    cameraManager?.setTorchMode(targetCameraId, isTorchOn)
                    handler?.postDelayed(this, FLASH_TOGGLE_INTERVAL_MS)
                } catch (error: SecurityException) {
                    /*
                     * Android denied background camera access.
                     * Stop flashlight only; leave TTS/audio/vibration running.
                     */
                    Log.w(LOG_TAG, "Flashlight denied by Android; continuing alert without flashlight")
                    stopFlashlight()
                } catch (error: Exception) {
                    Log.w(LOG_TAG, "Flashlight failed; continuing alert without flashlight", error)
                    stopFlashlight()
                }
            }
        }

        handler?.post(flashRunnable!!)
        Log.d(LOG_TAG, "Flashlight strobe requested")
    }

    private fun stopFlashlight() {
        flashRunnable?.let { handler?.removeCallbacks(it) }
        flashRunnable = null

        val targetCameraId = cameraId

        if (
            targetCameraId != null &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            hasCameraPermission()
        ) {
            try {
                cameraManager?.setTorchMode(targetCameraId, false)
            } catch (_: Exception) {
                // Flashlight cleanup must never crash the alert service.
            }
        }

        isTorchOn = false
        Log.d(LOG_TAG, "Flashlight stopped")
    }

    // ─────────────────────────────────────────────────────────────
    // TTS
    // ─────────────────────────────────────────────────────────────

    private fun startTts() {
        val sessionId = alertSessionId

        Log.d(LOG_TAG, "Starting TTS initialization (attempt ${ttsRetryCount + 1})")

        shutdownTts()

        try {
            tts = TextToSpeech(this, this)
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Failed to create TextToSpeech", error)

            ttsRetryCount++

            if (ttsRetryCount < MAX_TTS_RETRIES) {
                handler?.postDelayed({
                    if (sessionId == alertSessionId) {
                        startTts()
                    }
                }, TTS_RETRY_INTERVAL_MS)
            } else {
                onTtsFailed()
            }
        }
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Log.e(LOG_TAG, "TTS initialization failed with status=$status")

            ttsRetryCount++

            if (ttsRetryCount < MAX_TTS_RETRIES) {
                val sessionId = alertSessionId

                handler?.postDelayed({
                    if (sessionId == alertSessionId) {
                        startTts()
                    }
                }, TTS_RETRY_INTERVAL_MS)
            } else {
                onTtsFailed()
            }

            return
        }

        isReady = true
        ttsRetryCount = 0

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        tts?.setAudioAttributes(audioAttributes)
        tts?.language = Locale.US
        tts?.setSpeechRate(0.95f)
        tts?.setPitch(1.0f)

        setAlarmStreamToMaximum()

        val sessionId = alertSessionId

        tts?.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    Log.d(LOG_TAG, "TTS started: ${speakCount + 1}/$ttsRepeatCount")
                }

                override fun onDone(utteranceId: String?) {
                    handler?.post {
                        if (sessionId == alertSessionId) {
                            onSpeechFinished()
                        }
                    }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    handler?.post {
                        if (sessionId == alertSessionId) {
                            onSpeechFinished()
                        }
                    }
                }

                override fun onError(
                    utteranceId: String?,
                    errorCode: Int,
                ) {
                    Log.e(LOG_TAG, "TTS error code=$errorCode")

                    handler?.post {
                        if (sessionId == alertSessionId) {
                            onSpeechFinished()
                        }
                    }
                }
            },
        )

        speakOnce()
    }

    private fun speakOnce() {
        if (
            !isReady ||
            tts == null ||
            message.isBlank() ||
            speakCount >= ttsRepeatCount
        ) {
            return
        }

        val utteranceId = "${alertMode}_${speakCount}_${System.currentTimeMillis()}"

        val parameters = Bundle().apply {
            putInt(
                TextToSpeech.Engine.KEY_PARAM_STREAM,
                AudioManager.STREAM_ALARM,
            )
        }

        try {
            val result = tts?.speak(
                message,
                TextToSpeech.QUEUE_FLUSH,
                parameters,
                utteranceId,
            )

            if (result == TextToSpeech.ERROR) {
                Log.e(LOG_TAG, "Could not start TTS speech")
                shutdownTts()
                continueAfterTts()
            }
        } catch (error: Exception) {
            Log.e(LOG_TAG, "TTS speak failed", error)
            shutdownTts()
            continueAfterTts()
        }
    }

    private fun onTtsFailed() {
        Log.e(LOG_TAG, "TTS initialization failed after retry limit")
        shutdownTts()
        continueAfterTts()
    }

    private fun onSpeechFinished() {
        if (speakCount + 1 < ttsRepeatCount) {
            speakCount++

            handler?.postDelayed(
                { speakOnce() },
                GAP_BETWEEN_SPEAKS_MS,
            )
            return
        }

        speakCount = ttsRepeatCount
        shutdownTts()
        continueAfterTts()
    }

    private fun continueAfterTts() {
        if (alertMode == MODE_CARETAKER_MEDICATION) {
            stopEverything()
            stopSelf()
        } else {
            startSelectedSound()
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Sound
    // ─────────────────────────────────────────────────────────────

    private fun startSelectedSound() {
        stopMediaPlayerOnly()

        if (alertMode == MODE_CARETAKER_MEDICATION) {
            return
        }

        val requestedResourceName = normalizeResourceName(soundResource)
        var resourceId = getRawResourceId(requestedResourceName)

        if (resourceId == 0) {
            Log.w(
                LOG_TAG,
                "Sound resource '$requestedResourceName' missing; using alarm fallback",
            )
            resourceId = getRawResourceId("alarm")
        }

        if (resourceId == 0) {
            Log.e(LOG_TAG, "No alarm raw resource was found")
            return
        }

        try {
            val descriptor = resources.openRawResourceFd(resourceId)

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_SONIFICATION,
                        )
                        .build(),
                )

                isLooping = loopSound

                setDataSource(
                    descriptor.fileDescriptor,
                    descriptor.startOffset,
                    descriptor.length,
                )

                descriptor.close()

                setOnPreparedListener { player ->
                    setAlarmStreamToMaximum()
                    player.start()
                    Log.d(
                        LOG_TAG,
                        "Playing sound=$requestedResourceName loop=$loopSound",
                    )
                }

                setOnCompletionListener {
                    if (!loopSound) {
                        stopEverything()
                        stopSelf()
                    }
                }

                setOnErrorListener { _, what, extra ->
                    Log.e(LOG_TAG, "MediaPlayer error: what=$what extra=$extra")

                    if (!loopSound) {
                        stopEverything()
                        stopSelf()
                    }

                    true
                }

                prepareAsync()
            }
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Could not play alarm sound", error)

            if (!loopSound) {
                stopEverything()
                stopSelf()
            }
        }
    }

    private fun normalizeResourceName(rawName: String): String {
        return rawName
            .trim()
            .lowercase()
            .removeSuffix(".mp3")
            .replace(Regex("[^a-z0-9_]"), "_")
            .ifBlank { defaultSoundResource(alertMode) }
    }

    private fun getValidResourceName(rawName: String): String {
        val normalized = normalizeResourceName(rawName)
        return if (getRawResourceId(normalized) == 0) "alarm" else normalized
    }

    private fun getRawResourceId(resourceName: String): Int {
        return resources.getIdentifier(resourceName, "raw", packageName)
    }

    // ─────────────────────────────────────────────────────────────
    // Scanner route
    // ─────────────────────────────────────────────────────────────

    private fun launchScannerScreen(scannerPayload: String) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = "com.example.mar.OPEN_SCANNER"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("payload", scannerPayload)
        }

        try {
            startActivity(launchIntent)
            Log.d(LOG_TAG, "Scanner screen launch requested")
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Could not launch scanner screen", error)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Vibration
    // ─────────────────────────────────────────────────────────────

    private fun startVibration() {
        when (vibrationMode.trim().lowercase()) {
            VIBRATION_NONE -> stopVibration()

            VIBRATION_FIVE_PULSES -> {
                vibrate(
                    pattern = FIVE_PULSE_VIBRATION_PATTERN,
                    repeatIndex = -1,
                )
            }

            else -> {
                vibrate(
                    pattern = CONTINUOUS_VIBRATION_PATTERN,
                    repeatIndex = 0,
                )
            }
        }

        Log.d(LOG_TAG, "Vibration started: $vibrationMode")
    }

    private fun vibrate(
        pattern: LongArray,
        repeatIndex: Int,
    ) {
        val activeVibrator = vibrator ?: return

        try {
            if (!activeVibrator.hasVibrator()) {
                Log.w(LOG_TAG, "Device reports no vibrator")
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activeVibrator.vibrate(
                    VibrationEffect.createWaveform(pattern, repeatIndex),
                )
            } else {
                @Suppress("DEPRECATION")
                activeVibrator.vibrate(pattern, repeatIndex)
            }
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Could not start vibration", error)
        }
    }

    private fun stopVibration() {
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Cleanup / audio
    // ─────────────────────────────────────────────────────────────

    private fun setAlarmStreamToMaximum() {
        try {
            val audioManager = getSystemService(
                Context.AUDIO_SERVICE,
            ) as AudioManager

            audioManager.setStreamVolume(
                AudioManager.STREAM_ALARM,
                audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                0,
            )
        } catch (error: Exception) {
            Log.w(LOG_TAG, "Could not set alarm stream volume", error)
        }
    }

    private fun shutdownTts() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }

        tts = null
        isReady = false
    }

    private fun stopMediaPlayerOnly() {
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {
        }

        try {
            mediaPlayer?.reset()
            mediaPlayer?.release()
        } catch (_: Exception) {
        }

        mediaPlayer = null
    }

    private fun stopAudioOnly() {
        handler?.removeCallbacksAndMessages(null)
        shutdownTts()
        stopMediaPlayerOnly()
    }

    private fun stopEverything() {
        alertSessionId = System.currentTimeMillis()

        stopAudioOnly()
        stopVibration()
        stopFlashlight()

        speakCount = 0
        ttsRetryCount = 0

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        stopEverything()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ─────────────────────────────────────────────────────────────
    // Foreground notification
    // ─────────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Medication and SOS Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Spoken medication reminders and emergency alerts"
            setBypassDnd(true)
            enableVibration(true)
            enableLights(true)
            lightColor = 0xFF00BFA5.toInt()
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP

            if (
                launchScanner &&
                payload.isNotBlank() &&
                alertMode != MODE_CARETAKER_MEDICATION
            ) {
                action = "com.example.mar.OPEN_SCANNER"
                putExtra("payload", payload)
            } else {
                action = Intent.ACTION_MAIN
            }
        }

        val openPending = PendingIntent.getActivity(
            this,
            alertMode.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stopPending = PendingIntent.getService(
            this,
            alertMode.hashCode() + 1,
            Intent(this, TtsSpeakService::class.java).apply {
                action = ACTION_STOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = when (alertMode) {
            MODE_PRIOR_REMINDER -> "Upcoming Medication"
            MODE_CARETAKER_SOS -> "URGENT PATIENT SOS"
            MODE_CARETAKER_MEDICATION -> "Patient Medication Alert"
            else -> "Medication Reminder"
        }

        val fallbackBody = when (alertMode) {
            MODE_PRIOR_REMINDER -> "A medication dose is due soon"
            MODE_CARETAKER_SOS -> "A patient needs urgent assistance"
            MODE_CARETAKER_MEDICATION -> "A patient's medication is due"
            else -> "Time to take your medicine"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(message.ifBlank { fallbackBody })
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    message.ifBlank { fallbackBody },
                ),
            )
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(
                if (alertMode == MODE_CARETAKER_SOS) {
                    NotificationCompat.CATEGORY_CALL
                } else {
                    NotificationCompat.CATEGORY_ALARM
                },
            )
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(loopSound && alertMode != MODE_CARETAKER_MEDICATION)
            .setAutoCancel(!loopSound || alertMode == MODE_CARETAKER_MEDICATION)
            .setContentIntent(openPending)
            .addAction(
                android.R.drawable.ic_media_pause,
                "Stop Alert",
                stopPending,
            )
            .build()
    }

    private fun getVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (
                    getSystemService(
                        Context.VIBRATOR_MANAGER_SERVICE,
                    ) as VibratorManager
                    ).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun defaultSoundResource(mode: String): String {
        return when (mode.trim().lowercase()) {
            MODE_PRIOR_REMINDER -> "prior_reminder"
            MODE_CARETAKER_SOS -> "caretaker_sos"
            MODE_CARETAKER_MEDICATION -> ""
            else -> "alarm"
        }
    }

    private fun defaultLoopSound(mode: String): Boolean {
        return when (mode.trim().lowercase()) {
            MODE_PRIOR_REMINDER -> false
            MODE_CARETAKER_SOS -> true
            MODE_CARETAKER_MEDICATION -> false
            else -> true
        }
    }

    private fun defaultLaunchScanner(
        mode: String,
        scannerPayload: String,
    ): Boolean {
        return mode.trim().lowercase() == MODE_MEDICATION_DUE &&
                scannerPayload.isNotBlank()
    }

    private fun defaultVibrationMode(mode: String): String {
        return when (mode.trim().lowercase()) {
            MODE_PRIOR_REMINDER -> VIBRATION_FIVE_PULSES
            MODE_CARETAKER_SOS,
            MODE_CARETAKER_MEDICATION,
                -> VIBRATION_CONTINUOUS

            else -> VIBRATION_CONTINUOUS
        }
    }

    private fun defaultFlashlightEnabled(mode: String): Boolean {
        return when (mode.trim().lowercase()) {
            MODE_MEDICATION_DUE,
            MODE_CARETAKER_SOS,
            MODE_CARETAKER_MEDICATION,
                -> true

            else -> false
        }
    }
}