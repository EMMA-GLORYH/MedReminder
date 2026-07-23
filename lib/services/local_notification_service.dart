// lib/services/local_notification_service.dart

import 'dart:async';
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

void localNotificationLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

// This name must match SCANNER_ROUTE_CHANNEL in MainActivity.kt.
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
  Future<void>? _initializationFuture;

  // Scanner payloads can arrive before MaterialApp has created the root navigator.
  final List<String> _pendingScannerPayloads = <String>[];

  // Prevent duplicate opening.
  final Set<String> _queuedScannerKeys = <String>{};

  bool _isDrainingScannerQueue = false;

  // Versioned channels are used because Android notification-channel properties
  // cannot be changed after creation.
  static const String _reminderChannelId = 'medication_prior_visual_v2';

  static const String _urgentChannelId = 'medication_due_visual_v2';

  static final Int64List _noVibration = Int64List.fromList(
    const <int>[0],
  );

  // Stable notification/alarm IDs steps.
  static const int _dueNotificationStep = 0;
  static const int _legacyEscalationStep1 = 1;
  static const int _legacyEscalationStep2 = 2;
  static const int _priorNativeAlarmStep = 98;
  static const int _priorNotificationStep = 99;
  static const int _dueNativeAlarmStep = 100;
  static const int _retryNativeAlarmStep = 101;

  static const Duration _priorDuration = Duration(
    minutes: 10,
  );

  static const String _payloadPreferencePrefix = 'cached_dose_payload_';

  static const String _alarmIdsPreferenceKey = 'tracked_native_alarm_ids';

  /// Tracks native alarm IDs by schedule ID.
  ///
  /// This helps cancellation be more direct and keeps alarm IDs available after
  /// app restart. We still scan pending notification payloads as a fallback for
  /// older alarms that were scheduled before this tracking existed.
  final Map<String, Set<int>> _scheduledAlarmIds = <String, Set<int>>{};

  // ══════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ══════════════════════════════════════════════════════════════

  Future<void> init() {
    if (_initialized) {
      return Future<void>.value();
    }

    return _initializationFuture ??= _performInitialization();
  }

  Future<void> _performInitialization() async {
    // Register scanner handler early.
    _scannerRouteChannel.setMethodCallHandler(
          (MethodCall call) async {
        if (call.method != 'openScanner') {
          return false;
        }

        final payload =
        call.arguments is String ? call.arguments as String : null;

        if (payload == null || payload.trim().isEmpty) {
          return false;
        }

        _queueScannerPayload(payload);
        return true;
      },
    );

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));

    const androidInitialization = AndroidInitializationSettings(
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
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _urgentChannelId,
          'Medication Due Alerts',
          description: 'Visual notification when a medication dose is due',
          importance: Importance.max,
          playSound: false,
          enableVibration: false,
          enableLights: true,
          ledColor: Color(0xFF00BFA5),
          showBadge: true,
          bypassDnd: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannelId,
          'Upcoming Medication Reminders',
          description: 'Visual notification ten minutes before a dose',
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

    await _loadPersistedAlarmIds();

    _initialized = true;

    // Retrieve cold-start payload from MainActivity.
    await _retrieveInitialNativeScannerPayload();

    // Also handle cold start from a tapped visual notification.
    await _processNotificationLaunchDetails();

    localNotificationLog('✅ LocalNotificationService initialized');
  }

  Future<void> _retrieveInitialNativeScannerPayload() async {
    try {
      final initialPayload = await _scannerRouteChannel.invokeMethod<String>(
        'getInitialScannerPayload',
      );

      if (initialPayload == null || initialPayload.trim().isEmpty) {
        return;
      }

      localNotificationLog('📥 Received initial scanner payload from MainActivity');
      _queueScannerPayload(initialPayload);
    } on MissingPluginException {
      localNotificationLog('⚠️ Native scanner route channel is unavailable');
    } on PlatformException catch (error) {
      localNotificationLog(
        '⚠️ Could not retrieve initial scanner payload: ${error.message}',
      );
    } catch (error, stack) {
      localNotificationLog(
        '⚠️ Could not retrieve initial scanner payload: $error',
      );
      localNotificationLog('$stack');
    }
  }

  Future<void> _processNotificationLaunchDetails() async {
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();

      if (launchDetails?.didNotificationLaunchApp != true) {
        return;
      }

      final response = launchDetails?.notificationResponse;
      if (response == null) return;

      await _handleNotificationResponse(response);
    } catch (error, stack) {
      localNotificationLog(
        '⚠️ Could not process notification launch details: $error',
      );
      localNotificationLog('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ALARM ID TRACKING
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadPersistedAlarmIds() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_alarmIdsPreferenceKey);

      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      _scheduledAlarmIds.clear();

      for (final entry in decoded.entries) {
        final scheduleId = entry.key;
        final rawIds = entry.value;

        if (rawIds is! List) continue;

        _scheduledAlarmIds[scheduleId] = rawIds
            .whereType<num>()
            .map((value) => value.toInt())
            .where((value) => value > 0)
            .toSet();
      }

      localNotificationLog(
        '📦 Loaded tracked native alarm IDs for '
            '${_scheduledAlarmIds.length} schedule(s)',
      );
    } catch (error) {
      localNotificationLog('⚠️ Could not load tracked native alarm IDs: $error');
    }
  }

  Future<void> _persistAlarmIds() async {
    try {
      final preferences = await SharedPreferences.getInstance();

      final encoded = _scheduledAlarmIds.map(
            (scheduleId, ids) => MapEntry(
          scheduleId,
          ids.toList(),
        ),
      );

      await preferences.setString(
        _alarmIdsPreferenceKey,
        jsonEncode(encoded),
      );
    } catch (error) {
      localNotificationLog(
        '⚠️ Could not persist tracked native alarm IDs: $error',
      );
    }
  }

  void _trackAlarmId({
    required String scheduleId,
    required int alarmId,
  }) {
    if (scheduleId.trim().isEmpty || alarmId <= 0) return;

    _scheduledAlarmIds.putIfAbsent(scheduleId, () => <int>{});
    _scheduledAlarmIds[scheduleId]!.add(alarmId);
  }

  void _untrackAlarmIds({
    required String scheduleId,
    required Iterable<int> alarmIds,
  }) {
    final tracked = _scheduledAlarmIds[scheduleId];
    if (tracked == null) return;

    for (final alarmId in alarmIds) {
      tracked.remove(alarmId);
    }

    if (tracked.isEmpty) {
      _scheduledAlarmIds.remove(scheduleId);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // SCANNER ROUTE QUEUE
  // ══════════════════════════════════════════════════════════════

  void _queueScannerPayload(String rawPayload) {
    final payload = rawPayload.trim();
    if (payload.isEmpty) return;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Scanner payload must be a JSON object',
        );
      }

      final alertType = decoded['alertType']?.toString() ?? 'medication_due';

      if (alertType == 'prior_reminder') {
        localNotificationLog('ℹ️ Scanner route ignored for prior reminder');
        return;
      }

      final scannerKey = _scannerKey(decoded);

      if (_queuedScannerKeys.contains(scannerKey)) {
        localNotificationLog(
          'ℹ️ Duplicate scanner request ignored: $scannerKey',
        );
        return;
      }

      _queuedScannerKeys.add(scannerKey);
      _pendingScannerPayloads.add(payload);

      localNotificationLog(
        '📥 Medication scanner request queued: $scannerKey',
      );

      unawaited(_drainScannerQueue());
    } catch (error) {
      localNotificationLog('❌ Invalid scanner payload: $error');
    }
  }

  String _scannerKey(Map<String, dynamic> data) {
    final patientId = data['patientId']?.toString() ?? '';
    final scheduleId = data['scheduleId']?.toString() ?? '';
    final medicationId = data['medicationId']?.toString() ?? '';
    final scheduledFor = data['scheduledFor']?.toString() ??
        data['scheduledForMillis']?.toString() ??
        '';

    return '$patientId|$scheduleId|$medicationId|$scheduledFor';
  }

  Future<void> _drainScannerQueue() async {
    if (_isDrainingScannerQueue) return;
    _isDrainingScannerQueue = true;

    try {
      while (_pendingScannerPayloads.isNotEmpty) {
        final navigator = navigatorKey.currentState;

        if (navigator == null || !navigator.mounted) {
          await Future<void>.delayed(
            const Duration(milliseconds: 250),
          );
          continue;
        }

        final payload = _pendingScannerPayloads.removeAt(0);

        String? scannerKey;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            scannerKey = _scannerKey(decoded);
          }

          await _openScannerFromPayload(
            rawPayload: payload,
            navigator: navigator,
          );
        } catch (error) {
          localNotificationLog(
            '❌ Could not process queued scanner route: $error',
          );
        } finally {
          if (scannerKey != null) {
            _queuedScannerKeys.remove(scannerKey);
          }
        }
      }
    } finally {
      _isDrainingScannerQueue = false;

      if (_pendingScannerPayloads.isNotEmpty) {
        unawaited(_drainScannerQueue());
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // SCHEDULE A DOSE
  // ══════════════════════════════════════════════════════════════

  Future<void> scheduleForDose({
    required String patientId,
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
      localNotificationLog(
        'ℹ️ Skipping dose notification because the time has already passed: '
            '$scheduledFor',
      );
      return;
    }

    final priorTime = scheduledFor.subtract(_priorDuration);

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
      'patientId': patientId,
      'scheduleId': scheduleId,
      'medicationId': medicationId,
      'scheduledFor': scheduledFor.toIso8601String(),
      'scheduledForMillis': scheduledFor.millisecondsSinceEpoch,
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

    // Cache due payload so it survives reboot/offline for native restore.
    await _cachePayload(
      scheduleId: scheduleId,
      scheduledFor: scheduledFor,
      payload: duePayload,
    );

    // 1) Prior reminder
    if (priorTime.isAfter(now)) {
      await _scheduleVisualNotification(
        id: priorNotificationId,
        title: '⏰ Upcoming: $medicationName',
        body: 'Get ready — $dosageDisplay is due in 10 minutes',
        time: priorTime,
        payload: priorPayload,
        isUrgent: false,
        showDoseActions: false,
      );

      await MedicationTtsService.instance.schedulePriorReminder(
        alarmId: priorNativeAlarmId,
        startAt: priorTime,
        medicationName: medicationName,
        dosageDisplay: dosageDisplay,
        minutesBefore: 10,
      );

      _trackAlarmId(
        scheduleId: scheduleId,
        alarmId: priorNativeAlarmId,
      );
    }

    // 2) Due exact
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
      message: 'It is time to take $medicationName. '
          'Dosage: $dosageDisplay. Please confirm your medicine now.',
      payload: duePayload,
    );

    _trackAlarmId(
      scheduleId: scheduleId,
      alarmId: dueNativeAlarmId,
    );

    await _persistAlarmIds();

    if (escalationStep1Mins < 0 || escalationStep2Mins < 0) {
      localNotificationLog('⚠️ Invalid escalation values were supplied');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // SCHEDULE TEN-MINUTE RETRY AFTER REMINDER IS STOPPED
  // ══════════════════════════════════════════════════════════════

  Future<void> scheduleDoseRetry({
    required String patientId,
    required String scheduleId,
    required String medicationId,
    required String medicationName,
    required String dosageDisplay,
    required DateTime scheduledFor,
    String? pillImageUrl,
  }) async {
    if (!_initialized) {
      await init();
    }

    final safePatientId = patientId.trim();

    if (safePatientId.isEmpty) {
      localNotificationLog(
        '⚠️ Cannot schedule medication retry: patientId is empty',
      );
      return;
    }

    final retryTime = DateTime.now().add(
      const Duration(minutes: 10),
    );

    final retryAlarmId = _generateId(
      scheduleId,
      scheduledFor,
      _retryNativeAlarmStep,
    );

    final retryPayload = jsonEncode(
      <String, dynamic>{
        'patientId': safePatientId,
        'scheduleId': scheduleId,
        'medicationId': medicationId,
        'scheduledFor': scheduledFor.toIso8601String(),
        'scheduledForMillis': scheduledFor.millisecondsSinceEpoch,
        'medicationName': medicationName,
        'dosageDisplay': dosageDisplay,
        'pillImageUrl': pillImageUrl ?? '',
        'alertType': 'medication_retry',
        'retry': true,
      },
    );

    await MedicationTtsService.instance.scheduleAutoOpen(
      alarmId: retryAlarmId,
      startAt: retryTime,
      message: 'Your medication has not been confirmed as taken. '
          'It is time to take $medicationName. '
          'Dosage: $dosageDisplay. '
          'Please confirm your medicine now.',
      payload: retryPayload,
    );

    _trackAlarmId(
      scheduleId: scheduleId,
      alarmId: retryAlarmId,
    );

    await _persistAlarmIds();

    localNotificationLog(
      '🔁 Medication retry scheduled for $retryTime '
          '(alarmId=$retryAlarmId)',
    );
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
    if (!time.isAfter(now)) return;

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        isUrgent ? _urgentChannelId : _reminderChannelId,
        isUrgent ? 'Medication Due Alerts' : 'Upcoming Medication Reminders',
        channelDescription: isUrgent
            ? 'Visual notification when a medication dose is due'
            : 'Visual notification ten minutes before a dose',
        importance: isUrgent ? Importance.max : Importance.high,
        priority: isUrgent ? Priority.max : Priority.high,
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
        ticker: isUrgent ? 'Medication due' : 'Upcoming medication',
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
        fullScreenIntent: false,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: false,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(time, tz.local),
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (_) {
      // Best-effort; native AlarmManager is still the critical path.
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PAYLOAD CACHE HELPERS
  // ══════════════════════════════════════════════════════════════

  String _cacheKey(String scheduleId, DateTime scheduledFor) {
    return '$_payloadPreferencePrefix${scheduleId}_${scheduledFor.millisecondsSinceEpoch}';
  }

  Future<void> _cachePayload({
    required String scheduleId,
    required DateTime scheduledFor,
    required String payload,
  }) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _cacheKey(scheduleId, scheduledFor),
        payload,
      );
    } catch (_) {}
  }

  Future<void> _removeCachedPayload({
    required String scheduleId,
    required DateTime scheduledFor,
  }) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_cacheKey(scheduleId, scheduledFor));
    } catch (_) {}
  }

  Future<void> _removeSchedulePayloads(String scheduleId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final prefix = '$_payloadPreferencePrefix${scheduleId}_';
      final keys = preferences
          .getKeys()
          .where((key) => key.startsWith(prefix))
          .toList();

      for (final key in keys) {
        await preferences.remove(key);
      }
    } catch (_) {}
  }

  Future<void> _removeAllCachedPayloads() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final keys = preferences
          .getKeys()
          .where((key) => key.startsWith(_payloadPreferencePrefix))
          .toList();

      for (final key in keys) {
        await preferences.remove(key);
      }
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════
  // CANCEL DOSE / SCHEDULE / ALL
  // ══════════════════════════════════════════════════════════════

  Future<void> cancelDose({
    required String scheduleId,
    required DateTime scheduledFor,
  }) async {
    if (!_initialized) {
      await init();
    }

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
      } catch (_) {}
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

    final retryNativeAlarmId = _generateId(
      scheduleId,
      scheduledFor,
      _retryNativeAlarmStep,
    );

    await MedicationTtsService.instance.cancelPriorReminder(
      priorNativeAlarmId,
    );

    await MedicationTtsService.instance.cancelAutoOpen(
      dueNativeAlarmId,
    );

    await MedicationTtsService.instance.cancelAutoOpen(
      retryNativeAlarmId,
    );

    /*
     * Stops TTS, alarm.mp3, vibration, flashlight and foreground service.
     */
    await MedicationTtsService.instance.stop();

    await _removeCachedPayload(
      scheduleId: scheduleId,
      scheduledFor: scheduledFor,
    );

    _untrackAlarmIds(
      scheduleId: scheduleId,
      alarmIds: <int>[
        priorNativeAlarmId,
        dueNativeAlarmId,
        retryNativeAlarmId,
      ],
    );

    await _persistAlarmIds();

    localNotificationLog(
      '🗑️ Cancelled all alerts, including retry, for '
          '$scheduleId at $scheduledFor',
    );
  }

  Future<void> cancelSchedule(String scheduleId) async {
    if (!_initialized) {
      await init();
    }

    final nativeAlarmIds = <int>{};
    nativeAlarmIds.addAll(_scheduledAlarmIds[scheduleId] ?? <int>{});

    final pending = await _plugin.pendingNotificationRequests();

    for (final notification in pending) {
      final rawPayload = notification.payload;
      if (rawPayload == null) continue;

      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is! Map<String, dynamic>) continue;

        final payloadScheduleId = decoded['scheduleId']?.toString();
        if (payloadScheduleId != scheduleId) continue;

        final scheduledFor = _scheduledTimeFromPayload(decoded);

        nativeAlarmIds.add(
          _generateId(scheduleId, scheduledFor, _priorNativeAlarmStep),
        );
        nativeAlarmIds.add(
          _generateId(scheduleId, scheduledFor, _dueNativeAlarmStep),
        );
        nativeAlarmIds.add(
          _generateId(scheduleId, scheduledFor, _retryNativeAlarmStep),
        );

        try {
          await _plugin.cancel(id: notification.id);
        } catch (_) {}
      } catch (_) {}
    }

    for (final alarmId in nativeAlarmIds) {
      await MedicationTtsService.instance.cancelAutoOpen(alarmId);
    }

    await _removeSchedulePayloads(scheduleId);

    _scheduledAlarmIds.remove(scheduleId);
    await _persistAlarmIds();

    localNotificationLog(
      '🗑️ Cancelled schedule $scheduleId '
          '(${nativeAlarmIds.length} native alarm(s))',
    );
  }

  Future<void> cancelAll() async {
    if (!_initialized) {
      await init();
    }

    final pending = await _plugin.pendingNotificationRequests();

    final nativeAlarmIds = <int>{};

    for (final ids in _scheduledAlarmIds.values) {
      nativeAlarmIds.addAll(ids);
    }

    for (final notification in pending) {
      final rawPayload = notification.payload;
      if (rawPayload == null) continue;

      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is! Map<String, dynamic>) continue;

        final scheduleId = decoded['scheduleId']?.toString();
        if (scheduleId == null || scheduleId.trim().isEmpty) continue;

        final scheduledFor = _scheduledTimeFromPayload(decoded);

        nativeAlarmIds.add(
          _generateId(scheduleId, scheduledFor, _priorNativeAlarmStep),
        );
        nativeAlarmIds.add(
          _generateId(scheduleId, scheduledFor, _dueNativeAlarmStep),
        );
        nativeAlarmIds.add(
          _generateId(scheduleId, scheduledFor, _retryNativeAlarmStep),
        );
      } catch (_) {}
    }

    await _plugin.cancelAll();

    for (final alarmId in nativeAlarmIds) {
      await MedicationTtsService.instance.cancelAutoOpen(alarmId);
    }

    await MedicationTtsService.instance.stop();
    await _removeAllCachedPayloads();

    _pendingScannerPayloads.clear();
    _queuedScannerKeys.clear();
    _scheduledAlarmIds.clear();

    await _persistAlarmIds();

    localNotificationLog('🗑️ Cancelled all notifications and native alarms');
  }

  DateTime _scheduledTimeFromPayload(Map<String, dynamic> data) {
    final rawMillis = data['scheduledForMillis'];
    if (rawMillis is num) {
      return DateTime.fromMillisecondsSinceEpoch(rawMillis.toInt());
    }

    final rawScheduledFor = data['scheduledFor']?.toString();
    if (rawScheduledFor == null || rawScheduledFor.trim().isEmpty) {
      throw const FormatException('Missing scheduled medication time');
    }

    return DateTime.parse(rawScheduledFor);
  }

  // ══════════════════════════════════════════════════════════════
  // ID GENERATOR
  // ══════════════════════════════════════════════════════════════

  int _generateId(
      String scheduleId,
      DateTime time,
      int step,
      ) {
    return '${scheduleId}_${time.millisecondsSinceEpoch}_$step'
        .hashCode
        .abs() %
        2147483647;
  }
}

