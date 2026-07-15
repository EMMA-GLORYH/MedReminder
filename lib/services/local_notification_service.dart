// lib/services/local_notification_service.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../home/patients/medication_reminder_scanner_screen.dart';
import '../main.dart';
import 'dose_log_service.dart';
import 'medication_tts_service.dart';
import 'schedule_service.dart';

// Channel used by MainActivity to instruct Flutter to open the reminder screen.
const MethodChannel _scannerRouteChannel = MethodChannel(
  'medication_scanner_route',
);

class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance =
  LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Versioned channels are used because Android notification-channel
  // sound and vibration settings cannot be changed after creation.
  //
  // Native TtsSpeakService owns audio and vibration. These channels are
  // visual notification channels only, preventing duplicate sound.
  static const String _reminderChannelId =
      'medication_prior_visual_v2';

  static const String _urgentChannelId =
      'medication_due_visual_v2';

  // Notification vibration is disabled because native TtsSpeakService
  // already handles the requested patterns.
  static final Int64List _noVibration = Int64List.fromList(
    const <int>[0],
  );

  // Stable step IDs.
  static const int _dueNotificationStep = 0;
  static const int _legacyEscalationStep1 = 1;
  static const int _legacyEscalationStep2 = 2;
  static const int _priorNativeAlarmStep = 98;
  static const int _priorNotificationStep = 99;
  static const int _dueNativeAlarmStep = 100;

  static const Duration _priorDuration = Duration(
    minutes: 10,
  );

  static const String _payloadPreferencePrefix =
      'cached_dose_payload_';

  // ══════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ══════════════════════════════════════════════════════════════

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    // This preserves your current working timezone configuration.
    tz.setLocalLocation(tz.getLocation('UTC'));

    const androidInitialization =
    AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosInitialization = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInitialization,
        iOS: iosInitialization,
      ),
      onDidReceiveNotificationResponse:
      _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse:
      _onNotificationTapped,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Visual due-dose channel.
      //
      // Sound and vibration are disabled here because the native
      // TtsSpeakService provides the TTS, MP3, and vibration.
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _urgentChannelId,
          'Medication Due Alerts',
          description:
          'Visual notification when a medication dose is due',
          importance: Importance.max,
          playSound: false,
          enableVibration: false,
          enableLights: true,
          ledColor: Color(0xFF00BFA5),
          showBadge: true,
          bypassDnd: true,
        ),
      );

      // Visual prior-reminder channel.
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannelId,
          'Upcoming Medication Reminders',
          description:
          'Visual notification ten minutes before a dose',
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
          enableLights: true,
          ledColor: Color(0xFF00BFA5),
          showBadge: true,
          bypassDnd: true,
        ),
      );

      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    }

    // Native alarm auto-launch route.
    _scannerRouteChannel.setMethodCallHandler(
          (call) async {
        if (call.method != 'openScanner') return;

        final payload = call.arguments as String?;

        if (payload == null || payload.trim().isEmpty) {
          return;
        }

        await _openScannerFromPayload(payload);
      },
    );

    _initialized = true;

    debugPrint('✅ LocalNotificationService initialized');
  }

  // ══════════════════════════════════════════════════════════════
  // SCHEDULE A DOSE
  // ══════════════════════════════════════════════════════════════

  Future<void> scheduleForDose({
    required String scheduleId,
    required String medicationId,
    required String medicationName,
    required String dosageDisplay,
    required DateTime scheduledFor,
    String? pillImageUrl,
    int escalationStep1Mins = 10,
    int escalationStep2Mins = 20,
  }) async {
    if (!_initialized) {
      await init();
    }

    final now = DateTime.now();

    if (!scheduledFor.isAfter(now)) {
      debugPrint(
        'ℹ️ Skipping dose notification because the time '
            'has already passed: $scheduledFor',
      );
      return;
    }

    final priorTime = scheduledFor.subtract(
      _priorDuration,
    );

    final priorNotificationId = _generateId(
      scheduleId,
      scheduledFor,
      _priorNotificationStep,
    );

    final dueNotificationId = _generateId(
      scheduleId,
      scheduledFor,
      _dueNotificationStep,
    );

    final priorNativeAlarmId = _generateId(
      scheduleId,
      scheduledFor,
      _priorNativeAlarmStep,
    );

    final dueNativeAlarmId = _generateId(
      scheduleId,
      scheduledFor,
      _dueNativeAlarmStep,
    );

    final basePayload = <String, dynamic>{
      'scheduleId': scheduleId,
      'medicationId': medicationId,
      'scheduledFor': scheduledFor.toIso8601String(),
      'scheduledForMillis':
      scheduledFor.millisecondsSinceEpoch,
      'medicationName': medicationName,
      'dosageDisplay': dosageDisplay,
      'pillImageUrl': pillImageUrl ?? '',
      'priorTtsAlarmId': priorNativeAlarmId,
      'ttsAlarmId': dueNativeAlarmId,
    };

    final priorPayload = jsonEncode({
      ...basePayload,
      'alertType': 'prior_reminder',
    });

    final duePayload = jsonEncode({
      ...basePayload,
      'alertType': 'medication_due',
    });

    // Store the due payload so scanner actions remain available after
    // process recreation and offline use.
    await _cachePayload(
      scheduleId: scheduleId,
      scheduledFor: scheduledFor,
      payload: duePayload,
    );

    // ──────────────────────────────────────────────────────────
    // 1. TEN-MINUTE PRIOR REMINDER
    //
    // Native flow:
    // - TTS reads three times
    // - five vibration pulses
    // - prior_reminder.mp3 plays once
    // - scanner does not open
    // ──────────────────────────────────────────────────────────

    if (priorTime.isAfter(now)) {
      await _scheduleVisualNotification(
        id: priorNotificationId,
        title: '⏰ Upcoming: $medicationName',
        body:
        'Get ready — $dosageDisplay is due in 10 minutes',
        time: priorTime,
        payload: priorPayload,
        isUrgent: false,
        showDoseActions: false,
      );

      await MedicationTtsService.instance
          .schedulePriorReminder(
        alarmId: priorNativeAlarmId,
        startAt: priorTime,
        medicationName: medicationName,
        dosageDisplay: dosageDisplay,
        minutesBefore: 10,
      );

      debugPrint(
        '⏰ Prior reminder scheduled for $priorTime '
            '(native ID: $priorNativeAlarmId)',
      );
    } else {
      debugPrint(
        'ℹ️ Prior reminder skipped because $priorTime '
            'has already passed',
      );
    }

    // ──────────────────────────────────────────────────────────
    // 2. EXACT DUE-TIME ALERT
    //
    // Native flow:
    // - TTS reads three times
    // - continuous vibration
    // - alarm.mp3 loops
    // - scanner/confirmation screen auto-opens
    // ──────────────────────────────────────────────────────────

    await _scheduleVisualNotification(
      id: dueNotificationId,
      title: '💊 Time to Take Medicine',
      body: '$medicationName · $dosageDisplay',
      time: scheduledFor,
      payload: duePayload,
      isUrgent: true,
      showDoseActions: true,
    );

    await MedicationTtsService.instance.scheduleAutoOpen(
      alarmId: dueNativeAlarmId,
      startAt: scheduledFor,
      message:
      'It is time to take $medicationName. '
          'Dosage: $dosageDisplay. '
          'Please confirm your medicine now.',
      payload: duePayload,
    );

    debugPrint(
      '🚨 Due alert scheduled for $scheduledFor '
          '(native ID: $dueNativeAlarmId)',
    );

    // Retained only for API compatibility. The new audio flow does not
    // require separate escalation alarms because alarm.mp3 continues
    // until the reminder is stopped.
    if (escalationStep1Mins < 0 ||
        escalationStep2Mins < 0) {
      debugPrint(
        '⚠️ Invalid escalation values were supplied',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // VISUAL NOTIFICATION SCHEDULER
  // ══════════════════════════════════════════════════════════════

  Future<void> _scheduleVisualNotification({
    required int id,
    required String title,
    required String body,
    required DateTime time,
    required String payload,
    required bool isUrgent,
    required bool showDoseActions,
  }) async {
    final now = DateTime.now();

    if (!time.isAfter(now)) {
      debugPrint(
        'ℹ️ Visual notification #$id skipped because '
            '$time is not in the future',
      );
      return;
    }

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        isUrgent
            ? _urgentChannelId
            : _reminderChannelId,
        isUrgent
            ? 'Medication Due Alerts'
            : 'Upcoming Medication Reminders',
        channelDescription: isUrgent
            ? 'Visual notification when a medication dose is due'
            : 'Visual notification ten minutes before a dose',
        importance: isUrgent
            ? Importance.max
            : Importance.high,
        priority: isUrgent
            ? Priority.max
            : Priority.high,

        // Audio/vibration are provided by native TtsSpeakService.
        playSound: false,
        enableVibration: false,
        vibrationPattern: _noVibration,

        category: isUrgent
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.reminder,

        enableLights: true,
        ledColor: const Color(0xFF00BFA5),
        ledOnMs: 500,
        ledOffMs: 500,

        ticker: isUrgent
            ? 'Medication due'
            : 'Upcoming medication',

        styleInformation: BigTextStyleInformation(
          '$title\n$body',
          htmlFormatBigText: false,
          contentTitle: title,
        ),

        actions: showDoseActions
            ? const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'MARK_TAKEN',
            '✅ Mark as Taken',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'OPEN_SCANNER',
            '💊 Confirm Medicine',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ]
            : const <AndroidNotificationAction>[],

        // Native TtsSpeakService handles automatic foreground opening.
        // Keeping this false avoids duplicate scanner routes.
        fullScreenIntent: false,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: false,
        presentBadge: true,
        interruptionLevel:
        InterruptionLevel.timeSensitive,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(
          time,
          tz.local,
        ),
        notificationDetails: notificationDetails,
        androidScheduleMode:
        AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );

      debugPrint(
        '🔔 Visual notification #$id scheduled at $time',
      );
    } catch (error, stack) {
      debugPrint(
        '⚠️ Visual notification #$id failed: $error',
      );
      debugPrint('$stack');

      // Do not rethrow. The native alarm remains the critical alert path.
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PAYLOAD CACHE
  // ══════════════════════════════════════════════════════════════

  String _cacheKey(
      String scheduleId,
      DateTime scheduledFor,
      ) {
    return '$_payloadPreferencePrefix'
        '${scheduleId}_'
        '${scheduledFor.millisecondsSinceEpoch}';
  }

  Future<void> _cachePayload({
    required String scheduleId,
    required DateTime scheduledFor,
    required String payload,
  }) async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      await preferences.setString(
        _cacheKey(scheduleId, scheduledFor),
        payload,
      );
    } catch (error) {
      debugPrint(
        '⚠️ Could not cache dose payload: $error',
      );
    }
  }

  Future<void> _removeCachedPayload({
    required String scheduleId,
    required DateTime scheduledFor,
  }) async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      await preferences.remove(
        _cacheKey(scheduleId, scheduledFor),
      );
    } catch (_) {}
  }

  Future<void> _removeSchedulePayloads(
      String scheduleId,
      ) async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      final prefix =
          '$_payloadPreferencePrefix${scheduleId}_';

      final keys = preferences
          .getKeys()
          .where((key) => key.startsWith(prefix))
          .toList();

      for (final key in keys) {
        await preferences.remove(key);
      }
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════
  // CANCEL A SPECIFIC DOSE
  // ══════════════════════════════════════════════════════════════

  Future<void> cancelDose({
    required String scheduleId,
    required DateTime scheduledFor,
  }) async {
    final notificationIds = <int>[
      _generateId(
        scheduleId,
        scheduledFor,
        _dueNotificationStep,
      ),
      _generateId(
        scheduleId,
        scheduledFor,
        _legacyEscalationStep1,
      ),
      _generateId(
        scheduleId,
        scheduledFor,
        _legacyEscalationStep2,
      ),
      _generateId(
        scheduleId,
        scheduledFor,
        _priorNotificationStep,
      ),
    ];

    for (final id in notificationIds) {
      try {
        await _plugin.cancel(id: id);
      } catch (error) {
        debugPrint(
          '⚠️ Could not cancel notification #$id: $error',
        );
      }
    }

    final priorNativeAlarmId = _generateId(
      scheduleId,
      scheduledFor,
      _priorNativeAlarmStep,
    );

    final dueNativeAlarmId = _generateId(
      scheduleId,
      scheduledFor,
      _dueNativeAlarmStep,
    );

    await MedicationTtsService.instance
        .cancelPriorReminder(priorNativeAlarmId);

    await MedicationTtsService.instance
        .cancelAutoOpen(dueNativeAlarmId);

    // Stop any alert currently playing for this dose.
    await MedicationTtsService.instance.stop();

    await _removeCachedPayload(
      scheduleId: scheduleId,
      scheduledFor: scheduledFor,
    );

    debugPrint(
      '🗑️ Cancelled all alerts for dose '
          '$scheduleId at $scheduledFor',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // CANCEL ALL ALERTS FOR A SCHEDULE
  // ══════════════════════════════════════════════════════════════

  Future<void> cancelSchedule(String scheduleId) async {
    final pending =
    await _plugin.pendingNotificationRequests();

    final nativeAlarmIds = <int>{};

    for (final notification in pending) {
      final rawPayload = notification.payload;

      if (rawPayload == null ||
          !rawPayload.contains(scheduleId)) {
        continue;
      }

      try {
        final data = jsonDecode(rawPayload)
        as Map<String, dynamic>;

        final rawMillis =
        data['scheduledForMillis'];

        final scheduledFor = rawMillis is num
            ? DateTime.fromMillisecondsSinceEpoch(
          rawMillis.toInt(),
        )
            : DateTime.parse(
          data['scheduledFor'] as String,
        );

        nativeAlarmIds.add(
          _generateId(
            scheduleId,
            scheduledFor,
            _priorNativeAlarmStep,
          ),
        );

        nativeAlarmIds.add(
          _generateId(
            scheduleId,
            scheduledFor,
            _dueNativeAlarmStep,
          ),
        );
      } catch (error) {
        debugPrint(
          '⚠️ Could not parse notification payload '
              'while cancelling schedule: $error',
        );
      }

      try {
        await _plugin.cancel(id: notification.id);
      } catch (_) {}
    }

    for (final alarmId in nativeAlarmIds) {
      await MedicationTtsService.instance
          .cancelAutoOpen(alarmId);
    }

    await _removeSchedulePayloads(scheduleId);

    debugPrint(
      '🗑️ Cancelled schedule alerts: $scheduleId',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // CANCEL EVERYTHING
  // ══════════════════════════════════════════════════════════════

  Future<void> cancelAll() async {
    final pending =
    await _plugin.pendingNotificationRequests();

    final nativeAlarmIds = <int>{};

    for (final notification in pending) {
      final rawPayload = notification.payload;

      if (rawPayload == null) continue;

      try {
        final data = jsonDecode(rawPayload)
        as Map<String, dynamic>;

        final scheduleId =
        data['scheduleId']?.toString();

        if (scheduleId == null ||
            scheduleId.isEmpty) {
          continue;
        }

        final rawMillis =
        data['scheduledForMillis'];

        final scheduledFor = rawMillis is num
            ? DateTime.fromMillisecondsSinceEpoch(
          rawMillis.toInt(),
        )
            : DateTime.parse(
          data['scheduledFor'] as String,
        );

        nativeAlarmIds.add(
          _generateId(
            scheduleId,
            scheduledFor,
            _priorNativeAlarmStep,
          ),
        );

        nativeAlarmIds.add(
          _generateId(
            scheduleId,
            scheduledFor,
            _dueNativeAlarmStep,
          ),
        );
      } catch (_) {}
    }

    await _plugin.cancelAll();

    for (final alarmId in nativeAlarmIds) {
      await MedicationTtsService.instance
          .cancelAutoOpen(alarmId);
    }

    await MedicationTtsService.instance.stop();

    debugPrint('🗑️ All medication alerts cancelled');
  }

  // ══════════════════════════════════════════════════════════════
  // ID GENERATOR
  // ══════════════════════════════════════════════════════════════

  int _generateId(
      String scheduleId,
      DateTime time,
      int step,
      ) {
    return '${scheduleId}_'
        '${time.millisecondsSinceEpoch}_'
        '$step'
        .hashCode
        .abs() %
        2147483647;
  }
}

// ══════════════════════════════════════════════════════════════
// OPEN REMINDER SCREEN FROM PAYLOAD
// ══════════════════════════════════════════════════════════════

Future<void> _openScannerFromPayload(
    String rawPayload,
    ) async {
  try {
    final data = jsonDecode(rawPayload)
    as Map<String, dynamic>;

    final alertType =
        data['alertType']?.toString() ?? 'medication_due';

    // A ten-minute prior notification must not open the due screen.
    if (alertType == 'prior_reminder') {
      debugPrint(
        'ℹ️ Prior reminder tapped; scanner will not open',
      );
      return;
    }

    final rawDosage =
        data['dosageDisplay']?.toString() ?? '';

    final dosageParts = rawDosage
        .trim()
        .split(RegExp(r'\s+'));

    final double dosageAmount = dosageParts.isNotEmpty
        ? (double.tryParse(dosageParts.first) ?? 1.0)
        : 1.0;

    final dosageUnit = dosageParts.length > 1
        ? dosageParts.sublist(1).join(' ')
        : 'dose';

    final imageUrl =
    data['pillImageUrl']?.toString();

    final dose = TodayDose(
      scheduleId:
      data['scheduleId'] as String,
      medicationId:
      data['medicationId'] as String,
      medicationName:
      data['medicationName']?.toString() ??
          'Medication',
      genericName:
      data['medicationName']?.toString() ??
          'Medication',
      dosageAmount: dosageAmount,
      dosageUnit: dosageUnit,
      scheduledTime: DateTime.parse(
        data['scheduledFor'] as String,
      ),
      pillImageUrl: imageUrl != null &&
          imageUrl.trim().isNotEmpty
          ? imageUrl
          : null,
    );

    final navigator = navigatorKey.currentState;

    if (navigator == null) {
      debugPrint(
        '⚠️ Navigator is not ready to open reminder screen',
      );
      return;
    }

    await navigator.push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) =>
            MedicationReminderScannerScreen(
              dose: dose,
            ),
      ),
    );
  } catch (error, stack) {
    debugPrint(
      '❌ Failed to open reminder screen from payload: '
          '$error',
    );
    debugPrint('$stack');
  }
}

// ══════════════════════════════════════════════════════════════
// NOTIFICATION TAP / ACTION HANDLER
// ══════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
Future<void> _onNotificationTapped(
    NotificationResponse response,
    ) async {
  final rawPayload = response.payload;

  if (rawPayload == null ||
      rawPayload.trim().isEmpty) {
    return;
  }

  try {
    final data = jsonDecode(rawPayload)
    as Map<String, dynamic>;

    final alertType =
        data['alertType']?.toString() ?? 'medication_due';

    // Prior notifications are informational only.
    if (alertType == 'prior_reminder') {
      debugPrint(
        'ℹ️ Prior reminder notification opened',
      );
      return;
    }

    if (response.actionId == 'MARK_TAKEN') {
      await DoseLogService.instance.markAsTaken(
        scheduleId:
        data['scheduleId'] as String,
        medicationId:
        data['medicationId'] as String,
        scheduledFor: DateTime.parse(
          data['scheduledFor'] as String,
        ),
      );
      return;
    }

    // Notification body or Confirm Medicine action.
    await _openScannerFromPayload(rawPayload);
  } catch (error, stack) {
    debugPrint(
      '❌ Notification response failed: $error',
    );
    debugPrint('$stack');
  }
}