package com.example.mar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes // ✅ REQUIRED
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat

class TtsSpeakService : Service(), TextToSpeech.OnInitListener {

    companion object {
        const val ACTION_START = "ACTION_START_TTS"
        const val ACTION_STOP = "ACTION_STOP_TTS"
        private const val CHANNEL_ID = "tts_foreground_channel"
        private const val NOTIF_ID = 9001
        private const val REPEAT_MS: Long = 8000L
    }

    private var tts: TextToSpeech? = null
    private var handler: Handler? = null
    private var message: String = ""
    private var isReady: Boolean = false

    private val repeatRunnable = object : Runnable {
        override fun run() {
            if (!isReady) return
            tts?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "tts_${System.currentTimeMillis()}")
            handler?.postDelayed(this, REPEAT_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        handler = Handler()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val act = intent?.action ?: ACTION_START
        if (act == ACTION_STOP) {
            stopSpeaking()
            stopSelf()
            return START_NOT_STICKY
        }

        message = intent?.getStringExtra("message") ?: ""
        startForeground(NOTIF_ID, buildNotification())

        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}

        tts = TextToSpeech(this, this)
        return START_STICKY
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isReady = true

            // ✅ FORCE ALARM AUDIO STREAM
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            tts?.setAudioAttributes(audioAttributes)

            handler?.removeCallbacks(repeatRunnable)
            tts?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "tts_${System.currentTimeMillis()}")
            handler?.postDelayed(repeatRunnable, REPEAT_MS)
        }
    }

    private fun stopSpeaking() {
        handler?.removeCallbacks(repeatRunnable)
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        isReady = false
        try { stopForeground(true) } catch (_: Exception) {}
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Medication Reminder")
            .setContentText("Reading dose...")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(CHANNEL_ID, "TTS Reminders", NotificationManager.IMPORTANCE_HIGH)
            mgr.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        stopSpeaking()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}