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

import '../main.dart';
import '../home/patients/medication_reminder_scanner_screen.dart';
import 'dose_log_service.dart';
import 'medication_tts_service.dart';
import 'schedule_service.dart';

// Channel that MainActivity uses to tell Flutter to open the scanner screen
// (used by the native alarm auto-launch path — see MedicationTtsService).
const _scannerRouteChannel = MethodChannel('medication_scanner_route');

class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Two channels: one for prior alerts, one for full-screen alarm
  static const _reminderChannelId = 'medication_reminders';
  static const _urgentChannelId   = 'medication_urgent';

  // Heavy repeating vibration pattern (on/off in ms)
  static final Int64List _heavyVibration = Int64List.fromList([
    0,
    800, 300,
    800, 300,
    800, 300,
    1200, 400,
    1200, 400,
    1200,
  ]);

  static final Int64List _priorVibration = Int64List.fromList([
    0, 400, 200, 400, 200, 400,
  ]);

  // ──────────────────────────────────────────────────────────
  // INIT
  // ──────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
    );

    // IMPORTANT: this must be a *call* (with the trailing `()`), not a
    // reference to the method. Omitting the `()` assigns the generic
    // function itself (type `Function`) instead of invoking it — which is
    // exactly what causes "createNotificationChannel isn't defined for
    // type 'Function'" style errors below.
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
    _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Urgent channel — full-screen, alarm category, bypasses DND
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _urgentChannelId,
          'Medication Alarms',
          description: 'Full-screen alarm when a dose is due',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm'),
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFF00BFA5),
          showBadge: true,
          bypassDnd: true,
        ),
      );

      // Prior-alert channel — high priority, gentle
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannelId,
          'Medication Reminders',
          description: '10-minute prior alert',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    }

    // Listen for MainActivity telling us to open the scanner screen
    // (fired natively even if the app was fully killed).
    _scannerRouteChannel.setMethodCallHandler((call) async {
      if (call.method == 'openScanner') {
        final payload = call.arguments as String?;
        if (payload != null) {
          await _openScannerFromPayload(payload);
        }
      }
    });

    _initialized = true;
  }

  // ──────────────────────────────────────────────────────────
  // SCHEDULE A DOSE'S NOTIFICATIONS
  // ──────────────────────────────────────────────────────────
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
    if (!_initialized) await init();
    if (scheduledFor.isBefore(DateTime.now())) return;

    // Stable id for the native "auto-open" alarm — computed once and reused
    // everywhere (payload, scheduling, cancelling, boot rescheduling).
    final autoOpenId = _generateId(scheduleId, scheduledFor, 100);

    final payload = jsonEncode({
      'scheduleId':         scheduleId,
      'medicationId':       medicationId,
      'scheduledFor':       scheduledFor.toIso8601String(),
      'scheduledForMillis': scheduledFor.millisecondsSinceEpoch,
      'medicationName':     medicationName,
      'dosageDisplay':      dosageDisplay,
      'pillImageUrl':       pillImageUrl ?? '',
      'ttsAlarmId':         autoOpenId,
    });

    // Cache payload locally so actions work offline / app closed / after reboot
    await _cachePayload(scheduleId, payload);

    // 1. Prior alert — 10 mins before
    final priorTime = scheduledFor.subtract(const Duration(minutes: 10));
    if (priorTime.isAfter(DateTime.now())) {
      await _schedule(
        id:        _generateId(scheduleId, scheduledFor, 99),
        title:     '⏰ Upcoming: $medicationName',
        body:      'Get ready — dose due in 10 minutes ($dosageDisplay)',
        time:      priorTime,
        payload:   payload,
        isUrgent:  false,
        vibration: _priorVibration,
      );
    }

    // 2. Due now — full-screen alarm
    await _schedule(
      id:           _generateId(scheduleId, scheduledFor, 0),
      title:        '💊 Time to Take Medicine',
      body:         '$medicationName · $dosageDisplay',
      time:         scheduledFor,
      payload:      payload,
      isUrgent:     true,
      vibration:    _heavyVibration,
      isFullScreen: true,
    );

    // 3. Native alarm — survives app being killed, auto-opens the scanner
    //    over the lock screen without requiring the user to tap anything.
    await MedicationTtsService.instance.scheduleAutoOpen(
      alarmId: autoOpenId,
      startAt: scheduledFor,
      message: 'It is time to take $medicationName. '
          'Dosage: $dosageDisplay. Please scan the medicine now.',
      payload: payload,
    );
  }

  // ──────────────────────────────────────────────────────────
  // INTERNAL SCHEDULER
  // ──────────────────────────────────────────────────────────
  Future<void> _schedule({
    required int    id,
    required String title,
    required String body,
    required DateTime time,
    required String payload,
    required bool   isUrgent,
    Int64List?      vibration,
    bool            isFullScreen = false,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        isUrgent ? _urgentChannelId : _reminderChannelId,
        isUrgent ? 'Medication Alarms' : 'Medication Reminders',
        importance:           Importance.max,
        priority:             Priority.max,
        fullScreenIntent:     isFullScreen,
        category:             AndroidNotificationCategory.alarm,
        vibrationPattern:     vibration,
        playSound:            true,
        sound:                isUrgent
            ? const RawResourceAndroidNotificationSound('alarm')
            : null,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableLights:         true,
        ledColor:             const Color(0xFF00BFA5),
        ledOnMs:              500,
        ledOffMs:             500,
        ticker:               'Medication reminder',
        styleInformation: BigTextStyleInformation(
          '$title\n$body',
          htmlFormatBigText: false,
          contentTitle:      title,
        ),
        actions: [
          const AndroidNotificationAction(
            'MARK_TAKEN',
            '✅ Mark as Taken',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            'OPEN_SCANNER',
            '📷 Open Scanner',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert:      true,
        presentSound:      true,
        presentBadge:      true,
        interruptionLevel: InterruptionLevel.critical,
      ),
    );

    await _plugin.zonedSchedule(
      id:                  id,
      title:               title,
      body:                body,
      scheduledDate:       tz.TZDateTime.from(time, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload:             payload,
    );

    debugPrint('🔔 Scheduled notification #$id at $time');
  }

  // ──────────────────────────────────────────────────────────
  // PAYLOAD CACHE  (SharedPreferences — survives app close / reboot)
  // ──────────────────────────────────────────────────────────
  static const _prefKey = 'cached_dose_payload_';

  Future<void> _cachePayload(String scheduleId, String payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefKey$scheduleId', payload);
    } catch (e) {
      debugPrint('⚠️ Could not cache payload: $e');
    }
  }

  Future<String?> _getCachedPayload(String scheduleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_prefKey$scheduleId');
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeCachedPayload(String scheduleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefKey$scheduleId');
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────
  // CANCEL HELPERS
  // ──────────────────────────────────────────────────────────
  Future<void> cancelDose({
    required String scheduleId,
    required DateTime scheduledFor,
  }) async {
    for (int i = 0; i <= 2; i++) {
      await _plugin.cancel(id: _generateId(scheduleId, scheduledFor, i));
    }
    await _plugin.cancel(id: _generateId(scheduleId, scheduledFor, 99));
    await MedicationTtsService.instance
        .cancelAutoOpen(_generateId(scheduleId, scheduledFor, 100));
    await _removeCachedPayload(scheduleId);
  }

  Future<void> cancelSchedule(String scheduleId) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.payload != null && n.payload!.contains(scheduleId)) {
        await _plugin.cancel(id: n.id);
      }
    }
    await _removeCachedPayload(scheduleId);
  }

  // ──────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────
  int _generateId(String scheduleId, DateTime time, int step) =>
      '${scheduleId}_${time.millisecondsSinceEpoch}_$step'
          .hashCode
          .abs() %
          2147483647;
}

