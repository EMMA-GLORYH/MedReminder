// lib/services/local_notification_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mar/main.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'dose_log_service.dart';
import 'medication_tts_service.dart';
import 'package:flutter/services.dart';

import '../home/patients/medication_reminder_scanner_screen.dart';
import '../services/schedule_service.dart';

// Global navigator key to open screens from background/notification callbacks

class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _reminderChannelId = 'medication_reminders';
  static const _urgentChannelId = 'medication_urgent';

  static const MethodChannel _ttsChannel = MethodChannel('medication_tts_background');

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

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannelId,
          'Reminders',
          importance: Importance.max,
          playSound: false,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _urgentChannelId,
          'Urgent Reminders',
          importance: Importance.max,
          playSound: false,
        ),
      );

      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    }

    _initialized = true;
  }

  Future<void> scheduleForDose({
    required String scheduleId,
    required String medicationId,
    required String medicationName,
    required String dosageDisplay,
    required DateTime scheduledFor,
    int escalationStep1Mins = 10,
    int escalationStep2Mins = 20,
  }) async {
    if (!_initialized) await init();
    if (scheduledFor.isBefore(DateTime.now())) return;

    final payload = jsonEncode({
      'scheduleId': scheduleId,
      'medicationId': medicationId,
      'scheduledFor': scheduledFor.toIso8601String(),
      'medicationName': medicationName,
      'dosageDisplay': dosageDisplay,
    });

    final step0Time = scheduledFor;
    final step0AlarmId = _generateId(scheduleId, step0Time, 0);

    await _schedule(
      id: step0AlarmId,
      title: 'Medication Reminder',
      body: medicationName,
      time: step0Time,
      payload: payload,
      isUrgent: false,
    );

    await _ttsChannel.invokeMethod('scheduleStart', {
      'alarmId': step0AlarmId,
      'startAtMillis': step0Time.millisecondsSinceEpoch,
      'message': _buildTtsMessage(medicationName, dosageDisplay, step0Time),
    });

    // Escalation 1 & 2 (silent notifications + TTS)
    for (int step = 1; step <= 2; step++) {
      final delay = step == 1 ? escalationStep1Mins : escalationStep2Mins;
      final time = scheduledFor.add(Duration(minutes: delay));
      final alarmId = _generateId(scheduleId, time, step);

      await _schedule(
        id: alarmId,
        title: step == 1 ? 'Missed Dose Reminder' : 'Action Required',
        body: medicationName,
        time: time,
        payload: payload,
        isUrgent: true,
      );

      await _ttsChannel.invokeMethod('scheduleStart', {
        'alarmId': alarmId,
        'startAtMillis': time.millisecondsSinceEpoch,
        'message': _buildTtsMessage(medicationName, dosageDisplay, time),
      });
    }
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime time,
    required String payload,
    required bool isUrgent,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        isUrgent ? _urgentChannelId : _reminderChannelId,
        'Meds',
        importance: Importance.max,
        priority: Priority.high,
        playSound: false,
        sound: null,
        actions: const [
          AndroidNotificationAction(
            'MARK_TAKEN',
            '✅ Mark Taken',
            showsUserInterface: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(time, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      debugPrint('❌ schedule error: $e');
    }
  }

  Future<void> cancelDose({
    required String scheduleId,
    required DateTime scheduledFor,
    int escalationStep1Mins = 10,
    int escalationStep2Mins = 20,
  }) async {
    final step0AlarmId = _generateId(scheduleId, scheduledFor, 0);
    final step1Time = scheduledFor.add(Duration(minutes: escalationStep1Mins));
    final step1AlarmId = _generateId(scheduleId, step1Time, 1);
    final step2Time = scheduledFor.add(Duration(minutes: escalationStep2Mins));
    final step2AlarmId = _generateId(scheduleId, step2Time, 2);

    await _plugin.cancel(id: step0AlarmId);
    await _plugin.cancel(id: step1AlarmId);
    await _plugin.cancel(id: step2AlarmId);

    try {
      await _ttsChannel.invokeMethod('cancelAlarm', {'alarmId': step0AlarmId});
      await _ttsChannel.invokeMethod('cancelAlarm', {'alarmId': step1AlarmId});
      await _ttsChannel.invokeMethod('cancelAlarm', {'alarmId': step2AlarmId});
    } catch (_) {}

    try {
      await MedicationTtsService.instance.stop();
    } catch (_) {}
  }

  Future<void> cancelSchedule(String scheduleId) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.payload != null && n.payload!.contains(scheduleId)) {
        await _plugin.cancel(id: n.id);
      }
    }
  }

  Future<void> cancelAll() async => await _plugin.cancelAll();

  int _generateId(String scheduleId, DateTime time, int step) {
    return '${scheduleId}_${time.millisecondsSinceEpoch}_$step'.hashCode.abs() % 2147483647;
  }

  String _buildTtsMessage(String medicationName, String dosageDisplay, DateTime scheduledFor) {
    final local = scheduledFor.toLocal();
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final p = h >= 12 ? 'PM' : 'AM';
    final dh = (h == 0) ? 12 : (h > 12 ? h - 12 : h);

    return 'It is time to take $medicationName. Dosage: $dosageDisplay. Scheduled for $dh:$m $p.';
  }
}

// ── Notification Tap/Action Logic ──
@pragma('vm:entry-point')
Future<void> _onNotificationTapped(NotificationResponse response) async {
  if (response.payload == null) return;

  final data = jsonDecode(response.payload!);

  final scheduleId = data['scheduleId'] as String;
  final medicationId = data['medicationId'] as String;
  final scheduledFor = DateTime.parse(data['scheduledFor'] as String);
  final medicationName = data['medicationName'] as String;
  final dosageDisplay = data['dosageDisplay'] as String;

  // If user pressed the action button
  if (response.actionId == 'MARK_TAKEN') {
    await DoseLogService.instance.markAsTaken(
      scheduleId: scheduleId,
      medicationId: medicationId,
      scheduledFor: scheduledFor,
    );
    return;
  }

  // Otherwise, open the full-screen scanner with TTS already running
  final dose = TodayDose(
    scheduleId: scheduleId,
    medicationId: medicationId,
    medicationName: medicationName,
    genericName: medicationName,
    dosageAmount: double.tryParse(dosageDisplay.split(' ').first) ?? 0.0,
    dosageUnit: dosageDisplay.split(' ').last,
    scheduledTime: scheduledFor,
    pillImageUrl: null, // Will be loaded in scanner if needed
  );

  navigatorKey.currentState?.push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MedicationReminderScannerScreen(dose: dose),
    ),
  );
}