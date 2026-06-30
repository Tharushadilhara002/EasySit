import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'qr_scanner_screen.dart';
import 'find_seats_screen.dart';
import 'seat_booking_screen.dart';
import 'session_screen.dart';
import '../services/notification_service.dart';
import '../widgets/app_bottom_nav.dart';
import 'profile_screen.dart';
import 'notification_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  int _currentIndex = 0;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;
  String _userName = 'Student';

  @override
  void initState() {
    super.initState();
    _getUserName();
    _checkAndReleaseExpiredBookings();
  }

  @override
  void dispose() {
    _bookedListener?.cancel();
    super.dispose();
  }

  StreamSubscription<QuerySnapshot>? _bookedListener;

  Future<void> _openNotificationScreen() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    );
    if (result == 'session_expiring') {
      await _showSessionActionDialog();
    } else if (result == 'view_session') {
      _onNavTab(2);
    }
  }

  Future<void> _showSessionActionDialog() async {
    if (_user == null) return;

    final snapshot = await _firestore
        .collection('seats')
        .where('bookedBy', isEqualTo: _user.uid)
        .get();

    if (snapshot.docs.isEmpty) {
      final pendingSnapshot = await _firestore
          .collection('seats')
          .where('pendingBy', isEqualTo: _user.uid)
          .get();
      if (pendingSnapshot.docs.isNotEmpty && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SessionScreen()),
        );
      }
      return;
    }

    final doc = snapshot.docs.first;
    final data = doc.data();
    final seatNumber = data['seatNumber']?.toString() ?? doc.id;
    final buildingName = data['buildingName'] ?? '';
    final roomName = data['roomName'] ?? '';

    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Expiring'),
        content: Text(
          'Your session for Seat $seatNumber at $buildingName - $roomName will expire soon.\n\n'
          'Would you like to extend your session by 4 minutes or release the seat now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'release'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Release Seat'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'extend'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Extend 4 Minutes'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (action == 'extend') {
      await _firestore.collection('seats').doc(doc.id).update({
        'bookedAt': Timestamp.fromDate(DateTime.now()),
      });
      await NotificationService.clearUserNotifications(_user.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session extended by 4 minutes!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (action == 'release') {
      await _firestore.collection('seats').doc(doc.id).update({
        'status': 'available',
        'bookedBy': FieldValue.delete(),
        'bookedAt': FieldValue.delete(),
        'pendingBy': FieldValue.delete(),
        'pendingAt': FieldValue.delete(),
      });
      await NotificationService.cancelAllNotifications();
      await NotificationService.clearUserNotifications(_user.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seat released successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _getUserName() async {
    if (_user == null) return;
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(_user.uid).get();
      if (userDoc.exists) {
        setState(() {
          _userName = userDoc.get('fullName') ?? 'Student';
        });
      }
    } catch (_) {}
  }

  String _getGreeting() {
    int hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTabSelected: _onNavTab,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      toolbarHeight: 85, // Increased height
      elevation: 0,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(30),
        ),
      ),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(30),
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getGreeting(),
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          Text(
            _userName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
      actions: [
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('notifications')
              .where('userId', whereIn: ['all', _user?.uid ?? ''])
              .snapshots(),
          builder: (context, snapshot) {
            int count = 0;
            if (snapshot.hasData) {
              count = snapshot.data!.docs.length;
            }
            return Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications, color: Colors.white),
                    onPressed: _openNotificationScreen,
                  ),
                  if (count > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _checkAndReleaseExpiredBookings() async {
    if (_user == null) return;
    try {
      final now = DateTime.now();

      QuerySnapshot bookedSeats = await _firestore
          .collection('seats')
          .where('bookedBy', isEqualTo: _user.uid)
          .get();

      for (var doc in bookedSeats.docs) {
        var data = doc.data() as Map<String, dynamic>;
        Timestamp? bookedAt = data['bookedAt'] as Timestamp?;
        if (bookedAt != null) {
          DateTime expiresAt = bookedAt.toDate().add(const Duration(minutes: 4));
          if (now.isAfter(expiresAt)) {
            await _firestore.collection('seats').doc(doc.id).update({
              'status': 'available',
              'bookedBy': FieldValue.delete(),
              'bookedAt': FieldValue.delete(),
              'pendingBy': FieldValue.delete(),
              'pendingAt': FieldValue.delete(),
            });
          }
        }
      }

      QuerySnapshot pendingSeats = await _firestore
          .collection('seats')
          .where('pendingBy', isEqualTo: _user.uid)
          .get();

      for (var doc in pendingSeats.docs) {
        var data = doc.data() as Map<String, dynamic>;
        Timestamp? pendingAt = data['pendingAt'] as Timestamp?;
        if (pendingAt != null) {
          DateTime expiresAt = pendingAt.toDate().add(const Duration(minutes: 10));
          if (DateTime.now().isAfter(expiresAt)) {
            await _firestore.collection('seats').doc(doc.id).update({
              'status': 'available',
              'pendingBy': FieldValue.delete(),
              'pendingAt': FieldValue.delete(),
            });
          }
        }
      }
    } catch (_) {}
  }

  void _onNavTab(int index) {
    if (index == _currentIndex) return;
    if (index == 0) {
      setState(() => _currentIndex = index);
      return;
    }
    Widget screen;
    switch (index) {
      case 1: screen = const QrScannerScreen(); break;
      case 2: screen = const SessionScreen(); break;
      case 3: screen = const ProfileScreen(); break;
      default: return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // ========== Quick Actions ==========
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Center(
            child: SizedBox(
              width: double.infinity,
              child: _buildQuickActionCard(
                icon: Icons.search,
                title: 'Find Seats',
                subtitle: 'Browse library areas and book a seat',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FindSeatsScreen(),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 30),

        // ========== Available Areas Section ==========
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.dashboard, color: Color(0xFF1A237E), size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Available Areas',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FindSeatsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('View all'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF3949AB)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ========== Area Cards ==========
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('buildings').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No buildings available yet.'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var buildingDoc = snapshot.data!.docs[index];
                    var buildingData =
                        buildingDoc.data() as Map<String, dynamic>;
                    String buildingId = buildingDoc.id;
                    String buildingName = buildingData['name'] ?? 'Unnamed';

                    return _buildBuildingCard(buildingId, buildingName);
                  },
                );
              },
            ),
          ),
        ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3949AB).withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildingCard(String buildingId, String buildingName) {
    return StreamBuilder<QuerySnapshot>(
      stream:
          _firestore
              .collection('floors')
              .where('buildingId', isEqualTo: buildingId)
              .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Card(
            color: Colors.blue.shade50,
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.business, color: Colors.grey),
              ),
              title: Text(buildingName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('No floors available'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            ),
          );
        }

        List<Future<List<Map<String, dynamic>>>> roomFutures = [];
        for (var floorDoc in snapshot.data!.docs) {
          String floorId = floorDoc.id;
          var floorData = floorDoc.data() as Map<String, dynamic>;
          String floorName = floorData['name'] ?? 'Floor';

          roomFutures.add(_getRoomsForFloor(floorId, floorName, buildingName));
        }

        return FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: Future.wait(roomFutures),
          builder: (context, roomSnapshot) {
            if (roomSnapshot.connectionState == ConnectionState.waiting) {
              return Card(
                color: Colors.blue.shade50,
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.business, color: Color(0xFF3949AB)),
                  ),
                  title: Text(buildingName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Loading...'),
                ),
              );
            }

            if (roomSnapshot.hasError || roomSnapshot.data == null) {
              return const SizedBox.shrink();
            }

            var rooms =
                roomSnapshot.data!
                    .expand((x) => x)
                    .where((r) => r['roomId'] != '')
                    .toList();
            if (rooms.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              children: [
                ...rooms.map(
                  (room) => Card(
                    color: Colors.blue.shade50,
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 3,
                    shadowColor: Colors.black.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        if ((room['availableSeats'] ?? 0) > 0) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => SeatBookingScreen(
                                    roomId: room['roomId'],
                                    roomName: room['roomName'],
                                    buildingName: room['buildingName'],
                                    floorName: room['floorName'],
                                  ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No seats available in this room'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF3949AB), Color(0xFF5C6BC0)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.meeting_room,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${room['roomName']}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${room['floorName']}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${room['buildingName']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (room['availableSeats'] ?? 0) > 0
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.event_seat,
                                    size: 14,
                                    color:
                                        (room['availableSeats'] ?? 0) > 0
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${room['availableSeats']}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          (room['availableSeats'] ?? 0) > 0
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getRoomsForFloor(
    String floorId,
    String floorName,
    String buildingName,
  ) async {
    try {
      QuerySnapshot roomsSnapshot =
          await _firestore
              .collection('rooms')
              .where('floorId', isEqualTo: floorId)
              .get();

      if (roomsSnapshot.docs.isEmpty) {
        return [];
      }

      List<Map<String, dynamic>> results = [];
      for (var roomDoc in roomsSnapshot.docs) {
        var roomData = roomDoc.data() as Map<String, dynamic>;
        String roomId = roomDoc.id;
        String roomName = roomData['name'] ?? 'Room';

        QuerySnapshot seatsSnapshot =
            await _firestore
                .collection('seats')
                .where('roomId', isEqualTo: roomId)
                .where('status', isEqualTo: 'available')
                .get();

        int availableSeats = seatsSnapshot.docs.length;

        results.add({
          'floorId': floorId,
          'floorName': floorName,
          'buildingName': buildingName,
          'roomName': roomName,
          'availableSeats': availableSeats,
          'roomId': roomId,
        });
      }

      return results;
    } catch (e) {
      return [];
    }
  }
}
