import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'session_screen.dart';
import 'student_home_screen.dart';
import 'profile_screen.dart';

import '../widgets/app_bottom_nav.dart';
import '../services/notification_service.dart';

class QrScannerScreen extends StatefulWidget {
  final VoidCallback? onBookingComplete;

  const QrScannerScreen({super.key, this.onBookingComplete});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    final qrValue = barcode?.rawValue;
    if (qrValue == null || !qrValue.startsWith('SEAT:')) return;

    setState(() => _isProcessing = true);

    String seatId = qrValue.substring(5);
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showError('Please login first');
      return;
    }

    try {
      DocumentSnapshot seatDoc =
          await FirebaseFirestore.instance
              .collection('seats')
              .doc(seatId)
              .get();

      if (!seatDoc.exists) {
        _showError('Seat not found!');
        return;
      }

      var data = seatDoc.data() as Map<String, dynamic>;
      String roomId = data['roomId'] ?? '';
      String seatNumber = data['seatNumber'] ?? '?';
      String status = data['status'] ?? 'available';
      String? pendingBy = data['pendingBy'] as String?;

      // Get room details
      DocumentSnapshot roomDoc =
          await FirebaseFirestore.instance
              .collection('rooms')
              .doc(roomId)
              .get();
      String roomName =
          (roomDoc.data() as Map<String, dynamic>?)?['name'] ?? 'Unknown';
      String floorId =
          (roomDoc.data() as Map<String, dynamic>?)?['floorId'] ?? '';

      // Get floor and building details
      String floorName = '';
      String buildingName = '';
      if (floorId.isNotEmpty) {
        DocumentSnapshot floorDoc =
            await FirebaseFirestore.instance
                .collection('floors')
                .doc(floorId)
                .get();
        var floorData = floorDoc.data() as Map<String, dynamic>?;
        floorName = floorData?['name'] ?? 'Floor';
        String buildingId = floorData?['buildingId'] ?? '';

        if (buildingId.isNotEmpty) {
          DocumentSnapshot buildingDoc =
              await FirebaseFirestore.instance
                  .collection('buildings')
                  .doc(buildingId)
                  .get();
          var buildingData = buildingDoc.data() as Map<String, dynamic>?;
          buildingName = buildingData?['name'] ?? 'Building';
        }
      }

      if (!mounted) return;

      if (status == 'available') {
        _showDirectBookingDialog(
          seatId,
          seatNumber,
          roomName,
          buildingName,
          floorName,
        );
      } else if (status == 'pending') {
        if (pendingBy == user.uid) {
          // 🟢 Confirm Booking and Navigate to Session Screen
          _showConfirmBookingDialog(
            seatId,
            seatNumber,
            roomName,
            buildingName,
            floorName,
          );
        } else {
          _showError('Seat $seatNumber is reserved by another student.');
        }
      } else if (status == 'booked') {
        _showError('Seat $seatNumber is already booked!');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _showDirectBookingDialog(
    String seatId,
    String seatNumber,
    String roomName,
    String buildingName,
    String floorName,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Book This Seat?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seat #$seatNumber',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$buildingName • $floorName • $roomName',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your session will start immediately and last for 4 minutes.',
                          style: TextStyle(fontSize: 13, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _isProcessing = false);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _bookSeatDirect(
                    seatId,
                    seatNumber,
                    roomName,
                    buildingName,
                    floorName,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text(
                  'Book Now',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }

  // 🟢 Updated Confirm Booking Dialog (with Navigation)
  void _showConfirmBookingDialog(
    String seatId,
    String seatNumber,
    String roomName,
    String buildingName,
    String floorName,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Confirm Booking'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scan verified! Confirm booking for:'),
                const SizedBox(height: 8),
                Text(
                  'Seat #$seatNumber',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  '$buildingName • $floorName • $roomName',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your session will start now and last for 4 minutes.',
                          style: TextStyle(fontSize: 13, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _isProcessing = false);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _confirmBookingAndNavigate(
                    seatId,
                    seatNumber,
                    roomName,
                    buildingName,
                    floorName,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text(
                  'Confirm & Start',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }

  Future<bool> _hasExistingBooking(String uid) async {
    QuerySnapshot pending =
        await FirebaseFirestore.instance
            .collection('seats')
            .where('pendingBy', isEqualTo: uid)
            .limit(1)
            .get();
    if (pending.docs.isNotEmpty) return true;
    QuerySnapshot booked =
        await FirebaseFirestore.instance
            .collection('seats')
            .where('bookedBy', isEqualTo: uid)
            .limit(1)
            .get();
    if (booked.docs.isNotEmpty) return true;
    return false;
  }

  Future<void> _bookSeatDirect(
    String seatId,
    String seatNumber,
    String roomName,
    String buildingName,
    String floorName,
  ) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Please login first');
      return;
    }
    bool hasBooking = await _hasExistingBooking(user.uid);
    if (hasBooking) {
      _showError('You already have an active booking. Cancel it first.');
      return;
    }
    try {
      DocumentSnapshot seatDoc =
          await FirebaseFirestore.instance
              .collection('seats')
              .doc(seatId)
              .get();
      if (!seatDoc.exists) {
        _showError('Seat no longer exists.');
        return;
      }
      var data = seatDoc.data() as Map<String, dynamic>;
      if (data['status'] != 'available') {
        _showError('Seat is no longer available.');
        return;
      }

      DateTime now = DateTime.now();
      await FirebaseFirestore.instance.collection('seats').doc(seatId).update({
        'status': 'booked',
        'bookedBy': user.uid,
        'bookedAt': Timestamp.fromDate(now),
        'buildingName': buildingName,
        'roomName': roomName,
      });

      await NotificationService.clearUserNotifications(user.uid);

      if (mounted) {
        _showSuccessPopupAndNavigate();
      }
    } catch (e) {
      _showError('Booking failed: $e');
    }
  }

  // 🟢 Confirm booking from pending reservation
  Future<void> _confirmBookingAndNavigate(
    String seatId,
    String seatNumber,
    String roomName,
    String buildingName,
    String floorName,
  ) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Please login first');
      return;
    }

    try {
      // 1. Check if seat is still pending and not expired
      DocumentSnapshot seatDoc =
          await FirebaseFirestore.instance
              .collection('seats')
              .doc(seatId)
              .get();

      if (!seatDoc.exists) {
        _showError('Seat no longer exists.');
        return;
      }

      var data = seatDoc.data() as Map<String, dynamic>;
      Timestamp? pendingAt = data['pendingAt'] as Timestamp?;

      if (pendingAt != null) {
        DateTime expiresAt = pendingAt.toDate().add(
          const Duration(minutes: 10),
        );
        if (DateTime.now().isAfter(expiresAt)) {
          await FirebaseFirestore.instance
              .collection('seats')
              .doc(seatId)
              .update({
                'status': 'available',
                'pendingBy': FieldValue.delete(),
                'pendingAt': FieldValue.delete(),
              });
          if (mounted) {
            _showError(
              'Time expired! Reservation released. Please reserve again.',
            );
          }
          return;
        }
      }

      // 2. Update seat to 'booked'
      DateTime now = DateTime.now();
      await FirebaseFirestore.instance.collection('seats').doc(seatId).update({
        'status': 'booked',
        'bookedBy': user.uid,
        'bookedAt': Timestamp.fromDate(now),
        'pendingBy': FieldValue.delete(),
        'pendingAt': FieldValue.delete(),
        'buildingName': buildingName,
        'roomName': roomName,
      });

      await NotificationService.clearUserNotifications(user.uid);

      if (mounted) {
        _showSuccessPopupAndNavigate();
      }
    } catch (e) {
      _showError('Booking failed: $e');
    }
  }

  void _showSuccessPopupAndNavigate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 64,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Success!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your session has started.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Wait 4 seconds, then navigate
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        // Pop the dialog first
        Navigator.pop(context);
        
        if (widget.onBookingComplete != null) {
          widget.onBookingComplete!();
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SessionScreen()),
          );
        }
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _onNavTab(int index) {
    if (index == 1) return;
    Widget screen;
    switch (index) {
      case 0: screen = const StudentHomeScreen(); break;
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
      extendBody: true, // Lets the camera preview flow under the floating bottom nav
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 85,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
            ),
          ),
        ),
        title: const Text(
          'Scan QR Code',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              String errorMessage;
              switch (error.errorCode) {
                case MobileScannerErrorCode.permissionDenied:
                  errorMessage = 'Please grant camera permission in your device settings to scan QR codes.';
                  break;
                case MobileScannerErrorCode.unsupported:
                  errorMessage = 'This device does not support camera scanning.';
                  break;
                default:
                  errorMessage = 'Camera error: ${error.errorDetails?.message ?? error.errorCode.name}';
              }
              
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.camera_alt_outlined, size: 64, color: Colors.red.shade400),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Camera Access Needed',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        errorMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 1,
        onTabSelected: _onNavTab,
      ),
    );
  }
}
