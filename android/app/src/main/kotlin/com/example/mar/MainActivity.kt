package com.example.mar

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "medication_tts_background"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleStart" -> {
                        val alarmId = call.argument<Int>("alarmId") ?: 0
                        val startAtMillis = call.argument<Long>("startAtMillis") ?: 0L
                        val message = call.argument<String>("message") ?: ""
                        scheduleTtsAlarm(alarmId, startAtMillis, message)
                        result.success(null)
                    }
                    "cancelAlarm" -> {
                        val alarmId = call.argument<Int>("alarmId") ?: 0
                        cancelTtsAlarm(alarmId)
                        result.success(null)
                    }
                    "stop" -> {
                        stopTtsService()
                        result.success(null)
                    }
                    "start" -> {
                        // Optional foreground start
                        val message = call.argument<String>("message") ?: ""
                        startTtsService(message)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun scheduleTtsAlarm(alarmId: Int, startAtMillis: Long, message: String) {
        val context = this
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, TtsAlarmReceiver::class.java).apply {
            putExtra("alarmId", alarmId)
            putExtra("message", message)
        }

        val flags = pendingIntentFlags()
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            flags
        )

        val triggerAtMillis = startAtMillis

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent
            )
        }
    }

    private fun cancelTtsAlarm(alarmId: Int) {
        val context = this
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, TtsAlarmReceiver::class.java)
        val flags = pendingIntentFlags()
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            flags
        )

        alarmManager.cancel(pendingIntent)
    }

    private fun startTtsService(message: String) {
        val intent = Intent(this, TtsSpeakService::class.java).apply {
            action = TtsSpeakService.ACTION_START
            putExtra("message", message)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopTtsService() {
        val intent = Intent(this, TtsSpeakService::class.java).apply {
            action = TtsSpeakService.ACTION_STOP
        }
        stopService(intent)
    }

    private fun pendingIntentFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        flags = flags or PendingIntent.FLAG_IMMUTABLE
        return flags
    }
}