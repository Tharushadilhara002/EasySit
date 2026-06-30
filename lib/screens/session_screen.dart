import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../widgets/app_bottom_nav.dart';
import 'student_home_screen.dart';
import 'qr_scanner_screen.dart';
import 'profile_screen.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  static bool isActive = false;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  Map<String, dynamic>? _activeBooking;
  Timer? _timer;
  int _remainingSeconds = 0;
  String _bookingStatus = '';
  bool _isLoading = true;

  StreamSubscription<QuerySnapshot>? _bookedSub;
  StreamSubscription<QuerySnapshot>? _pendingSub;

  @override
  void initState() {
    super.initState();
    SessionScreen.isActive = true;
    _listenActiveBooking();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bookedSub?.cancel();
    _pendingSub?.cancel();
    SessionScreen.isActive = false;
    super.dispose();
  }

  void _listenActiveBooking() {
    if (_user == null) {
      setState(() => _isLoading = false);
      return;
    }

    _bookedSub?.cancel();
    _bookedSub = _firestore
        .collection('seats')
        .where('bookedBy', isEqualTo: _user.uid)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            _pendingSub?.cancel();
            _onBookingFound(snapshot.docs.first, 'booked');
          } else {
            _pendingSub?.cancel();
            _pendingSub = _firestore
                .collection('seats')
                .where('pendingBy', isEqualTo: _user.uid)
                .snapshots()
                .listen((pendingSnapshot) {
                  if (pendingSnapshot.docs.isNotEmpty) {
                    _onBookingFound(pendingSnapshot.docs.first, 'pending');
                  } else {
                    setState(() {
                      _activeBooking = null;
                      _bookingStatus = '';
                      _isLoading = false;
                    });
                    _timer?.cancel();
                  }
                });
          }
        });
  }

  Future<void> _onBookingFound(QueryDocumentSnapshot doc, String status) async {
    var data = doc.data() as Map<String, dynamic>;

    _timer?.cancel();

    if (status == 'pending') {
      Timestamp? pendingAt = data['pendingAt'] as Timestamp?;
      if (pendingAt != null) {
        DateTime expiresAt = pendingAt.toDate().add(const Duration(minutes: 10));
        _startTimerForPending(doc.id, data['seatNumber']?.toString() ?? '?', expiresAt);
      }
      setState(() {
        _activeBooking = {
          'docId': doc.id,
          'seatId': doc.id,
          'seatNumber': data['seatNumber'] ?? '?',
          'roomName': '',
          'floorName': '',
          'buildingName': '',
          'status': 'pending',
          'zone': data['zone'] ?? 'Quiet Zone',
        };
        _bookingStatus = 'pending';
        _isLoading = false;
      });
    } else if (status == 'booked') {
      Timestamp? bookedAt = data['bookedAt'] as Timestamp?;
      DateTime sessionEnd;
      if (bookedAt != null) {
        sessionEnd = bookedAt.toDate().add(const Duration(minutes: 4));
      } else {
        sessionEnd = DateTime.now().add(const Duration(minutes: 4));
      }
      _startTimerForBooked(
        doc.id,
        sessionEnd,
        data['seatNumber'] ?? '?',
        '',
        '',
      );
      setState(() {
        _activeBooking = {
          'docId': doc.id,
          'seatId': doc.id,
          'seatNumber': data['seatNumber'] ?? '?',
          'roomName': '',
          'floorName': '',
          'buildingName': '',
          'status': 'booked',
          'zone': data['zone'] ?? 'Quiet Zone',
        };
        _bookingStatus = 'booked';
        _isLoading = false;
      });
    }

    String roomId = data['roomId'] ?? '';
    String roomName = '';
    String floorName = '';
    String buildingName = '';
    if (roomId.isNotEmpty) {
      DocumentSnapshot roomDoc =
          await _firestore.collection('rooms').doc(roomId).get();
      var roomData = roomDoc.data() as Map<String, dynamic>?;
      roomName = roomData?['name'] ?? 'Room';
      String floorId = roomData?['floorId'] ?? '';
      if (floorId.isNotEmpty) {
        DocumentSnapshot floorDoc =
            await _firestore.collection('floors').doc(floorId).get();
        var floorData = floorDoc.data() as Map<String, dynamic>?;
        floorName = floorData?['name'] ?? 'Floor';
        String buildingId = floorData?['buildingId'] ?? '';
        if (buildingId.isNotEmpty) {
          DocumentSnapshot buildingDoc =
              await _firestore.collection('buildings').doc(buildingId).get();
          var buildingData = buildingDoc.data() as Map<String, dynamic>?;
          buildingName = buildingData?['name'] ?? 'Building';
  }
}

    if (mounted) {
      setState(() {
        if (_activeBooking != null) {
          _activeBooking!['roomName'] = roomName;
          _activeBooking!['floorName'] = floorName;
          _activeBooking!['buildingName'] = buildingName;
        }
      });
    }
  }
}

  void _startTimerForPending(String seatId, String seatNumber, DateTime expiresAt) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      int secs = expiresAt.difference(DateTime.now()).inSeconds;
      if (secs <= 0) {
        timer.cancel();
        _releaseExpired(seatId);
      } else {
        setState(() => _remainingSeconds = secs);
      }
    });
    setState(
      () => _remainingSeconds = expiresAt.difference(DateTime.now()).inSeconds,
    );
  }

  void _startTimerForBooked(
    String seatId,
    DateTime sessionEnd,
    String seatNumber,
    String buildingName,
    String roomName,
  ) {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      int secs = sessionEnd.difference(DateTime.now()).inSeconds;

      if (secs <= 0) {
        timer.cancel();
        _autoReleaseSeat(seatId);
        return;
      }

      setState(() => _remainingSeconds = secs);
    });

    setState(
      () => _remainingSeconds = sessionEnd.difference(DateTime.now()).inSeconds,
    );
  }

  Future<void> _releaseSeat(String seatId) async {
    _timer?.cancel();
    try {
      await _firestore.collection('seats').doc(seatId).update({
        'status': 'available',
        'bookedBy': FieldValue.delete(),
        'bookedAt': FieldValue.delete(),
        'pendingBy': FieldValue.delete(),
        'pendingAt': FieldValue.delete(),
      });
      await NotificationService.cancelAllNotifications();
      if (_user != null) {
        await NotificationService.clearUserNotifications(_user.uid);
      }
      if (mounted) {
        setState(() {
          _activeBooking = null;
          _bookingStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seat released successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error releasing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _autoReleaseSeat(String seatId) async {
    await _firestore.collection('seats').doc(seatId).update({
      'status': 'available',
      'bookedBy': FieldValue.delete(),
      'bookedAt': FieldValue.delete(),
      'pendingBy': FieldValue.delete(),
      'pendingAt': FieldValue.delete(),
    });
    _timer?.cancel();
    await NotificationService.cancelAllNotifications();
    if (_user != null) {
      await NotificationService.clearUserNotifications(_user.uid);
    }
    if (mounted) {
      setState(() {
        _activeBooking = null;
        _bookingStatus = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Session expired. Seat released automatically.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _releaseExpired(String seatId) async {
    await _firestore.collection('seats').doc(seatId).update({
      'status': 'available',
      'pendingBy': FieldValue.delete(),
      'pendingAt': FieldValue.delete(),
    });
    await NotificationService.cancelAllNotifications();
    if (_user != null) {
      await NotificationService.clearUserNotifications(_user.uid);
    }
    if (mounted) {
      setState(() {
        _activeBooking = null;
        _bookingStatus = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Reservation expired. Seat released.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _manualReleaseSeat() async {
    if (_activeBooking == null) return;
    await _releaseSeat(_activeBooking!['seatId']);
  }

  String _formatTime(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onNavTab(int index) {
    if (index == 2) return;
    Widget screen;
    switch (index) {
      case 0: screen = const StudentHomeScreen(); break;
      case 1: screen = const QrScannerScreen(); break;
      case 3: screen = const ProfileScreen(); break;
      default: return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 70,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        leadingWidth: 70,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                ]
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.black),
                onPressed: () {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                },
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My session', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            Text('Your seat is now active', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: const [],
      ),
      body: _buildBody(),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 2,
        onTabSelected: _onNavTab,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF2ECA7F)));
    }

    if (_activeBooking == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_seat, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No Active Session',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Find and book a seat to start your session',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    bool isPending = _bookingStatus == 'pending';
    bool isBooked = _bookingStatus == 'booked';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Column(
        children: [
          // ========== Success Graphic ==========
          Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F7F0), // Very light green
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 85,
                    height: 85,
                    decoration: const BoxDecoration(
                      color: Color(0xFFC3EEDB), // Light green
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 55,
                    height: 55,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2ECA7F), // Bright green
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x662ECA7F), blurRadius: 15, offset: Offset(0, 5)),
                      ]
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 36),
                  ),
                  // Sparkles
                  const Positioned(top: 5, left: 10, child: Icon(Icons.star_border, color: Color(0xFF2ECA7F), size: 18)),
                  const Positioned(bottom: 25, left: 0, child: Icon(Icons.star_border, color: Color(0xFF2ECA7F), size: 22)),
                  const Positioned(top: 25, right: 0, child: Icon(Icons.star_border, color: Color(0xFF2ECA7F), size: 16)),
                  const Positioned(bottom: 15, right: -10, child: Icon(Icons.star_border, color: Color(0xFF2ECA7F), size: 20)),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                isPending ? "Pending Confirmation" : "You're all set",
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                isPending ? "Please scan the QR on the seat" : "Your session has started successfully",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // ========== Circular Timer ==========
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 260,
                height: 260,
                child: CircularProgressIndicator(
                  value: _remainingSeconds > 0 ? _remainingSeconds / (isPending ? (10 * 60) : (4 * 60)) : 0, 
                  strokeWidth: 12,
                  backgroundColor: const Color(0xFFF2F2F2),
                  color: const Color(0xFF3949AB), // Blue progress
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    isPending ? 'TIME REMAINING' : 'SESSION TIME',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTime(_remainingSeconds),
                    style: const TextStyle(
                      fontSize: 54, 
                      fontWeight: FontWeight.bold, 
                      color: Color(0xFF1A237E), // Dark blue text
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'TOTAL DURATION', 
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, letterSpacing: 1.1),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isPending ? '10 mins' : '4 mins', 
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3949AB)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 40),

          // ========== Seat Details Card ==========
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF2FAF5), // Very light green tint
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                // Left side icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  child: const Icon(Icons.chair_alt, color: Color(0xFF2ECA7F), size: 36),
                ),
                const SizedBox(width: 16),
                
                // Details
                Expanded(
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Seat ID', style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(
                            _activeBooking!['seatNumber'] ?? 'A03',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2ECA7F)),
                          ),
                        ],
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: Colors.grey.shade300,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _activeBooking!['zone'] ?? 'Quiet Zone',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_activeBooking!['buildingName'] ?? 'Admin'} • ${_activeBooking!['floorName'] ?? 'Floor 6'}', 
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ========== Action Buttons ==========
          const SizedBox(height: 24),
          if (isPending)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C6FFF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Scan QR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _releaseSeat(_activeBooking!['seatId']),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          else if (isBooked)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24), // Match upper card radius
                border: Border.all(color: Colors.red.shade200, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.05), // Softer shadow
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _manualReleaseSeat,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16), // Tighter padding for height match
                    child: Column(
                      children: [
                        Icon(Icons.output_rounded, color: Colors.red.shade500, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          'Release Seat',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'End session and make seat available',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