// ── Open scanner from JSON payload (shared by tap + native auto-launch) ──
Future<void> _openScannerFromPayload(String rawPayload) async {
  try {
    final data       = jsonDecode(rawPayload) as Map<String, dynamic>;
    final rawDisplay = data['dosageDisplay'] as String? ?? '';
    final parts      = rawDisplay.split(' ');
    final amount     = parts.isNotEmpty ? (double.tryParse(parts[0]) ?? 1.0) : 1.0;
    final unit       = parts.length > 1 ? parts[1] : 'dose';

    final dose = TodayDose(
      scheduleId:     data['scheduleId']    as String,
      medicationId:   data['medicationId']  as String,
      medicationName: data['medicationName'] as String,
      genericName:    data['medicationName'] as String,
      dosageAmount:   amount,
      dosageUnit:     unit,
      scheduledTime:  DateTime.parse(data['scheduledFor'] as String),
      pillImageUrl:   (data['pillImageUrl'] as String?)?.isNotEmpty == true
          ? data['pillImageUrl'] as String
          : null,
    );

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MedicationReminderScannerScreen(dose: dose),
      ),
    );
  } catch (e) {
    debugPrint('❌ Failed to open scanner from payload: $e');
  }
}

// ── Notification Tap / Action Handler ──────────────────────
@pragma('vm:entry-point')
Future<void> _onNotificationTapped(NotificationResponse response) async {
  if (response.payload == null) return;

  final data = jsonDecode(response.payload!) as Map<String, dynamic>;

  // Quick-action: mark taken without opening screen
  if (response.actionId == 'MARK_TAKEN') {
    await DoseLogService.instance.markAsTaken(
      scheduleId:   data['scheduleId']   as String,
      medicationId: data['medicationId'] as String,
      scheduledFor: DateTime.parse(data['scheduledFor'] as String),
    );
    return;
  }

  // Tap on notification body OR "Open Scanner" action → open scanner screen
  await _openScannerFromPayload(response.payload!);
}