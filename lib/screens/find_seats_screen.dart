import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'seat_booking_screen.dart';
import 'student_home_screen.dart';
import 'qr_scanner_screen.dart';
import 'session_screen.dart';
import 'profile_screen.dart';
import '../widgets/app_bottom_nav.dart';

class FindSeatsScreen extends StatefulWidget {
  const FindSeatsScreen({super.key});

  @override
  State<FindSeatsScreen> createState() => _FindSeatsScreenState();
}

class _FindSeatsScreenState extends State<FindSeatsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';
  String? _selectedBuildingId;
  String? _selectedFloorId;

  // Get all buildings for filter
  Stream<QuerySnapshot> _getBuildings() {
    return _firestore.collection('buildings').snapshots();
  }

  // Get floors for selected building
  Stream<QuerySnapshot> _getFloors() {
    if (_selectedBuildingId == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('floors')
        .where('buildingId', isEqualTo: _selectedBuildingId)
        .snapshots();
  }

  // Get all rooms with building and floor info
  Stream<List<Map<String, dynamic>>> _getAllRooms() {
    return _firestore.collection('buildings').snapshots().asyncMap((
      buildingSnapshot,
    ) async {
      List<Map<String, dynamic>> allRooms = [];

      for (var buildingDoc in buildingSnapshot.docs) {
        String buildingId = buildingDoc.id;
        String buildingName = (buildingDoc.data() as Map)['name'] ?? 'Unnamed';

        QuerySnapshot floorsSnapshot =
            await _firestore
                .collection('floors')
                .where('buildingId', isEqualTo: buildingId)
                .get();

        for (var floorDoc in floorsSnapshot.docs) {
          String floorId = floorDoc.id;
          String floorName = (floorDoc.data() as Map)['name'] ?? 'Floor';

          QuerySnapshot roomsSnapshot =
              await _firestore
                  .collection('rooms')
                  .where('floorId', isEqualTo: floorId)
                  .get();

          for (var roomDoc in roomsSnapshot.docs) {
            String roomId = roomDoc.id;
            String roomName = (roomDoc.data() as Map)['name'] ?? 'Room';

            // Count available seats
            QuerySnapshot seatsSnapshot =
                await _firestore
                    .collection('seats')
                    .where('roomId', isEqualTo: roomId)
                    .where('status', isEqualTo: 'available')
                    .get();

            allRooms.add({
              'buildingId': buildingId,
              'buildingName': buildingName,
              'floorId': floorId,
              'floorName': floorName,
              'roomId': roomId,
              'roomName': roomName,
              'availableSeats': seatsSnapshot.docs.length,
            });
          }
        }
      }

      // Apply filters
      if (_selectedBuildingId != null) {
        allRooms =
            allRooms
                .where((room) => room['buildingId'] == _selectedBuildingId)
                .toList();
      }
      if (_selectedFloorId != null) {
        allRooms =
            allRooms
                .where((room) => room['floorId'] == _selectedFloorId)
                .toList();
      }
      if (_searchQuery.isNotEmpty) {
        allRooms =
            allRooms
                .where(
                  (room) =>
                      room['roomName'].toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ) ||
                      room['buildingName'].toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ) ||
                      room['floorName'].toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ),
                )
                .toList();
      }

      // Sort by available seats
      allRooms.sort(
        (a, b) =>
            (b['availableSeats'] ?? 0).compareTo(a['availableSeats'] ?? 0),
      );

      return allRooms;
    });
  }

  void _onNavTab(int index) {
    Widget screen;
    switch (index) {
      case 0: screen = const StudentHomeScreen(); break;
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 85,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
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
        title: const Text(
          'Find Seats',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search building, floor, room...',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF3949AB)),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              children: [
                // Building Filter
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _getBuildings(),
                    builder: (context, snapshot) {
                      var items = <DropdownMenuItem<String>>[];
                      if (snapshot.hasData) {
                        items = [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All Buildings'),
                          ),
                          ...snapshot.data!.docs.map((doc) {
                            var data = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem<String>(
                              value: doc.id,
                              child: Text(data['name'] ?? 'Unnamed'),
                            );
                          }),
                        ];
                      }
                      
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true, // Prevents text overflow
                          value: _selectedBuildingId,
                          items: items.isEmpty ? null : items,
                          hint: const Text(
                            'Building',
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: snapshot.hasData ? (value) {
                            setState(() {
                              _selectedBuildingId = value;
                              _selectedFloorId = null;
                            });
                          } : null,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Floor Filter
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _getFloors(),
                    builder: (context, snapshot) {
                      var items = <DropdownMenuItem<String>>[];
                      if (_selectedBuildingId != null && snapshot.hasData) {
                        items = [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All Floors'),
                          ),
                          ...snapshot.data!.docs.map((doc) {
                            var data = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem<String>(
                              value: doc.id,
                              child: Text(data['name'] ?? 'Floor'),
                            );
                          }),
                        ];
                      }
                      
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true, // Prevents text overflow
                          value: _selectedFloorId,
                          items: items.isEmpty ? null : items,
                          hint: const Text(
                            'Floor',
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: items.isNotEmpty ? (value) {
                            setState(() {
                              _selectedFloorId = value;
                            });
                          } : null,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Room List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _getAllRooms(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 72, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No areas found',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey),
                        ),
                        Text(
                          'Try adjusting your filters',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                var rooms = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    var room = rooms[index];
                    return Card(
                      color: Colors.blue.shade50, // Match the blue variant theme
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0, 
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          if (room['availableSeats'] > 0) {
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
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.meeting_room,
                                  color: Color(0xFF3949AB),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      room['roomName'],
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A237E),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${room['buildingName']} • ${room['floorName']}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${room['availableSeats']}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: room['availableSeats'] > 0
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                      ),
                                    ),
                                    Text(
                                      'seats',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: room['availableSeats'] > 0
                                            ? Colors.green.shade600
                                            : Colors.red.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0,
        onTabSelected: _onNavTab,
      ),
    );
  }
}
