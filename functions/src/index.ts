// functions/src/index.ts

import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";

admin.initializeApp();
const db = admin.firestore();

// ══════════════════════════════════════════════════════════════
// SEND MEDICATION REMINDERS — runs every minute
// ══════════════════════════════════════════════════════════════
export const sendMedicationReminders = onSchedule(
  {schedule: "* * * * *", timeZone: "UTC"},
  async () => {
    const now = admin.firestore.Timestamp.now();
    const later = admin.firestore.Timestamp.fromMillis(now.toMillis() + 60_000);

    const snap = await db
      .collection("notification_schedules")
      .where("status", "==", "pending")
      .where("scheduledFor", ">=", now)
      .where("scheduledFor", "<", later)
      .get();

    if (snap.empty) {
      console.log("No reminders due");
      return;
    }

    console.log(`📤 Sending ${snap.size} reminder(s)`);

    for (const doc of snap.docs) {
      const data = doc.data();

      const userDoc = await db.collection("users").doc(data.userId).get();
      const token = userDoc.data()?.fcm_token;

      if (!token) {
        console.warn(`⚠️ No token for user ${data.userId}`);
        continue;
      }

      const scheduledFor = (data.scheduledFor as admin.firestore.Timestamp)
        .toDate().toISOString();

      try {
        await admin.messaging().send({
          token,
          notification: {
            title: `💊 Time for ${data.medicationName}`,
            body: `Take your ${data.dosageDisplay} now`,
          },
          data: {
            scheduleId: data.scheduleId,
            medicationId: data.medicationId,
            medicationName: data.medicationName,
            dosageDisplay: data.dosageDisplay,
            scheduledFor,
            type: "medication_reminder",
          },
          webpush: {
            notification: {
              icon: "/icons/Icon-192.png",
              badge: "/icons/Icon-192.png",
              requireInteraction: true,
            },
            fcmOptions: {link: "/"},
          },
          android: {
            priority: "high",
            notification: {
              channelId: "medication_reminders",
              priority: "max",
              defaultSound: true,
              defaultVibrateTimings: true,
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
        });

        await doc.ref.update({
          status: "sent",
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Schedule escalation step 1
        await db.collection("escalation_queue").add({
          notificationDocId: doc.id,
          token,
          data,
          scheduledFor,
          escalationTime: admin.firestore.Timestamp.fromMillis(
            Date.now() + (data.escalationStep1Mins ?? 10) * 60_000
          ),
          step: 1,
          step2Mins: data.escalationStep2Mins ?? 20,
        });

        console.log(`✅ Sent for ${data.medicationName}`);
      } catch (err) {
        console.error("❌ Send failed:", err);
        await doc.ref.update({status: "error"});
      }
    }
  }
);

// ══════════════════════════════════════════════════════════════
// ESCALATION PROCESSOR — runs every minute
// ══════════════════════════════════════════════════════════════
export const processEscalations = onSchedule(
  {schedule: "* * * * *", timeZone: "UTC"},
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db
      .collection("escalation_queue")
      .where("escalationTime", "<=", now)
      .get();

    for (const doc of snap.docs) {
      const esc = doc.data();

      // Skip if user already took it
      const notif = await db
        .collection("notification_schedules")
        .doc(esc.notificationDocId)
        .get();

      if (notif.data()?.status === "taken") {
        await doc.ref.delete();
        continue;
      }

      try {
        await admin.messaging().send({
          token: esc.token,
          notification: {
            title: `⚠️ Missed: ${esc.data.medicationName}`,
            body: `You haven't taken your ${esc.data.dosageDisplay}`,
          },
          data: {
            scheduleId: esc.data.scheduleId,
            medicationId: esc.data.medicationId,
            medicationName: esc.data.medicationName,
            dosageDisplay: esc.data.dosageDisplay,
            scheduledFor: esc.scheduledFor,
            type: "escalation",
            step: String(esc.step),
          },
          webpush: {
            notification: {
              icon: "/icons/Icon-192.png",
              requireInteraction: true,
            },
          },
          android: {
            priority: "high",
            notification: {
              channelId: "medication_reminders",
              priority: "max",
            },
          },
        });

        // Schedule step 2 if this was step 1
        if (esc.step === 1) {
          await db.collection("escalation_queue").add({
            notificationDocId: esc.notificationDocId,
            token: esc.token,
            data: esc.data,
            scheduledFor: esc.scheduledFor,
            escalationTime: admin.firestore.Timestamp.fromMillis(
              Date.now() + esc.step2Mins * 60_000
            ),
            step: 2,
            step2Mins: esc.step2Mins,
          });
        }

        await doc.ref.delete();
        console.log(`📢 Escalation ${esc.step} sent`);
      } catch (err) {
        console.error("❌ Escalation failed:", err);
        await doc.ref.delete();
      }
    }
  }
);
