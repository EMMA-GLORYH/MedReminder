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
import androidx.core.app.NotificationCompat

class TtsSpeakService : Service(), TextToSpeech.OnInitListener {

    companion object {
        const val ACTION_START = "ACTION_START_TTS"
        const val ACTION_STOP  = "ACTION_STOP_TTS"

        private const val CHANNEL_ID = "tts_foreground_channel"
        private const val NOTIF_ID   = 9001

        // How many times the message is spoken before the app switches to
        // the looping alarm tone.
        private const val MAX_SPEAK_REPEATS = 3
        private const val GAP_BETWEEN_SPEAKS_MS = 600L

        // Heavy repeating vibration pattern (continues through both phases)
        private val VIBRATION_PATTERN = longArrayOf(
            0L,
            900L, 300L,
            900L, 300L,
            900L, 300L,
            1_300L, 400L,
            1_300L
        )
    }

    private var tts:         TextToSpeech? = null
    private var mediaPlayer: MediaPlayer?  = null
    private var handler:     Handler?      = null
    private var message:     String        = ""
    private var payload:     String        = ""   // ← scanner payload for auto-open
    private var isReady:     Boolean       = false
    private var vibrator:    Vibrator?     = null
    private var speakCount:  Int           = 0

    // ── Lifecycle ─────────────────────────────────────────
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        handler  = Handler(Looper.getMainLooper())
        vibrator = getVibrator()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        if (action == ACTION_STOP) {
            stopEverything()
            stopSelf()
            return START_NOT_STICKY
        }

        message = intent?.getStringExtra("message") ?: ""
        payload = intent?.getStringExtra("payload") ?: ""
        speakCount = 0

        // Auto-open scanner screen immediately (wakes phone, shows over lock)
        if (payload.isNotBlank()) {
            launchScannerScreen(payload)
        }

        startForeground(NOTIF_ID, buildNotification())
        startVibration()

        // Reset any previous alarm tone / TTS instance from an older alert
        stopAudioOnly()

        tts = TextToSpeech(this, this)

        return START_STICKY
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            // No TTS engine available — skip straight to the alarm tone so
            // the person still gets an audible alert.
            startAlarmSoundLoop()
            return
        }
        isReady = true

        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        tts?.setAudioAttributes(attrs)

        // Max alarm volume
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.setStreamVolume(
            AudioManager.STREAM_ALARM,
            am.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            0
        )

        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}

            override fun onDone(utteranceId: String?) {
                handler?.post { onSpeechFinished() }
            }

            @Deprecated("Deprecated in Java, still required to override")
            override fun onError(utteranceId: String?) {
                handler?.post { onSpeechFinished() }
            }
        })

        speakOnce()
    }

    private fun speakOnce() {
        if (!isReady) return
        val utteranceId = "tts_${speakCount}_${System.currentTimeMillis()}"
        tts?.speak(message, TextToSpeech.QUEUE_FLUSH, Bundle(), utteranceId)
    }

    private fun onSpeechFinished() {
        speakCount++
        if (speakCount < MAX_SPEAK_REPEATS) {
            handler?.postDelayed({ speakOnce() }, GAP_BETWEEN_SPEAKS_MS)
        } else {
            startAlarmSoundLoop()
        }
    }

    // ── Alarm tone (after the 3 spoken repeats) ───────────
    private fun startAlarmSoundLoop() {
        try { mediaPlayer?.stop(); mediaPlayer?.release() } catch (_: Exception) {}
        mediaPlayer = null

        try {
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                val afd = resources.openRawResourceFd(R.raw.alarm)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                prepare()
                start()
            }
        } catch (e: Exception) {
            // Missing/broken res/raw/alarm.mp3 shouldn't crash the service —
            // vibration keeps going even if the tone can't be played.
        }
    }

    // ── Launch scanner screen from background / lock screen ──
    private fun launchScannerScreen(payload: String) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action  = "com.example.mar.OPEN_SCANNER"
            flags   = Intent.FLAG_ACTIVITY_NEW_TASK        or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP      or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("payload", payload)
        }
        startActivity(launchIntent)
    }

    // ── Vibration ─────────────────────────────────────────
    private fun startVibration() {
        vibrator ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator!!.vibrate(
                VibrationEffect.createWaveform(VIBRATION_PATTERN, 0)
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator!!.vibrate(VIBRATION_PATTERN, 0)
        }
    }

    private fun stopVibration() {
        try { vibrator?.cancel() } catch (_: Exception) {}
    }

    // ── Stop just TTS/alarm audio, keep the service/notification alive ──
    private fun stopAudioOnly() {
        handler?.removeCallbacksAndMessages(null)
        try { tts?.stop(); tts?.shutdown() } catch (_: Exception) {}
        tts = null
        isReady = false
        try { mediaPlayer?.stop(); mediaPlayer?.release() } catch (_: Exception) {}
        mediaPlayer = null
    }

    // ── Stop everything ───────────────────────────────────
    private fun stopEverything() {
        stopAudioOnly()
        stopVibration()
        speakCount = 0
        try { stopForeground(true) } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopEverything()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Notification ──────────────────────────────────────
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Medication TTS Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Spoken medication reminders"
                setBypassDnd(true)
                enableVibration(true)
                enableLights(true)
                lightColor = 0xFF00BFA5.toInt()
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = "com.example.mar.OPEN_SCANNER"
            flags  = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("payload", payload)
        }
        val openPending = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopPending = PendingIntent.getService(
            this, 1,
            Intent(this, TtsSpeakService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("💊 Medication Reminder")
            .setContentText(message.ifBlank { "Time to take your medicine" })
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText(message.ifBlank { "Time to take your medicine" }))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(openPending, true)
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(android.R.drawable.ic_media_pause, "Stop Reminder", stopPending)
            .build()
    }

    // ── Compat vibrator ───────────────────────────────────
    private fun getVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }
}