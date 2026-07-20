// android/app/src/main/kotlin/com/example/mar/SmsSosReceiver.kt

package com.example.mar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsMessage
import android.util.Log
import org.json.JSONObject

class SmsSosReceiver : BroadcastReceiver() {

    companion object {
        private const val LOG_TAG = "MAR_ALERTS"

        private const val SMS_PREFIX = "MAR-SOS"

        private const val KEY_PREFIX = "k:"
        private const val NAME_PREFIX = "n:"
        private const val LOCATION_PREFIX = "g:"

        private const val PREFS_NAME =
            "mar_sos_sms_preferences"

        private const val SEEN_KEYS_NAME =
            "seen_sos_keys"

        private const val MAX_STORED_KEYS = 500
    }

    override fun onReceive(
        context: Context,
        intent: Intent
    ) {
        if (
            intent.action !=
            Telephony.Sms.Intents.SMS_RECEIVED_ACTION
        ) {
            return
        }

        val messages = try {
            Telephony.Sms.Intents
                .getMessagesFromIntent(intent)
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "Could not read incoming SMS",
                error
            )
            return
        }

        if (messages.isNullOrEmpty()) {
            return
        }

        /*
         * Multipart SMS messages may arrive as several SmsMessage objects.
         * Group them by sender and combine their bodies before parsing.
         */
        val messagesBySender =
            LinkedHashMap<String, StringBuilder>()

        for (sms in messages) {
            val sender =
                sms.originatingAddress
                    ?.trim()
                    .orEmpty()

            val body =
                sms.messageBody
                    ?.trim()
                    .orEmpty()

            if (sender.isEmpty() || body.isEmpty()) {
                continue
            }

            messagesBySender
                .getOrPut(sender) {
                    StringBuilder()
                }
                .append(body)
        }

        for ((sender, bodyBuilder) in messagesBySender) {
            val body = bodyBuilder.toString().trim()

            if (!body.startsWith(SMS_PREFIX)) {
                continue
            }

            Log.d(
                LOG_TAG,
                "Tagged SOS SMS received from $sender: $body"
            )

            handleSosSms(
                context = context,
                body = body
            )
        }
    }

    private fun handleSosSms(
        context: Context,
        body: String
    ) {
        val requestKey = extractField(
            body = body,
            prefix = KEY_PREFIX
        )

        if (requestKey.isNullOrBlank()) {
            Log.w(
                LOG_TAG,
                "SOS SMS has no request key; ignoring"
            )
            return
        }

        if (!markKeyAsSeen(context, requestKey)) {
            Log.d(
                LOG_TAG,
                "SOS SMS already handled: $requestKey"
            )
            return
        }

        val patientName =
            extractField(
                body = body,
                prefix = NAME_PREFIX
            )
                ?.replace("|", "")
                ?.trim()
                ?.ifBlank { "A patient" }
                ?: "A patient"

        val location =
            extractField(
                body = body,
                prefix = LOCATION_PREFIX
            )

        val payload = JSONObject().apply {
            put(
                "sosKey",
                requestKey
            )
            put(
                "patientName",
                patientName
            )
            put(
                "via",
                "sms"
            )

            if (!location.isNullOrBlank()) {
                put(
                    "location",
                    location
                )
            }
        }.toString()

        val message =
            "Urgent! Urgent! $patientName has sent an " +
                    "emergency SOS by SMS. " +
                    "Please respond immediately."

        startCaretakerAlarm(
            context = context,
            message = message,
            payload = payload
        )
    }

    /**
     * Extracts a field until the next "|" separator.
     *
     * Example:
     * MAR-SOS k:abc123 | n:Elijah | g:5.345,-0.625
     */
    private fun extractField(
        body: String,
        prefix: String
    ): String? {
        val start = body.indexOf(prefix)

        if (start < 0) {
            return null
        }

        val valueStart = start + prefix.length

        if (valueStart >= body.length) {
            return null
        }

        val separator = body.indexOf(
            '|',
            valueStart
        )

        val valueEnd =
            if (separator >= 0) {
                separator
            } else {
                body.length
            }

        return body
            .substring(valueStart, valueEnd)
            .trim()
            .takeIf { it.isNotEmpty() }
    }

    /**
     * Returns false when this SOS request key has already caused an alarm.
     *
     * This prevents duplicate alarms when the same SOS arrives through both:
     *
     * - Supabase Realtime
     * - SMS fallback
     */
    private fun markKeyAsSeen(
        context: Context,
        requestKey: String
    ): Boolean {
        val preferences =
            context.getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE
            )

        val existingKeys =
            HashSet(
                preferences.getStringSet(
                    SEEN_KEYS_NAME,
                    emptySet()
                ) ?: emptySet()
            )

        if (existingKeys.contains(requestKey)) {
            return false
        }

        existingKeys.add(requestKey)

        /*
         * Keep the set bounded so it cannot grow forever.
         *
         * This simple cleanup is sufficient for the fallback path. The
         * current request remains stored after cleanup.
         */
        if (existingKeys.size > MAX_STORED_KEYS) {
            existingKeys.clear()
            existingKeys.add(requestKey)
        }

        preferences.edit()
            .putStringSet(
                SEEN_KEYS_NAME,
                existingKeys
            )
            .apply()

        return true
    }

    private fun startCaretakerAlarm(
        context: Context,
        message: String,
        payload: String
    ) {
        val serviceIntent =
            Intent(
                context,
                TtsSpeakService::class.java
            ).apply {
                action =
                    TtsSpeakService.ACTION_START

                putExtra(
                    "message",
                    message
                )

                putExtra(
                    "payload",
                    payload
                )

                putExtra(
                    "alertMode",
                    TtsSpeakService.MODE_CARETAKER_SOS
                )

                putExtra(
                    "soundResource",
                    "caretaker_sos"
                )

                putExtra(
                    "loopSound",
                    true
                )

                putExtra(
                    "launchScanner",
                    false
                )

                putExtra(
                    "vibrationMode",
                    TtsSpeakService.VIBRATION_CONTINUOUS
                )

                putExtra(
                    "ttsRepeatCount",
                    3
                )
            }

        try {
            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.O
            ) {
                context.startForegroundService(
                    serviceIntent
                )
            } else {
                @Suppress("DEPRECATION")
                context.startService(
                    serviceIntent
                )
            }

            Log.d(
                LOG_TAG,
                "🔊 SMS fallback started caretaker SOS alarm"
            )
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "❌ Could not start SOS alarm from SMS",
                error
            )
        }
    }
}