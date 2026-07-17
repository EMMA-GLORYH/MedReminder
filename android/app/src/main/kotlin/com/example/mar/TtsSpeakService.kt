// android/app/src/main/kotlin/com/example/mar/TtsSpeakService.kt

package com.example.mar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
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

class TtsSpeakService : Service(), TextToSpeech.OnInitListener {

    companion object {
        const val ACTION_START = "ACTION_START_TTS"
        const val ACTION_STOP = "ACTION_STOP_TTS"

        const val MODE_MEDICATION_DUE = "medication_due"
        const val MODE_PRIOR_REMINDER = "prior_reminder"
        const val MODE_CARETAKER_SOS = "caretaker_sos"

        const val VIBRATION_CONTINUOUS = "continuous"
        const val VIBRATION_FIVE_PULSES = "five_pulses"
        const val VIBRATION_NONE = "none"

        private const val CHANNEL_ID = "tts_foreground_channel"
        private const val NOTIFICATION_ID = 9001
        private const val LOG_TAG = "MAR_ALERTS"

        private const val DEFAULT_TTS_REPEAT_COUNT = 3
        private const val GAP_BETWEEN_SPEAKS_MS = 600L
        private const val FLASH_TOGGLE_INTERVAL_MS = 400L // Strobe interval in milliseconds

        /*
         * Continuous heavy vibration.
         * index 0 restarts this sequence until ACTION_STOP is received.
         */
        private val CONTINUOUS_VIBRATION_PATTERN = longArrayOf(
            0L,
            900L, 300L,
            900L, 300L,
            900L, 300L,
            1_300L, 400L,
            1_300L
        )

        /*
         * Five prior-reminder vibration pulses, without repeat.
         */
        private val FIVE_PULSE_VIBRATION_PATTERN = longArrayOf(
            0L,
            300L, 220L,
            300L, 220L,
            300L, 220L,
            300L, 220L,
            300L
        )
    }

    private var tts: TextToSpeech? = null
    private var mediaPlayer: MediaPlayer? = null
    private var handler: Handler? = null
    private var vibrator: Vibrator? = null

    // Torch / Flashlight state
    private var cameraManager: CameraManager? = null
    private var cameraId: String? = null
    private var isTorchOn: Boolean = false
    private var flashRunnable: Runnable? = null

    private var message: String = ""
    private var payload: String = ""

    private var alertMode: String = MODE_MEDICATION_DUE
    private var soundResource: String = "alarm"
    private var vibrationMode: String = VIBRATION_CONTINUOUS

    private var loopSound: Boolean = true
    private var launchScanner: Boolean = true
    private var ttsRepeatCount: Int = DEFAULT_TTS_REPEAT_COUNT

    private var isReady: Boolean = false
    private var speakCount: Int = 0

    /*
     * Each ACTION_START increments the session. Callbacks from a previous
     * alert can no longer continue after a newer alert begins.
     */
    private var alertSessionId: Long = 0L

