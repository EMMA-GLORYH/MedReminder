// // lib/services/firebase_service.dart
//
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/foundation.dart';
// import '../config/firebase_config.dart';
// import 'auth_service.dart';
//
// class FirebaseService {
//   FirebaseService._();
//   static final FirebaseService instance = FirebaseService._();
//
//   final FirebaseFirestore _db  = FirebaseFirestore.instance;
//   final FirebaseMessaging _fcm = FirebaseMessaging.instance;
//
//   // ══════════════════════════════════════════════════════════
//   // INITIALIZATION — call once after user logs in
//   // ══════════════════════════════════════════════════════════
//   Future<void> initForUser() async {
//     final userId = AuthService.instance.currentUser?.id;
//     if (userId == null) {
//       debugPrint('⚠️ FirebaseService: No user logged in, skipping init');
//       return;
//     }
//
//     await _requestPermission();
//     await _saveFcmToken(userId);
//     _listenToTokenRefresh(userId);
//     debugPrint('✅ FirebaseService initialized for user $userId');
//   }
//
//   // ══════════════════════════════════════════════════════════
//   // PERMISSIONS
//   // ══════════════════════════════════════════════════════════
//   Future<void> _requestPermission() async {
//     final settings = await _fcm.requestPermission(
//       alert:       true,
//       badge:       true,
//       sound:       true,
//       provisional: false,
//     );
//     debugPrint('🔔 Permission: ${settings.authorizationStatus}');
//   }
//
//   // ══════════════════════════════════════════════════════════
//   // FCM TOKEN MANAGEMENT
//   // ══════════════════════════════════════════════════════════
//   Future<void> _saveFcmToken(String userId) async {
//     try {
//       final token = kIsWeb
//           ? await _fcm.getToken(vapidKey: FirebaseConfig.vapidKey)
//           : await _fcm.getToken();
//
//       if (token == null) {
//         debugPrint('⚠️ FCM token is null');
//         return;
//       }
//
//       debugPrint('🔑 FCM Token: ${token.substring(0, 20)}...');
//
//       await _db.collection('users').doc(userId).set({
//         'fcm_token':  token,
//         'platform':   kIsWeb ? 'web' : defaultTargetPlatform.name,
//         'updated_at': FieldValue.serverTimestamp(),
//       }, SetOptions(merge: true));
//
//       debugPrint('✅ FCM token saved to Firestore');
//     } catch (e) {
//       debugPrint('❌ Failed to save FCM token: $e');
//     }
//   }
//
//   void _listenToTokenRefresh(String userId) {
//     _fcm.onTokenRefresh.listen((newToken) async {
//       debugPrint('🔄 FCM token refreshed');
//       await _db.collection('users').doc(userId).set({
//         'fcm_token':  newToken,
//         'updated_at': FieldValue.serverTimestamp(),
//       }, SetOptions(merge: true));
//     });
//   }
//
//   // ══════════════════════════════════════════════════════════
//   // SYNC SCHEDULE → FIRESTORE (creates notification slots)
//   // ══════════════════════════════════════════════════════════
//   Future<void> syncScheduleToFirestore({
//     required String userId,
//     required String scheduleId,
//     required String medicationId,
//     required String medicationName,
//     required String dosageDisplay,
//     required List<DateTime> scheduledTimes,
//     required DateTime startDate,
//     DateTime? endDate,
//     int escalationStep1Mins = 10,
//     int escalationStep2Mins = 20,
//   }) async {
//     try {
//       final batch = _db.batch();
//
//       for (final scheduledFor in scheduledTimes) {
//         final docId = '${scheduleId}_${scheduledFor.millisecondsSinceEpoch}';
//         final ref   = _db.collection('notification_schedules').doc(docId);
//
//         batch.set(ref, {
//           'userId':              userId,
//           'scheduleId':          scheduleId,
//           'medicationId':        medicationId,
//           'medicationName':      medicationName,
//           'dosageDisplay':       dosageDisplay,
//           'scheduledFor':        Timestamp.fromDate(scheduledFor),
//           'status':              'pending',
//           'escalationStep1Mins': escalationStep1Mins,
//           'escalationStep2Mins': escalationStep2Mins,
//           'createdAt':           FieldValue.serverTimestamp(),
//         }, SetOptions(merge: true));
//       }
//
//       await batch.commit();
//       debugPrint('✅ Synced ${scheduledTimes.length} notification slots');
//     } catch (e) {
//       debugPrint('❌ Failed to sync schedule: $e');
//     }
//   }
//
//   // ══════════════════════════════════════════════════════════
//   // MARK DOSE AS TAKEN IN FIRESTORE
//   // ══════════════════════════════════════════════════════════
//   Future<void> markNotificationTaken({
//     required String scheduleId,
//     required DateTime scheduledFor,
//   }) async {
//     try {
//       final docId = '${scheduleId}_${scheduledFor.millisecondsSinceEpoch}';
//       await _db.collection('notification_schedules').doc(docId).update({
//         'status':  'taken',
//         'takenAt': FieldValue.serverTimestamp(),
//       });
//       debugPrint('✅ Firestore: marked $docId as taken');
//     } catch (e) {
//       debugPrint('⚠️ Could not update Firestore: $e');
//     }
//   }
//
//   // ══════════════════════════════════════════════════════════
//   // DELETE NOTIFICATIONS FOR A SCHEDULE
//   // ══════════════════════════════════════════════════════════
//   Future<void> deleteScheduleNotifications(String scheduleId) async {
//     try {
//       final snap = await _db
//           .collection('notification_schedules')
//           .where('scheduleId', isEqualTo: scheduleId)
//           .get();
//
//       final batch = _db.batch();
//       for (final doc in snap.docs) {
//         batch.delete(doc.reference);
//       }
//       await batch.commit();
//       debugPrint('🗑️ Deleted ${snap.docs.length} notifications');
//     } catch (e) {
//       debugPrint('⚠️ Delete failed: $e');
//     }
//   }
// }