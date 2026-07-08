// lib/services/local_notification_service.dart

import 'dart:convert';
import 'dart:typed_data'; // ✅ FIXED: For Int64List
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../main.dart';
import '../home/patients/medication_reminder_scanner_screen.dart';
import 'dose_log_service.dart';
import 'medication_tts_service.dart';
import 'schedule_service.dart';

class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _reminderChannelId = 'medication_reminders';
  static const _urgentChannelId = 'medication_urgent';

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
        const AndroidNotificationChannel(_reminderChannelId, 'Reminders', importance: Importance.max, playSound: false),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(_urgentChannelId, 'Urgent Reminders', importance: Importance.max, playSound: false),
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
      'scheduleId': scheduleId, 'medicationId': medicationId,
      'scheduledFor': scheduledFor.toIso8601String(), 'medicationName': medicationName,
      'dosageDisplay': dosageDisplay,
    });

    // 1. PRIOR ALERT (10 mins before)
    final priorTime = scheduledFor.subtract(const Duration(minutes: 10));
    await _schedule(
      id: _generateId(scheduleId, scheduledFor, 99),
      title: 'Prior Alert: $medicationName',
      body: 'Get ready to take your medicine in 10 mins',
      time: priorTime,
      payload: payload,
      isUrgent: false,
      vibration: [0, 200, 200, 200, 200, 200, 200, 200, 200, 200],
    );

    // 2. DUE NOW
    await _schedule(
      id: _generateId(scheduleId, scheduledFor, 0),
      title: 'Time to Take Medicine',
      body: '$medicationName - $dosageDisplay',
      time: scheduledFor,
      payload: payload,
      isUrgent: true,
      vibration: [0, 1000, 500, 1000, 500],
      isFullScreen: true,
    );
  }

  Future<void> _schedule({
    required int id, required String title, required String body,
    required DateTime time, required String payload,
    required bool isUrgent, List<int>? vibration, bool isFullScreen = false,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        isUrgent ? _urgentChannelId : _reminderChannelId,
        'Medication Alarms',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: isFullScreen,
        category: AndroidNotificationCategory.alarm,
        vibrationPattern: vibration != null ? Int64List.fromList(vibration) : null, // ✅ FIXED
        playSound: false,
        sound: null,
        actions: const [
          AndroidNotificationAction('MARK_TAKEN', '✅ Mark Taken', showsUserInterface: true),
        ],
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: false),
    );

    await _plugin.zonedSchedule(
      id: id, title: title, body: body,
      scheduledDate: tz.TZDateTime.from(time, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  Future<void> cancelDose({required String scheduleId, required DateTime scheduledFor}) async {
    for (int i = 0; i <= 2; i++) {
      await _plugin.cancel(id: _generateId(scheduleId, scheduledFor, i)); // ✅ FIXED: named parameter
    }
  }

  Future<void> cancelSchedule(String scheduleId) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.payload != null && n.payload!.contains(scheduleId)) await _plugin.cancel(id: n.id); // ✅ FIXED: named parameter
    }
  }

  int _generateId(String scheduleId, DateTime time, int step) =>
      '${scheduleId}_${time.millisecondsSinceEpoch}_$step'.hashCode.abs() % 2147483647;
}

// ── Notification Tap Logic ──
@pragma('vm:entry-point')
Future<void> _onNotificationTapped(NotificationResponse response) async {
  if (response.payload == null) return;
  final data = jsonDecode(response.payload!);

  if (response.actionId == 'MARK_TAKEN') {
    await DoseLogService.instance.markAsTaken(
      scheduleId: data['scheduleId'], medicationId: data['medicationId'],
      scheduledFor: DateTime.parse(data['scheduledFor']),
    );
    return;
  }

  final dose = TodayDose(
    scheduleId: data['scheduleId'], medicationId: data['medicationId'],
    medicationName: data['medicationName'], genericName: data['medicationName'],
    dosageAmount: double.tryParse(data['dosageDisplay'].split(' ').first) ?? 0.0,
    dosageUnit: data['dosageDisplay'].split(' ').last,
    scheduledTime: DateTime.parse(data['scheduledFor']),
    pillImageUrl: null,
  );

  navigatorKey.currentState?.push(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => MedicationReminderScannerScreen(dose: dose)),
  );
}