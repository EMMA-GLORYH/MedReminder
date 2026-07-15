// android/app/src/main/kotlin/com/example/mar/TtsSpeakService.kt

package com.example.mar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
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

        /*
         * Continuous heavy vibration.
         *
         * The repeat index is 0, so Android repeats this pattern until
         * ACTION_STOP is received.
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
         * Five distinct vibration pulses.
         *
         * This pattern is not repeated. It is used for the ten-minute
         * prior medication reminder.
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

    // Prevents callbacks from an older alert from continuing a newer session.
    private var alertSessionId: Long = 0L

    // ──────────────────────────────────────────────────────────
    // Lifecycle
    // ──────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()

        createNotificationChannel()

        handler = Handler(Looper.getMainLooper())
        vibrator = getVibrator()
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

        // Increment the session so callbacks from a previous alert can
        // no longer continue the old speech/sound sequence.
        alertSessionId = System.currentTimeMillis()

        message = intent?.getStringExtra("message").orEmpty()
        payload = intent?.getStringExtra("payload").orEmpty()

        alertMode = intent?.getStringExtra("alertMode")
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

        vibrationMode = intent?.getStringExtra("vibrationMode")
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
         * Existing medication behavior is preserved:
         * medication_due + payload automatically opens the scanner.
         *
         * prior_reminder and caretaker_sos default to no scanner.
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

        startVibration()

        /*
         * If no TTS repetitions were requested, go directly to the
         * selected sound resource.
         */
        if (ttsRepeatCount <= 0 || message.isBlank()) {
            startSelectedSound()
        } else {
            tts = TextToSpeech(this, this)
        }

        return START_STICKY
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Log.e(
                LOG_TAG,
                "TTS initialization failed; starting fallback sound"
            )

            isReady = false
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

    // ──────────────────────────────────────────────────────────
    // Text-to-speech
    // ──────────────────────────────────────────────────────────

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
            onSpeechFinished()
        }
    }

    private fun onSpeechFinished() {
        speakCount++

        if (speakCount < ttsRepeatCount) {
            handler?.postDelayed(
                { speakOnce() },
                GAP_BETWEEN_SPEAKS_MS
            )
        } else {
            Log.d(
                LOG_TAG,
                "TTS completed $ttsRepeatCount repetition(s)"
            )

            shutdownTts()
            startSelectedSound()
        }
    }

    // ──────────────────────────────────────────────────────────
    // Selected MP3 sound
    // ──────────────────────────────────────────────────────────

    private fun startSelectedSound() {
        stopMediaPlayerOnly()

        val requestedResourceName =
            normalizeResourceName(soundResource)

        var resourceId = resources.getIdentifier(
            requestedResourceName,
            "raw",
            packageName
        )

        /*
         * If prior_reminder.mp3 or caretaker_sos.mp3 is missing,
         * fall back to the existing alarm.mp3 so the alert remains
         * audible instead of silently failing.
         */
        if (resourceId == 0) {
            Log.e(
                LOG_TAG,
                "Sound resource '$requestedResourceName' not found; " +
                        "falling back to alarm"
            )

            resourceId = resources.getIdentifier(
                "alarm",
                "raw",
                packageName
            )
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

                setOnPreparedListener {
                    setAlarmStreamToMaximum()
                    it.start()

                    Log.d(
                        LOG_TAG,
                        "Playing sound: " +
                                "$requestedResourceName, " +
                                "looping=$loopSound"
                    )
                }

                setOnCompletionListener {
                    /*
                     * Prior reminders use a non-looping sound. After the
                     * MP3 finishes, the service can stop automatically.
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
        val normalized = rawName
            .trim()
            .lowercase()
            .removeSuffix(".mp3")
            .replace(
                Regex("[^a-z0-9_]"),
                "_"
            )

        return normalized.ifBlank {
            defaultSoundResource(alertMode)
        }
    }

    private fun getValidResourceName(
        rawName: String
    ): String {
        val normalized = normalizeResourceName(rawName)

        val resourceId = resources.getIdentifier(
            normalized,
            "raw",
            packageName
        )

        if (resourceId == 0) {
            return "alarm"
        }

        return normalized
    }

    // ──────────────────────────────────────────────────────────
    // Scanner launch
    // ──────────────────────────────────────────────────────────

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

    // ──────────────────────────────────────────────────────────
    // Vibration
    // ──────────────────────────────────────────────────────────

    private fun startVibration() {
        when (vibrationMode) {
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

    // ──────────────────────────────────────────────────────────
    // Audio control
    // ──────────────────────────────────────────────────────────

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
        // Invalidates all callbacks from the current alert.
        alertSessionId = System.currentTimeMillis()

        stopAudioOnly()
        stopVibration()

        speakCount = 0

        try {
            if (Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.N) {
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

    // ──────────────────────────────────────────────────────────
    // Foreground notification
    // ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT <
            Build.VERSION_CODES.O) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Medication and SOS Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description =
                "Spoken medication reminders and emergency SOS alerts"

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
                    action =
                        Intent.ACTION_MAIN
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
         * Only the exact medication reminder opens the scanner over
         * the lock screen. Prior reminders and caretaker SOS do not
         * accidentally open the scanner.
         */
        if (launchScanner &&
            payload.isNotBlank()
        ) {
            builder.setFullScreenIntent(
                openPending,
                true
            )
        }

        return builder.build()
    }

    // ──────────────────────────────────────────────────────────
    // Vibrator compatibility
    // ──────────────────────────────────────────────────────────

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

    // ──────────────────────────────────────────────────────────
    // Backward-compatible defaults
    // ──────────────────────────────────────────────────────────

    private fun defaultSoundResource(
        mode: String
    ): String {
        return when (mode) {
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
        return when (mode) {
            MODE_PRIOR_REMINDER -> false
            MODE_CARETAKER_SOS -> true
            else -> true
        }
    }

    private fun defaultLaunchScanner(
        mode: String,
        scannerPayload: String
    ): Boolean {
        return mode == MODE_MEDICATION_DUE &&
                scannerPayload.isNotBlank()
    }

    private fun defaultVibrationMode(
        mode: String
    ): String {
        return when (mode) {
            MODE_PRIOR_REMINDER ->
                VIBRATION_FIVE_PULSES

            MODE_CARETAKER_SOS ->
                VIBRATION_CONTINUOUS

            else ->
                VIBRATION_CONTINUOUS
        }
    }
}