package com.example.mar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class SosRealtimeService : Service() {

    companion object {
        const val ACTION_START = "ACTION_START_SOS_REALTIME"
        const val ACTION_STOP = "ACTION_STOP_SOS_REALTIME"
        const val EXTRA_CAREGIVER_ID = "caregiver_id"
        const val EXTRA_SUPABASE_URL = "supabase_url"
        const val EXTRA_SUPABASE_ANON_KEY = "supabase_anon_key"
        const val EXTRA_ACCESS_TOKEN = "access_token"

        private const val CHANNEL_ID = "sos_realtime_channel"
        private const val NOTIFICATION_ID = 9002
        private const val LOG_TAG = "MAR_ALERTS"

        private const val RECONNECT_DELAY_MS = 5_000L
        private const val MAX_RECONNECT_DELAY_MS = 60_000L
        private const val HEARTBEAT_INTERVAL_MS = 25_000L

        fun start(
            context: Context,
            caregiverId: String,
            supabaseUrl: String,
            supabaseAnonKey: String,
            accessToken: String
        ) {
            if (caregiverId.isBlank() || supabaseUrl.isBlank() || supabaseAnonKey.isBlank()) return
            val intent = Intent(context, SosRealtimeService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CAREGIVER_ID, caregiverId)
                putExtra(EXTRA_SUPABASE_URL, supabaseUrl)
                putExtra(EXTRA_SUPABASE_ANON_KEY, supabaseAnonKey)
                putExtra(EXTRA_ACCESS_TOKEN, accessToken)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, SosRealtimeService::class.java).apply { action = ACTION_STOP }
            )
        }
    }

    private var caregiverId = ""
    private var supabaseUrl = ""
    private var supabaseAnonKey = ""
    private var accessToken = ""

    private var webSocket: WebSocket? = null
    private var httpClient: OkHttpClient? = null
    private var handler: Handler? = null
    private var reconnectRunnable: Runnable? = null
    private var heartbeatRunnable: Runnable? = null

    private var reconnectDelayMs = RECONNECT_DELAY_MS
    private var isRunning = false
    private var isStopping = false
    private val ref = AtomicInteger(1)

    private val firedAlertIds = mutableSetOf<String>()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        handler = Handler(Looper.getMainLooper())
        httpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        if (action == ACTION_STOP) { stopSelf(); return START_NOT_STICKY }

        val newId = intent?.getStringExtra(EXTRA_CAREGIVER_ID) ?: return START_NOT_STICKY
        val newUrl = intent.getStringExtra(EXTRA_SUPABASE_URL) ?: return START_NOT_STICKY
        val newKey = intent.getStringExtra(EXTRA_SUPABASE_ANON_KEY) ?: return START_NOT_STICKY
        val newToken = intent.getStringExtra(EXTRA_ACCESS_TOKEN).orEmpty()
        if (newId.isBlank()) { stopSelf(); return START_NOT_STICKY }

        val tokenChanged = isRunning && newToken.isNotBlank() && newToken != accessToken

        caregiverId = newId
        supabaseUrl = newUrl
        supabaseAnonKey = newKey
        accessToken = newToken

        startForeground(NOTIFICATION_ID, buildNotification())

        when {
            !isRunning -> {
                isRunning = true; isStopping = false; connectWebSocket()
            }
            tokenChanged -> {
                Log.d(LOG_TAG, "Access token changed → reconnecting socket")
                reconnectNow()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        isStopping = true; isRunning = false
        cancelReconnect(); cancelHeartbeat()
        try { webSocket?.close(1000, "service stopping") } catch (_: Exception) {}
        webSocket = null
        httpClient?.dispatcher?.cancelAll()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── connection ──────────────────────────────────────────────
    private fun connectWebSocket() {
        if (isStopping) return
        val url = buildWebSocketUrl()
        Log.d(LOG_TAG, "Connecting to Supabase Realtime: $url")

        val request = Request.Builder()
            .url(url)
            .addHeader("apikey", supabaseAnonKey)            // connection auth
            .addHeader("Authorization", "Bearer $supabaseAnonKey")
            .addHeader("X-Client-Info", "mar-android/1.0.0")
            .build()

        webSocket = httpClient?.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(LOG_TAG, "WebSocket connected")
                reconnectDelayMs = RECONNECT_DELAY_MS
                handler?.post {
                    if (!isStopping) {
                        subscribeToSosAlerts(webSocket)
                        startHeartbeat(webSocket)
                    }
                }
            }
            override fun onMessage(webSocket: WebSocket, text: String) {
                handler?.post { handleIncomingMessage(text) }
            }
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(LOG_TAG, "WebSocket closing: $code $reason"); webSocket.close(1000, null)
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(LOG_TAG, "WebSocket closed: $code $reason")
                handler?.post { if (!isStopping) scheduleReconnect() }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(LOG_TAG, "WebSocket failure: $t")
                handler?.post { if (!isStopping) scheduleReconnect() }
            }
        })
    }

    private fun buildWebSocketUrl(): String {
        val base = supabaseUrl.trimEnd('/')
            .replace("https://", "wss://").replace("http://", "ws://")
        return "$base/realtime/v1/websocket?apikey=$supabaseAnonKey&vsn=1.0.0"
    }

    private fun reconnectNow() {
        cancelHeartbeat()
        try { webSocket?.close(1000, "token refresh") } catch (_: Exception) {}
        webSocket = null
        connectWebSocket()
    }

    // ── subscription (postgres_changes INSIDE the join config) ──
    private fun subscribeToSosAlerts(socket: WebSocket) {
        val topic = "realtime:sos_caretaker_$caregiverId"
        val joinRef = ref.getAndIncrement().toString()

        val join = JSONObject().apply {
            put("topic", topic)
            put("event", "phx_join")
            put("ref", joinRef)
            put("payload", JSONObject().apply {
                put("config", JSONObject().apply {
                    put("broadcast", JSONObject().apply { put("self", false) })
                    put("presence", JSONObject().apply { put("key", "") })
                    put("postgres_changes", JSONArray().apply {
                        put(JSONObject().apply {
                            put("event", "INSERT")
                            put("schema", "public")
                            put("table", "sos_alerts")
                            put("filter", "caregiver_id=eq.$caregiverId")
                        })
                    })
                })
                // RLS needs the user's JWT, not the anon key.
                put("access_token", accessToken.ifBlank { supabaseAnonKey })
            })
        }

        Log.d(LOG_TAG, "Sending phx_join on $topic ref=$joinRef")
        val sent = socket.send(join.toString())
        Log.d(LOG_TAG, "phx_join sent=$sent")
    }

    // ── incoming messages ───────────────────────────────────────
    private fun handleIncomingMessage(text: String) {
        Log.d(LOG_TAG, "RAW WS MESSAGE: $text")
        try {
            val json = JSONObject(text)
            val event = json.optString("event", "")
            val topic = json.optString("topic", "")

            if (event == "phx_reply") {
                val status = json.optJSONObject("payload")?.optString("status", "")
                if (status == "ok") Log.d(LOG_TAG, "✅ Subscription confirmed for topic: $topic")
                else Log.e(LOG_TAG, "❌ Subscription reply status=$status topic=$topic payload=${json.optJSONObject("payload")}")
                return
            }

            if (event != "postgres_changes") {
                Log.d(LOG_TAG, "Ignoring event: $event")
                return
            }

            val data = json.optJSONObject("payload")?.optJSONObject("data")
            val type = data?.optString("type", "")
            val record = data?.optJSONObject("record")
            Log.d(LOG_TAG, "postgres_changes type=$type record=$record")

            if (type != "INSERT" || record == null) return

            val status = record.optString("status", "")
            val alertId = record.optString("id", "")
            val receivedCaregiver = record.optString("caregiver_id", "")

            if (status != "sent") return
            if (alertId.isBlank()) return
            if (receivedCaregiver != caregiverId) return
            if (!firedAlertIds.add(alertId)) return

            val patientName = record.optString("patient_name", "A patient")
                .trim().ifBlank { "A patient" }

            Log.d(LOG_TAG, "🆘 SOS from $patientName (alertId=$alertId)")
            fireSosAlarm(patientName, alertId)
        } catch (e: Exception) {
            Log.e(LOG_TAG, "Parse error: $e  raw=$text")
        }
    }

    private fun fireSosAlarm(patientName: String, alertId: String) {
        val message = "Urgent! Urgent! $patientName has sent an emergency SOS. Please respond immediately."
        Log.d(LOG_TAG, "🔊 Firing SOS alarm for $patientName")

        val intent = Intent(this, TtsSpeakService::class.java).apply {
            action = TtsSpeakService.ACTION_START
            putExtra("message", message)
            putExtra("payload", alertId)
            putExtra("alertMode", TtsSpeakService.MODE_CARETAKER_SOS)
            putExtra("soundResource", "caretaker_sos")
            putExtra("loopSound", true)
            putExtra("launchScanner", false)
            putExtra("vibrationMode", TtsSpeakService.VIBRATION_CONTINUOUS)
            putExtra("ttsRepeatCount", 3)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
            else startService(intent)
            Log.d(LOG_TAG, "✅ TtsSpeakService started for SOS")
        } catch (e: Exception) {
            Log.e(LOG_TAG, "❌ Could not fire SOS alarm: $e", e)
        }
    }

    // ── housekeeping ────────────────────────────────────────────
    private fun scheduleReconnect() {
        if (isStopping) return; cancelReconnect()
        reconnectRunnable = Runnable { if (!isStopping) connectWebSocket() }
        handler?.postDelayed(reconnectRunnable!!, reconnectDelayMs)
        reconnectDelayMs = (reconnectDelayMs * 2).coerceAtMost(MAX_RECONNECT_DELAY_MS)
    }
    private fun cancelReconnect() { reconnectRunnable?.let { handler?.removeCallbacks(it) }; reconnectRunnable = null }

    private fun startHeartbeat(socket: WebSocket) {
        cancelHeartbeat()
        heartbeatRunnable = object : Runnable {
            override fun run() {
                if (isStopping) return
                try {
                    socket.send(JSONObject().apply {
                        put("topic", "phoenix"); put("event", "heartbeat")
                        put("payload", JSONObject()); put("ref", ref.getAndIncrement())
                    }.toString())
                } catch (e: Exception) { Log.w(LOG_TAG, "Heartbeat failed: $e") }
                handler?.postDelayed(this, HEARTBEAT_INTERVAL_MS)
            }
        }
        handler?.postDelayed(heartbeatRunnable!!, HEARTBEAT_INTERVAL_MS)
    }
    private fun cancelHeartbeat() { heartbeatRunnable?.let { handler?.removeCallbacks(it) }; heartbeatRunnable = null }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "SOS Alert Monitoring", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Keeps caretaker SOS monitoring active in the background"; setShowBadge(false)
            }
        )
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1,
            Intent(this, SosRealtimeService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("SOS Monitoring Active")
            .setContentText("Listening for patient emergencies")
            .setPriority(NotificationCompat.PRIORITY_LOW).setOngoing(true)
            .setContentIntent(open)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stop)
            .build()
    }
}