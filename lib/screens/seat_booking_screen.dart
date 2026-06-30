import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'qr_scanner_screen.dart';
import 'session_screen.dart';
import 'student_home_screen.dart';
import 'profile_screen.dart';
import '../widgets/app_bottom_nav.dart';

class SeatBookingScreen extends StatefulWidget {
  final String roomId;
  final String roomName;
  final String buildingName;
  final String floorName;
  final VoidCallback? onBookingComplete;

  const SeatBookingScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.buildingName,
    required this.floorName,
    this.onBookingComplete,
  });

  @override
  State<SeatBookingScreen> createState() => _SeatBookingScreenState();
}

class _SeatBookingScreenState extends State<SeatBookingScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> _hasExistingBooking(String uid) async {
    QuerySnapshot pending = await _firestore
        .collection('seats')
        .where('pendingBy', isEqualTo: uid)
        .limit(1)
        .get();
    if (pending.docs.isNotEmpty) return true;
    QuerySnapshot booked = await _firestore
        .collection('seats')
        .where('bookedBy', isEqualTo: uid)
        .limit(1)
        .get();
    if (booked.docs.isNotEmpty) return true;
    return false;
  }

  Future<void> _reserveSeat(String seatId, String seatNumber) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login first'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    bool hasBooking = await _hasExistingBooking(user.uid);
    if (hasBooking) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have an active booking. Cancel it first.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reserve Seat'),
        content: Text('You have 10 minutes to scan the QR code at Seat #$seatNumber to confirm booking.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Reserve'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore.collection('seats').doc(seatId).update({
        'status': 'pending',
        'pendingBy': user.uid,
        'pendingAt': Timestamp.fromDate(DateTime.now()),
        'buildingName': widget.buildingName,
        'roomName': widget.roomName,
      });

      if (mounted) {
        if (widget.onBookingComplete != null) {
          widget.onBookingComplete!();
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SessionScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _cancelPending(String seatId, String seatNumber) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Reservation'),
        content: Text('Release seat #$seatNumber?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore.collection('seats').doc(seatId).update({
        'status': 'available',
        'pendingBy': FieldValue.delete(),
        'pendingAt': FieldValue.delete(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Seat #$seatNumber released.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _goScan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
  }

  void _onNavTab(int index) {
    if (index == 0) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const StudentHomeScreen()),
        (route) => false,
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomName),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR',
            onPressed: _goScan,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${widget.buildingName} • ${widget.floorName}',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F7FA), Colors.white],
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('seats')
            .where('roomId', isEqualTo: widget.roomId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_seat, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No seats available in this room',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          var seats = snapshot.data!.docs;
          seats.sort((a, b) {
            var aNum = int.tryParse((a.data() as Map)['seatNumber'] ?? '0') ?? 0;
            var bNum = int.tryParse((b.data() as Map)['seatNumber'] ?? '0') ?? 0;
            return aNum.compareTo(bNum);
          });

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _legendItem(Colors.green.shade600, 'Available'),
                    const SizedBox(width: 12),
                    _legendItem(Colors.amber.shade600, 'Pending'),
                    const SizedBox(width: 12),
                    _legendItem(Colors.red.shade600, 'Booked'),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.9,
                        ),
                    itemCount: seats.length,
                    itemBuilder: (context, index) {
                      var seatData = seats[index].data() as Map<String, dynamic>;
                      String seatId = seats[index].id;
                      String seatNumber = seatData['seatNumber'] ?? '?';
                      String status = seatData['status'] ?? 'available';
                      String? pendingBy = seatData['pendingBy'] as String?;
                      String? bookedBy = seatData['bookedBy'] as String?;
                      User? user = FirebaseAuth.instance.currentUser;
                      String myUid = user?.uid ?? '';

                      Color bgColor;
                      Color borderColor;
                      Color iconColor;
                      Color textColor;
                      bool isMine = false;
                      VoidCallback? onTap;

                      if (status == 'available') {
                        bgColor = Colors.green.shade50;
                        borderColor = Colors.green.shade400;
                        iconColor = Colors.green.shade600;
                        textColor = Colors.green.shade800;
                        onTap = () => _reserveSeat(seatId, seatNumber);
                      } else if (status == 'pending') {
                        isMine = pendingBy == myUid;
                        bgColor = isMine ? Colors.amber.shade50 : Colors.grey.shade100;
                        borderColor = isMine ? Colors.amber.shade400 : Colors.grey.shade400;
                        iconColor = isMine ? Colors.amber.shade600 : Colors.grey;
                        textColor = isMine ? Colors.amber.shade800 : Colors.grey.shade600;
                        if (isMine) {
                          onTap = () => _cancelPending(seatId, seatNumber);
                        }
                      } else {
                        isMine = bookedBy == myUid;
                        bgColor = isMine ? Colors.blue.shade50 : Colors.red.shade50;
                        borderColor = isMine ? Colors.blue.shade400 : Colors.red.shade400;
                        iconColor = isMine ? Colors.blue.shade600 : Colors.red.shade600;
                        textColor = isMine ? Colors.blue.shade800 : Colors.red.shade800;
                      }

                      return GestureDetector(
                        onTap: onTap,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: borderColor.withValues(alpha: 0.15),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isMine ? Icons.person : Icons.event_seat,
                                size: 26,
                                color: iconColor,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                seatNumber,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              if (isMine && status == 'pending')
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Mine',
                                    style: TextStyle(fontSize: 8, color: Colors.amber.shade800),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0,
        onTabSelected: _onNavTab,
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color, width: 2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
