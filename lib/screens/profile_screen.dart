import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import '../widgets/app_bottom_nav.dart';
import 'student_home_screen.dart';
import 'qr_scanner_screen.dart';
import 'session_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  String _fullName = '';
  String _email = '';
  String _phone = '';
  String _userType = 'Student';
  Map<String, dynamic>? _activeBooking;
  String _bookingStatus = '';

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  bool _isEditing = false;
  bool _isSaving = false;

  StreamSubscription<QuerySnapshot>? _bookedSub;
  StreamSubscription<QuerySnapshot>? _pendingSub;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _listenActiveBooking();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _bookedSub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (_user == null) return;
    try {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(_user.uid).get();
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        setState(() {
          _fullName = data['fullName'] ?? '';
              _email = data['email'] ?? _user.email ?? '';
          _phone = data['phone'] ?? '';
          _userType = data['userType'] ?? 'Student';
        });
        _nameCtrl.text = _fullName;
        _emailCtrl.text = _email;
        _phoneCtrl.text = _phone;
      }
    } catch (_) {}
  }

  void _listenActiveBooking() {
    if (_user == null) return;

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
            .listen((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            _onBookingFound(snapshot.docs.first, 'pending');
          } else if (mounted) {
            setState(() {
              _activeBooking = null;
              _bookingStatus = '';
            });
          }
        });
      }
    });
  }

  Future<void> _onBookingFound(QueryDocumentSnapshot doc, String status) async {
    var data = doc.data() as Map<String, dynamic>;
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
    }

    if (mounted) {
      setState(() {
        _activeBooking = {
          'docId': doc.id,
          'seatId': doc.id,
          'seatNumber': data['seatNumber'] ?? '?',
          'roomName': roomName,
          'floorName': floorName,
          'buildingName': buildingName,
          'status': status,
        };
        _bookingStatus = status;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_user == null) return;
    setState(() => _isSaving = true);
    try {
      await _firestore.collection('users').doc(_user.uid).update({
        'fullName': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      });
      setState(() {
        _fullName = _nameCtrl.text.trim();
        _email = _emailCtrl.text.trim();
        _phone = _phoneCtrl.text.trim();
        _isEditing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
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
    setState(() => _isSaving = false);
  }

  Future<void> _logout() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _onNavTab(int index) {
    if (index == 3) return;
    Widget screen;
    switch (index) {
      case 0: screen = const StudentHomeScreen(); break;
      case 1: screen = const QrScannerScreen(); break;
      case 2: screen = const SessionScreen(); break;
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        toolbarHeight: 80,
        elevation: 0,
        backgroundColor: const Color(0xFF1A237E), // Deep indigo theme
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUserInfoCard(),
            const SizedBox(height: 20),
            if (_activeBooking != null) _buildCurrentSession(),
            if (_activeBooking != null) const SizedBox(height: 20),
            _buildStats(),
            const SizedBox(height: 24),
            const Text(
              'Settings & Options',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
            ),
            const SizedBox(height: 12),
            _buildEditProfile(),
            const SizedBox(height: 12),
            _buildHelpAndSupport(),
            const SizedBox(height: 12),
            _buildAbout(),
            const SizedBox(height: 24),
            _buildLogout(),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 3,
        onTabSelected: _onNavTab,
      ),
    );
  }

  Widget _buildUserInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF3949AB), Color(0xFF1A237E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _fullName.isNotEmpty ? _fullName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fullName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _email,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _userType == 'Admin' ? Colors.purple.shade50 : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _userType == 'Admin' ? Colors.purple.shade200 : Colors.indigo.shade200,
                      )
                    ),
                    child: Text(
                      _userType,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _userType == 'Admin' ? Colors.purple.shade700 : Colors.indigo.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSession() {
    bool isPending = _bookingStatus == 'pending';
    return Container(
      decoration: BoxDecoration(
        color: isPending ? Colors.orange.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPending ? Colors.orange.shade200 : Colors.green.shade200,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPending ? Icons.timer_outlined : Icons.check_circle_outline,
                  size: 24,
                  color: isPending ? Colors.orange.shade700 : Colors.green.shade700,
                ),
                const SizedBox(width: 12),
                Text(
                  isPending ? 'Pending Reservation' : 'Active Session',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isPending ? Colors.orange.shade800 : Colors.green.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildDetailRow(Icons.event_seat_rounded, 'Seat', '#${_activeBooking!['seatNumber']}'),
                  const Divider(height: 16),
                  _buildDetailRow(Icons.business_rounded, 'Building', _activeBooking!['buildingName'] ?? ''),
                  const Divider(height: 16),
                  _buildDetailRow(Icons.layers_rounded, 'Floor', _activeBooking!['floorName'] ?? ''),
                  const Divider(height: 16),
                  _buildDetailRow(Icons.meeting_room_rounded, 'Room', _activeBooking!['roomName'] ?? ''),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildEditProfile() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ExpansionTile(
          collapsedIconColor: Colors.grey.shade400,
          iconColor: const Color(0xFF1A237E),
          title: const Text(
            'Edit Profile',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E)),
          ),
          subtitle: Text('Update your personal details', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
            child: Icon(Icons.edit_rounded, color: Colors.blue.shade600, size: 22),
          ),
          initiallyExpanded: _isEditing,
          onExpansionChanged: (expanded) {
            setState(() => _isEditing = expanded);
          },
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  const Divider(height: 24),
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      labelStyle: TextStyle(color: Colors.grey.shade600),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2)),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      labelStyle: TextStyle(color: Colors.grey.shade600),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2)),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      labelStyle: TextStyle(color: Colors.grey.shade600),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2)),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.event_seat, size: 28, color: Colors.blue.shade600),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('seats')
                        .where('bookedBy', isEqualTo: _user?.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      int count = snapshot.data?.docs.length ?? 0;
                      return Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Completed\nSessions',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Container(height: 60, width: 1.5, color: Colors.grey.shade200),
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.access_time_filled, size: 28, color: Colors.orange.shade600),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('seats')
                        .where('bookedBy', isEqualTo: _user?.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      int totalMinutes = 0;
                      if (snapshot.hasData) {
                        for (var doc in snapshot.data!.docs) {
                          var data = doc.data() as Map<String, dynamic>;
                          Timestamp? bookedAt = data['bookedAt'] as Timestamp?;
                          if (bookedAt != null) {
                            Duration diff = DateTime.now().difference(bookedAt.toDate());
                            totalMinutes += diff.inMinutes;
                          }
                        }
                      }
                      int hours = totalMinutes ~/ 60;
                      return Text(
                        '$hours',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total\nHours',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpAndSupport() {
    return _buildSettingsTile(
      icon: Icons.help_outline_rounded,
      iconColor: Colors.blue.shade600,
      bgColor: Colors.blue.shade50,
      title: 'Help & Support',
      subtitle: 'Contact us for assistance',
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Help & Support', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('For assistance, please contact:'),
                SizedBox(height: 8),
                Text('Email: support@easysit.app', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Phone: 0713393669', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAbout() {
    return _buildSettingsTile(
      icon: Icons.info_outline_rounded,
      iconColor: Colors.indigo.shade600,
      bgColor: Colors.indigo.shade50,
      title: 'About EasySit',
      subtitle: 'Version 1.0.0',
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('About EasySit', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EasySit is a smart seat booking system for students.', style: TextStyle(fontSize: 14)),
                SizedBox(height: 12),
                Text('Version: 1.0.0', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Platform: Mobile', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Developer: EasySit Team', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogout() {
    return _buildSettingsTile(
      icon: Icons.logout_rounded,
      iconColor: Colors.red.shade600,
      bgColor: Colors.red.shade50,
      title: 'Logout',
      titleColor: Colors.red.shade600,
      subtitle: 'Sign out of your account',
      onTap: _logout,
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: titleColor ?? const Color(0xFF1A237E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
