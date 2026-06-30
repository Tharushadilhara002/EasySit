import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../navigator_key.dart';
import '../widgets/expiry_dialog.dart';
import 'notification_service.dart';

class SessionWatcher {
  static Timer? _timer;
  static Timer? _countdownTimer;
  static bool _dialogShowing = false;
  static String? _currentSeatId;
  static final ValueNotifier<int> _countdownNotifier = ValueNotifier<int>(0);
  static final Set<String> _bookedNotifSent = {};
  static final Set<String> _pendingNotifSent = {};
  static DateTime? _lastKnownBookedAt;

  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _dialogShowing = false;
    _currentSeatId = null;
    _bookedNotifSent.clear();
    _pendingNotifSent.clear();
    _lastKnownBookedAt = null;
  }

  static Future<void> _check() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final now = DateTime.now();
      final bookedSeats = await FirebaseFirestore.instance
          .collection('seats')
          .where('bookedBy', isEqualTo: user.uid)
          .get();

      for (var doc in bookedSeats.docs) {
        final data = doc.data();
        final bookedAt = data['bookedAt'] as Timestamp?;
        if (bookedAt == null) continue;

        final expiresAt = bookedAt.toDate().add(const Duration(minutes: 4));
        final secs = expiresAt.difference(now).inSeconds;

        if (_lastKnownBookedAt != bookedAt.toDate()) {
          _bookedNotifSent.clear();
          _lastKnownBookedAt = bookedAt.toDate();
        }

        if (secs <= 120 && secs > 0 && !_bookedNotifSent.contains(doc.id)) {
          _bookedNotifSent.add(doc.id);
          await FirebaseFirestore.instance.collection('notifications').add({
            'title': 'Session Expiring',
            'message':
                'Your session at ${data['buildingName'] ?? ''}, ${data['roomName'] ?? ''} (Seat #${data['seatNumber']?.toString() ?? doc.id}) will expire in 2 minutes.',
            'timestamp': FieldValue.serverTimestamp(),
            'userId': user.uid,
          });
        }

        if (secs <= 60 && secs > 0 && !_dialogShowing) {
          _dialogShowing = true;
          _currentSeatId = doc.id;
          _showDialog(
            doc.id,
            data,
            expiresAt,
            data['seatNumber']?.toString() ?? doc.id,
            data['buildingName'] ?? '',
            data['roomName'] ?? '',
          );
        }

        if (secs <= 0 && _dialogShowing && _currentSeatId == doc.id) {
          _dialogShowing = false;
          _currentSeatId = null;
          _countdownTimer?.cancel();
          _releaseSeat(doc.id);
        }
      }

      // Check Pending Seats
      final pendingSeats = await FirebaseFirestore.instance
          .collection('seats')
          .where('pendingBy', isEqualTo: user.uid)
          .get();

      if (pendingSeats.docs.isEmpty) {
        _pendingNotifSent.clear();
      }

      for (var doc in pendingSeats.docs) {
        final data = doc.data();
        final pendingAt = data['pendingAt'] as Timestamp?;
        if (pendingAt == null) continue;

        final expiresAt = pendingAt.toDate().add(const Duration(minutes: 10));
        final secs = expiresAt.difference(now).inSeconds;

        if (secs <= 60 && secs > 0 && !_pendingNotifSent.contains(doc.id)) {
          _pendingNotifSent.add(doc.id);
          await FirebaseFirestore.instance.collection('notifications').add({
            'title': 'Reservation Expiring',
            'message':
                'Your reserved seat (#${data['seatNumber']?.toString() ?? doc.id}) will expire in 1 minute. Please confirm your booking to secure it.',
            'timestamp': FieldValue.serverTimestamp(),
            'userId': user.uid,
          });
        }
      }
    } catch (_) {}
  }

  static void _showDialog(
    String seatId,
    Map<String, dynamic> data,
    DateTime expiresAt,
    String seatNumber,
    String buildingName,
    String roomName,
  ) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    int remainingSecs = expiresAt.difference(DateTime.now()).inSeconds;
    if (remainingSecs <= 0) {
      _releaseSeat(seatId);
      return;
    }

    _countdownNotifier.value = remainingSecs;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      int secs = expiresAt.difference(DateTime.now()).inSeconds;
      _countdownNotifier.value = secs;
      if (secs <= 0) {
        timer.cancel();
        if (_dialogShowing) {
          _dialogShowing = false;
          _currentSeatId = null;
          _releaseSeat(seatId);
        }
      }
    });

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExpiryDialog(
        seatNumber: seatNumber,
        buildingName: buildingName,
        roomName: roomName,
        countdownNotifier: _countdownNotifier,
      ),
    ).then((result) {
      _countdownTimer?.cancel();
      _dialogShowing = false;
      _currentSeatId = null;

      if (result == true) {
        _extendSeat(seatId);
      } else if (result == false) {
        _releaseSeat(seatId);
      } else {
        _releaseSeat(seatId);
      }
    });
  }

  static Future<void> _extendSeat(String seatId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('seats').doc(seatId).update({
        'bookedAt': Timestamp.fromDate(DateTime.now()),
      });
      await NotificationService.clearUserNotifications(user.uid);

      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session extended by 4 minutes!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {}
  }

  static Future<void> _releaseSeat(String seatId) async {
    final user = FirebaseAuth.instance.currentUser;
    try {
      await FirebaseFirestore.instance.collection('seats').doc(seatId).update({
        'status': 'available',
        'bookedBy': FieldValue.delete(),
        'bookedAt': FieldValue.delete(),
        'pendingBy': FieldValue.delete(),
        'pendingAt': FieldValue.delete(),
      });
      if (user != null) {
        await NotificationService.clearUserNotifications(user.uid);
      }
    } catch (_) {}
  }
}