// ══════════════════════════════════════════════════════════════
// OPEN REMINDER SCREEN FROM PAYLOAD
// ══════════════════════════════════════════════════════════════

Future<void> _openScannerFromPayload({
  required String rawPayload,
  required NavigatorState navigator,
}) async {
  try {
    final decoded = jsonDecode(rawPayload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Scanner payload must be a JSON object',
      );
    }

    final alertType = decoded['alertType']?.toString() ?? 'medication_due';

    if (alertType == 'prior_reminder') {
      return;
    }

    final scheduleId = decoded['scheduleId']?.toString();
    final medicationId = decoded['medicationId']?.toString();
    final patientId = decoded['patientId']?.toString();
    final rawScheduledFor = decoded['scheduledFor']?.toString();

    if (scheduleId == null ||
        scheduleId.trim().isEmpty ||
        medicationId == null ||
        medicationId.trim().isEmpty ||
        rawScheduledFor == null ||
        rawScheduledFor.trim().isEmpty) {
      throw const FormatException(
        'Scanner payload is missing dose identifiers',
      );
    }

    final rawDosage = decoded['dosageDisplay']?.toString().trim() ?? '';
    final dosageParts =
    rawDosage.isEmpty ? <String>[] : rawDosage.split(RegExp(r'\s+'));

    final dosageAmount = dosageParts.isNotEmpty
        ? (double.tryParse(dosageParts.first) ?? 1.0)
        : 1.0;

    final dosageUnit = dosageParts.length > 1
        ? dosageParts.sublist(1).join(' ')
        : (rawDosage.isNotEmpty ? rawDosage : 'dose');

    final rawImageUrl = decoded['pillImageUrl']?.toString().trim();

    final medicationName =
        decoded['medicationName']?.toString().trim().takeIfNotEmpty ??
            'Medication';

    final genericName =
        decoded['genericName']?.toString().trim().takeIfNotEmpty ??
            medicationName;

    final dose = TodayDose(
      patientId: patientId,
      scheduleId: scheduleId,
      medicationId: medicationId,
      medicationName: medicationName,
      genericName: genericName,
      dosageAmount: dosageAmount,
      dosageUnit: dosageUnit,
      scheduledTime: DateTime.parse(rawScheduledFor),
      pillImageUrl:
      rawImageUrl != null && rawImageUrl.isNotEmpty ? rawImageUrl : null,
    );

    await navigator.push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => MedicationReminderScannerScreen(dose: dose),
      ),
    );
  } catch (error, stack) {
    localNotificationLog(
      '❌ Failed to open reminder screen from payload: $error',
    );
    localNotificationLog('$stack');
  }
}