    // ──────────────────────────────────────────────────────────────
    // Lifecycle
    // ──────────────────────────────────────────────────────────────

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
        startId: Int
    ): Int {
        val action = intent?.action ?: ACTION_START

        if (action == ACTION_STOP) {
            stopEverything()
            stopSelf()
            return START_NOT_STICKY
        }

        alertSessionId = System.currentTimeMillis()

        message = intent
            ?.getStringExtra("message")
            ?.trim()
            .orEmpty()

        payload = intent
            ?.getStringExtra("payload")
            .orEmpty()

        alertMode = intent
            ?.getStringExtra("alertMode")
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotBlank() }
            ?: MODE_MEDICATION_DUE

        soundResource = getValidResourceName(
            intent?.getStringExtra("soundResource")
                ?: defaultSoundResource(alertMode)
        )

        loopSound = if (intent?.hasExtra("loopSound") == true) {
            intent.getBooleanExtra(
                "loopSound",
                defaultLoopSound(alertMode)
            )
        } else {
            defaultLoopSound(alertMode)
        }

        launchScanner = if (intent?.hasExtra("launchScanner") == true) {
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

        vibrationMode = intent
            ?.getStringExtra("vibrationMode")
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: defaultVibrationMode(alertMode)

        ttsRepeatCount = intent
            ?.getIntExtra(
                "ttsRepeatCount",
                DEFAULT_TTS_REPEAT_COUNT
            )
            ?.coerceIn(0, 10)
            ?: DEFAULT_TTS_REPEAT_COUNT

        speakCount = 0

        Log.d(
            LOG_TAG,
            "Starting alert: " +
                    "mode=$alertMode, " +
                    "sound=$soundResource, " +
                    "loop=$loopSound, " +
                    "launchScanner=$launchScanner, " +
                    "vibration=$vibrationMode, " +
                    "ttsRepeats=$ttsRepeatCount"
        )

        /*
         * Exact medication reminders launch the confirmation/scanner
         * automatically. SOS and prior reminders do not.
         */
        if (launchScanner && payload.isNotBlank()) {
            launchScannerScreen(payload)
        }

        startForeground(
            NOTIFICATION_ID,
            buildNotification()
        )

        stopAudioOnly()
        stopVibration()
        stopFlashlight()

        startVibration()

        /*
         * Flash physical LED only for high-priority alerts (Medication Due & SOS).
         */
        if (alertMode == MODE_MEDICATION_DUE || alertMode == MODE_CARETAKER_SOS) {
            startFlashlightStrobe()
        }

        /*
         * Medication and SOS use configured speech repetition.
         * If speech is not required or unavailable, skip to sound.
         */
        if (ttsRepeatCount <= 0 || message.isBlank()) {
            startSelectedSound()
        } else {
            startTts()
        }

        return START_STICKY
    }

    // ──────────────────────────────────────────────────────────────
    // Flashlight Controller
    // ──────────────────────────────────────────────────────────────

    private fun initCameraManager() {
        try {
            cameraManager = getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            val ids = cameraManager?.cameraIdList ?: emptyArray()
            for (id in ids) {
                val characteristics = cameraManager?.getCameraCharacteristics(id)
                val hasFlash = characteristics?.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                val facing = characteristics?.get(CameraCharacteristics.LENS_FACING)
                if (hasFlash && facing == CameraCharacteristics.LENS_FACING_BACK) {
                    cameraId = id
                    break
                }
            }
        } catch (e: Exception) {
            Log.e(LOG_TAG, "Could not initialize camera flash", e)
        }
    }

    private fun startFlashlightStrobe() {
        val targetCamId = cameraId ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        flashRunnable = object : Runnable {
            override fun run() {
                try {
                    isTorchOn = !isTorchOn
                    cameraManager?.setTorchMode(targetCamId, isTorchOn)
                    handler?.postDelayed(this, FLASH_TOGGLE_INTERVAL_MS)
                } catch (e: Exception) {
                    Log.e(LOG_TAG, "Torch mode error", e)
                }
            }
        }
        handler?.post(flashRunnable as Runnable)
        Log.d(LOG_TAG, "Camera flashlight strobe started")
    }

    private fun stopFlashlight() {
        flashRunnable?.let { handler?.removeCallbacks(it) }
        flashRunnable = null

        val targetCamId = cameraId
        if (targetCamId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                cameraManager?.setTorchMode(targetCamId, false)
            } catch (_: Exception) {}
        }
        isTorchOn = false
    }

    // ──────────────────────────────────────────────────────────────
    // Text-to-Speech initialization
    // ──────────────────────────────────────────────────────────────

    private fun startTts() {
        shutdownTts()

        tts = TextToSpeech(this, this)
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Log.e(
                LOG_TAG,
                "TTS initialization failed; starting fallback sound"
            )

            shutdownTts()
            startSelectedSound()
            return
        }

        isReady = true

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        tts?.setAudioAttributes(audioAttributes)

        setAlarmStreamToMaximum()

        val sessionId = alertSessionId

        tts?.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    Log.d(
                        LOG_TAG,
                        "TTS started: " +
                                "${speakCount + 1}/$ttsRepeatCount"
                    )
                }

                override fun onDone(utteranceId: String?) {
                    handler?.post {
                        if (sessionId == alertSessionId) {
                            onSpeechFinished()
                        }
                    }
                }

                @Deprecated(
                    "Deprecated in Java, but still required"
                )
                override fun onError(utteranceId: String?) {
                    Log.e(
                        LOG_TAG,
                        "TTS reported legacy error"
                    )

                    handler?.post {
                        if (sessionId == alertSessionId) {
                            onSpeechFinished()
                        }
                    }
                }

                override fun onError(
                    utteranceId: String?,
                    errorCode: Int
                ) {
                    Log.e(
                        LOG_TAG,
                        "TTS error code: $errorCode"
                    )

                    handler?.post {
                        if (sessionId == alertSessionId) {
                            onSpeechFinished()
                        }
                    }
                }
            }
        )

        speakOnce()
    }

    private fun speakOnce() {
        if (!isReady ||
            tts == null ||
            message.isBlank() ||
            speakCount >= ttsRepeatCount
        ) {
            return
        }

        val utteranceId =
            "${alertMode}_${speakCount}_${System.currentTimeMillis()}"

        val parameters = Bundle().apply {
            putInt(
                TextToSpeech.Engine.KEY_PARAM_STREAM,
                AudioManager.STREAM_ALARM
            )
        }

        val result = tts?.speak(
            message,
            TextToSpeech.QUEUE_FLUSH,
            parameters,
            utteranceId
        )

        if (result == TextToSpeech.ERROR) {
            Log.e(LOG_TAG, "Could not start TTS speech")

            shutdownTts()
            startSelectedSound()
        }
    }

    private fun onSpeechFinished() {
        if (speakCount + 1 < ttsRepeatCount) {
            speakCount++

            handler?.postDelayed(
                { speakOnce() },
                GAP_BETWEEN_SPEAKS_MS
            )
        } else {
            speakCount = ttsRepeatCount

            Log.d(
                LOG_TAG,
                "TTS completed $ttsRepeatCount repetition(s)"
            )

            shutdownTts()
            startSelectedSound()
        }
    }

    // ──────────────────────────────────────────────────────────────
    // MP3 playback
    // ──────────────────────────────────────────────────────────────

    private fun startSelectedSound() {
        stopMediaPlayerOnly()

        val requestedResourceName =
            normalizeResourceName(soundResource)

        var resourceId = getRawResourceId(
            requestedResourceName
        )
        Log.d(
            LOG_TAG,
            "Sound lookup: resource='$requestedResourceName', " +
                    "id=$resourceId, package=$packageName"
        )

        if (resourceId == 0) {
            Log.e(
                LOG_TAG,
                "Sound resource '$requestedResourceName' not found; " +
                        "falling back to alarm"
            )

            resourceId = getRawResourceId("alarm")
        }

        if (resourceId == 0) {
            Log.e(
                LOG_TAG,
                "No fallback alarm resource found"
            )
            return
        }

        try {
            val fileDescriptor =
                resources.openRawResourceFd(resourceId)

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_SONIFICATION
                        )
                        .build()
                )

                isLooping = loopSound

                setDataSource(
                    fileDescriptor.fileDescriptor,
                    fileDescriptor.startOffset,
                    fileDescriptor.length
                )

                fileDescriptor.close()

                setOnPreparedListener { player ->
                    setAlarmStreamToMaximum()
                    player.start()

                    Log.d(
                        LOG_TAG,
                        "Playing sound: " +
                                "$requestedResourceName, " +
                                "looping=$loopSound"
                    )
                }

                setOnCompletionListener {
                    /*
                     * Non-looping prior reminders stop automatically when
                     * their MP3 finishes.
                     */
                    if (!loopSound) {
                        handler?.post {
                            stopEverything()
                            stopSelf()
                        }
                    }
                }

                setOnErrorListener { _, what, extra ->
                    Log.e(
                        LOG_TAG,
                        "MediaPlayer error: what=$what, extra=$extra"
                    )

                    if (!loopSound) {
                        handler?.post {
                            stopEverything()
                            stopSelf()
                        }
                    }

                    true
                }

                prepareAsync()
            }
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "Failed to play raw/$requestedResourceName.mp3",
                error
            )

            if (!loopSound) {
                stopEverything()
                stopSelf()
            }
        }
    }

    private fun normalizeResourceName(
        rawName: String
    ): String {
        return rawName
            .trim()
            .lowercase()
            .removeSuffix(".mp3")
            .replace(
                Regex("[^a-z0-9_]"),
                "_"
            )
            .ifBlank {
                defaultSoundResource(alertMode)
            }
    }

    private fun getValidResourceName(
        rawName: String
    ): String {
        val normalized = normalizeResourceName(rawName)

        val resourceId = getRawResourceId(normalized)

        if (resourceId == 0) {
            return "alarm"
        }

        return normalized
    }

    private fun getRawResourceId(
        resourceName: String
    ): Int {
        return resources.getIdentifier(
            resourceName,
            "raw",
            packageName
        )
    }

    // ──────────────────────────────────────────────────────────────
    // Scanner / confirmation screen launch
    // ──────────────────────────────────────────────────────────────

    private fun launchScannerScreen(
        scannerPayload: String
    ) {
        val launchIntent =
            Intent(this, MainActivity::class.java).apply {
                action =
                    "com.example.mar.OPEN_SCANNER"

                flags =
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP

                putExtra("payload", scannerPayload)
            }

        try {
            startActivity(launchIntent)

            Log.d(
                LOG_TAG,
                "Scanner screen launch requested"
            )
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "Could not launch scanner screen",
                error
            )
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Vibration
    // ──────────────────────────────────────────────────────────────

    private fun startVibration() {
        when (vibrationMode.trim().lowercase()) {
            VIBRATION_NONE -> {
                stopVibration()
            }

            VIBRATION_FIVE_PULSES -> {
                vibrate(
                    pattern = FIVE_PULSE_VIBRATION_PATTERN,
                    repeatIndex = -1
                )
            }

            else -> {
                vibrate(
                    pattern = CONTINUOUS_VIBRATION_PATTERN,
                    repeatIndex = 0
                )
            }
        }

        Log.d(
            LOG_TAG,
            "Vibration started: $vibrationMode"
        )
    }

    private fun vibrate(
        pattern: LongArray,
        repeatIndex: Int
    ) {
        val activeVibrator = vibrator ?: return

        try {
            if (!activeVibrator.hasVibrator()) {
                Log.w(
                    LOG_TAG,
                    "Device reports no vibrator"
                )
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activeVibrator.vibrate(
                    VibrationEffect.createWaveform(
                        pattern,
                        repeatIndex
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                activeVibrator.vibrate(
                    pattern,
                    repeatIndex
                )
            }
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "Could not start vibration",
                error
            )
        }
    }

    private fun stopVibration() {
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Audio management
    // ──────────────────────────────────────────────────────────────

    private fun setAlarmStreamToMaximum() {
        try {
            val audioManager =
                getSystemService(
                    Context.AUDIO_SERVICE
                ) as AudioManager

            audioManager.setStreamVolume(
                AudioManager.STREAM_ALARM,
                audioManager.getStreamMaxVolume(
                    AudioManager.STREAM_ALARM
                ),
                0
            )
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "Could not raise alarm stream volume",
                error
            )
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

        try {
            if (Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.N
            ) {
                stopForeground(
                    STOP_FOREGROUND_REMOVE
                )
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

    // ──────────────────────────────────────────────────────────────
    // Foreground notification
    // ──────────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT <
            Build.VERSION_CODES.O
        ) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Medication and SOS Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description =
                "Spoken medication reminders and emergency alerts"

            setBypassDnd(true)
            enableVibration(true)
            enableLights(true)

            lightColor = 0xFF00BFA5.toInt()
            lockscreenVisibility =
                Notification.VISIBILITY_PUBLIC
        }

        getSystemService(
            NotificationManager::class.java
        ).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openIntent =
            Intent(this, MainActivity::class.java).apply {
                flags =
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP

                if (launchScanner &&
                    payload.isNotBlank()
                ) {
                    action =
                        "com.example.mar.OPEN_SCANNER"

                    putExtra("payload", payload)
                } else {
                    action = Intent.ACTION_MAIN
                }
            }

        val openPending = PendingIntent.getActivity(
            this,
            alertMode.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
        )

        val stopPending = PendingIntent.getService(
            this,
            alertMode.hashCode() + 1,
            Intent(
                this,
                TtsSpeakService::class.java
            ).apply {
                action = ACTION_STOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
        )

        val title = when (alertMode) {
            MODE_PRIOR_REMINDER ->
                "Upcoming Medication"

            MODE_CARETAKER_SOS ->
                "URGENT PATIENT SOS"

            else ->
                "Medication Reminder"
        }

        val fallbackBody = when (alertMode) {
            MODE_PRIOR_REMINDER ->
                "A medication dose is due soon"

            MODE_CARETAKER_SOS ->
                "A patient needs urgent assistance"

            else ->
                "Time to take your medicine"
        }

        val builder = NotificationCompat.Builder(
            this,
            CHANNEL_ID
        )
            .setSmallIcon(
                android.R.drawable.ic_lock_idle_alarm
            )
            .setContentTitle(title)
            .setContentText(
                message.ifBlank {
                    fallbackBody
                }
            )
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(
                        message.ifBlank {
                            fallbackBody
                        }
                    )
            )
            .setPriority(
                NotificationCompat.PRIORITY_MAX
            )
            .setCategory(
                if (alertMode == MODE_CARETAKER_SOS) {
                    NotificationCompat.CATEGORY_CALL
                } else {
                    NotificationCompat.CATEGORY_ALARM
                }
            )
            .setVisibility(
                NotificationCompat.VISIBILITY_PUBLIC
            )
            .setOngoing(loopSound)
            .setAutoCancel(!loopSound)
            .setContentIntent(openPending)
            .addAction(
                android.R.drawable.ic_media_pause,
                "Stop Alert",
                stopPending
            )

        /*
         * Full-screen only belongs to exact medication reminders.
         * SOS alerts do not automatically open the scanner; they appear in
         * the caretaker Alerts tab and over the normal audible alert.
         */
        if (alertMode == MODE_MEDICATION_DUE &&
            launchScanner &&
            payload.isNotBlank()
        ) {
            builder.setFullScreenIntent(
                openPending,
                true
            )
        }

        return builder.build()
    }

    // ──────────────────────────────────────────────────────────────
    // Vibrator compatibility
    // ──────────────────────────────────────────────────────────────

    private fun getVibrator(): Vibrator? {
        return if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.S
        ) {
            (
                    getSystemService(
                        Context.VIBRATOR_MANAGER_SERVICE
                    ) as VibratorManager
                    ).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(
                Context.VIBRATOR_SERVICE
            ) as? Vibrator
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Backward-compatible defaults
    // ──────────────────────────────────────────────────────────────

    private fun defaultSoundResource(
        mode: String
    ): String {
        return when (mode.trim().lowercase()) {
            MODE_PRIOR_REMINDER ->
                "prior_reminder"

            MODE_CARETAKER_SOS ->
                "caretaker_sos"

            else ->
                "alarm"
        }
    }

    private fun defaultLoopSound(
        mode: String
    ): Boolean {
        return when (mode.trim().lowercase()) {
            MODE_PRIOR_REMINDER -> false
            MODE_CARETAKER_SOS -> true
            else -> true
        }
    }

    private fun defaultLaunchScanner(
        mode: String,
        scannerPayload: String
    ): Boolean {
        return mode.trim().lowercase() ==
                MODE_MEDICATION_DUE &&
                scannerPayload.isNotBlank()
    }

    private fun defaultVibrationMode(
        mode: String
    ): String {
        return when (mode.trim().lowercase()) {
            MODE_PRIOR_REMINDER ->
                VIBRATION_FIVE_PULSES

            MODE_CARETAKER_SOS ->
                VIBRATION_CONTINUOUS

            else ->
                VIBRATION_CONTINUOUS
        }
    }
}