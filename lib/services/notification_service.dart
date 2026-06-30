import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);
  }

  /// ✅ Only this method will be used for the 2-minute warning
  static Future<void> showTwoMinuteWarning(
    String seatNumber,
    String buildingName,
    String roomName,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'session_channel',
          'Session Notifications',
          channelDescription: 'Notifications about your seat session',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      0, // Fixed ID
      '🕐 Session Expiring Soon',
      'Your session for Seat $seatNumber at $buildingName - $roomName will expire in 2 minutes!',
      details,
    );
  }

  /// Optional: Cancel all previous notifications
  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Clear user warning notifications from Firestore
  static Future<void> clearUserNotifications(String userId, {String? title}) async {
    if (userId.isEmpty) return;
    try {
      final firestore = FirebaseFirestore.instance;
      Query query = firestore.collection('notifications').where('userId', isEqualTo: userId);
      if (title != null) {
        query = query.where('title', isEqualTo: title);
      }
      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return;

      final batch = firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error clearing notifications: $e');
    }
  }
}