// ══════════════════════════════════════════════════════════════
// NOTIFICATION TAP / ACTION HANDLER
// ══════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
Future<void> _onNotificationTapped(
    NotificationResponse response,
    ) async {
  await _handleNotificationResponse(response);
}

Future<void> _handleNotificationResponse(
    NotificationResponse response,
    ) async {
  final rawPayload = response.payload;

  if (rawPayload == null || rawPayload.trim().isEmpty) return;

  try {
    final decoded = jsonDecode(rawPayload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Notification payload must be a JSON object',
      );
    }

    final alertType = decoded['alertType']?.toString() ?? 'medication_due';

    if (alertType == 'prior_reminder') {
      return;
    }

    if (response.actionId == 'MARK_TAKEN') {
      final scheduleId = decoded['scheduleId']?.toString();
      final medicationId = decoded['medicationId']?.toString();
      final scheduledForStr = decoded['scheduledFor']?.toString();
      final patientId = decoded['patientId']?.toString();

      if (scheduleId == null ||
          scheduleId.trim().isEmpty ||
          medicationId == null ||
          medicationId.trim().isEmpty ||
          scheduledForStr == null ||
          scheduledForStr.trim().isEmpty) {
        throw const FormatException('Mark-as-taken payload is incomplete');
      }

      await DoseLogService.instance.markAsTaken(
        scheduleId: scheduleId,
        medicationId: medicationId,
        scheduledFor: DateTime.parse(scheduledForStr),
        patientId: patientId,
      );

      await MedicationTtsService.instance.stop();
      return;
    }

    // OPEN_SCANNER action / body tap: queue + native handler will open.
    LocalNotificationService.instance._queueScannerPayload(rawPayload);
  } catch (error, stack) {
    localNotificationLog('❌ Notification response failed: $error');
    localNotificationLog('$stack');
  }
}

// Small helper for safely selecting non-empty payload strings.
extension _NonEmptyStringExtension on String {
  String? get takeIfNotEmpty {
    return isEmpty ? null : this;
  }
}