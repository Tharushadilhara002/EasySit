import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image/image.dart' as im;
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr/qr.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'login_screen.dart';

// ============================================================
// MAIN ADMIN DASHBOARD
// ============================================================
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;

  final List<String> _menuTitles = [
    'Manage Buildings',
    'Manage Floors',
    'Manage Rooms',
    'Manage Seats & QR',
    'Student Behavior',
    'Send Notification',
  ];

  final List<IconData> _menuIcons = [
    Icons.business,
    Icons.vertical_align_top,
    Icons.door_front_door,
    Icons.event_seat,
    Icons.analytics,
    Icons.notifications_active,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Admin Menu',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _menuTitles.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    selected: _selectedIndex == index,
                    selectedTileColor: Colors.blue.shade50,
                    leading: Icon(
                      _menuIcons[index],
                      color:
                          _selectedIndex == index
                              ? Colors.blue
                              : Colors.grey.shade700,
                    ),
                    title: Text(
                      _menuTitles[index],
                      style: TextStyle(
                        color:
                            _selectedIndex == index
                                ? Colors.blue
                                : Colors.black87,
                        fontWeight:
                            _selectedIndex == index
                                ? FontWeight.bold
                                : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: _buildScreen(_selectedIndex),
    );
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const ManageBuildingsScreen();
      case 1:
        return const ManageFloorsScreen();
      case 2:
        return const ManageRoomsScreen();
      case 3:
        return const ManageSeatsScreen();
      case 4:
        return const StudentBehaviorScreen();
      case 5:
        return const SendNotificationScreen();
      default:
        return const Center(child: Text('Unknown'));
    }
  }
}

// ============================================================
// 1. MANAGE BUILDINGS SCREEN
// ============================================================
class ManageBuildingsScreen extends StatefulWidget {
  const ManageBuildingsScreen({super.key});

  @override
  State<ManageBuildingsScreen> createState() => _ManageBuildingsScreenState();
}

class _ManageBuildingsScreenState extends State<ManageBuildingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _addBuilding() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter building name')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _firestore.collection('buildings').add({
        'name': _nameController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _nameController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Building added!'),
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
    setState(() => _isLoading = false);
  }

  Future<void> _deleteBuilding(String buildingId) async {
    bool? confirm = await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Building'),
            content: const Text(
              'This will delete ALL Floors, Rooms, and Seats inside this building. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete All'),
              ),
            ],
          ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      QuerySnapshot floorsSnapshot =
          await _firestore
              .collection('floors')
              .where('buildingId', isEqualTo: buildingId)
              .get();

      for (var floorDoc in floorsSnapshot.docs) {
        String floorId = floorDoc.id;
        QuerySnapshot roomsSnapshot =
            await _firestore
                .collection('rooms')
                .where('floorId', isEqualTo: floorId)
                .get();

        for (var roomDoc in roomsSnapshot.docs) {
          String roomId = roomDoc.id;
          QuerySnapshot seatsSnapshot =
              await _firestore
                  .collection('seats')
                  .where('roomId', isEqualTo: roomId)
                  .get();
          for (var seatDoc in seatsSnapshot.docs) {
            await _firestore.collection('seats').doc(seatDoc.id).delete();
          }
          await _firestore.collection('rooms').doc(roomId).delete();
        }
        await _firestore.collection('floors').doc(floorId).delete();
      }
      await _firestore.collection('buildings').doc(buildingId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Building and all data deleted!'),
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
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ListView(
        children: [
          const Text(
            'Manage Buildings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Building Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _addBuilding,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    child: _isLoading
                        ? const Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : const Text(
                            'Add Building',
                            style: TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Building List',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream:
                _firestore
                    .collection('buildings')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text('Error: ${snapshot.error}'));
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No buildings added yet.'));
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.business, color: Colors.blue),
                        title: Text(data['name'] ?? 'Unnamed'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteBuilding(doc.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

// ============================================================
// 2. MANAGE FLOORS SCREEN
// ============================================================
class ManageFloorsScreen extends StatefulWidget {
  const ManageFloorsScreen({super.key});

  @override
  State<ManageFloorsScreen> createState() => _ManageFloorsScreenState();
}

class _ManageFloorsScreenState extends State<ManageFloorsScreen> {
  final TextEditingController _floorNameController = TextEditingController();
  String? _selectedBuildingId;
  bool _isLoading = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _addFloor() async {
    if (_selectedBuildingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a building first!')),
      );
      return;
    }
    if (_floorNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a floor name!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _firestore.collection('floors').add({
        'buildingId': _selectedBuildingId,
        'name': _floorNameController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _floorNameController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Floor added!'),
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
    setState(() => _isLoading = false);
  }

  Future<void> _deleteFloor(String floorId) async {
    bool? confirm = await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Floor'),
            content: const Text(
              'This will delete all Rooms and Seats in this floor. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      QuerySnapshot roomsSnapshot =
          await _firestore
              .collection('rooms')
              .where('floorId', isEqualTo: floorId)
              .get();

      for (var roomDoc in roomsSnapshot.docs) {
        String roomId = roomDoc.id;
        QuerySnapshot seatsSnapshot =
            await _firestore
                .collection('seats')
                .where('roomId', isEqualTo: roomId)
                .get();
        for (var seatDoc in seatsSnapshot.docs) {
          await _firestore.collection('seats').doc(seatDoc.id).delete();
        }
        await _firestore.collection('rooms').doc(roomId).delete();
      }
      await _firestore.collection('floors').doc(floorId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Floor and related data deleted!'),
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
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ListView(
        children: [
          const Text(
            'Manage Floors',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('buildings').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return DropdownButtonFormField<String>(
                          value: null,
                          items: const [],
                          hint: const Text('No Buildings'),
                          onChanged: null,
                          decoration: const InputDecoration(
                            labelText: 'Building',
                            border: OutlineInputBorder(),
                          ),
                        );
                      }
                      var items = snapshot.data!.docs.map((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(data['name'] ?? 'Unnamed'),
                        );
                      }).toList();
                      return DropdownButtonFormField<String>(
                        value: _selectedBuildingId,
                        items: items,
                        decoration: const InputDecoration(
                          labelText: 'Building',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _selectedBuildingId = value;
                          });
                        },
                        hint: const Text('Select Building'),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _floorNameController,
                    decoration: const InputDecoration(
                      labelText: 'Floor Name (e.g. Ground Floor)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _addFloor,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    child: _isLoading
                        ? const Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : const Text(
                            'Add Floor',
                            style: TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Floor List',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream:
                _firestore
                    .collection('floors')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text('Error: ${snapshot.error}'));
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No floors added yet.'));
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(
                          Icons.vertical_align_top,
                          color: Colors.blue,
                        ),
                        title: Text(data['name'] ?? 'Unnamed'),
                        subtitle: FutureBuilder<DocumentSnapshot>(
                          future:
                              _firestore
                                  .collection('buildings')
                                  .doc(data['buildingId'])
                                  .get(),
                          builder: (context, buildingSnapshot) {
                            if (!buildingSnapshot.hasData)
                              return const Text('Loading...');
                            var buildingData =
                                buildingSnapshot.data?.data()
                                    as Map<String, dynamic>?;
                            return Text(
                              'Building: ${buildingData?['name'] ?? 'Unknown'}',
                            );
                          },
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteFloor(doc.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

// ============================================================
// 3. MANAGE ROOMS SCREEN
// ============================================================
class ManageRoomsScreen extends StatefulWidget {
  const ManageRoomsScreen({super.key});

  @override
  State<ManageRoomsScreen> createState() => _ManageRoomsScreenState();
}

class _ManageRoomsScreenState extends State<ManageRoomsScreen> {
  final TextEditingController _roomNameController = TextEditingController();
  String? _selectedBuildingId;
  String? _selectedFloorId;
  bool _isLoading = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot> _getFloors() {
    if (_selectedBuildingId == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('floors')
        .where('buildingId', isEqualTo: _selectedBuildingId)
        .snapshots();
  }

  Future<void> _addRoom() async {
    if (_selectedFloorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a floor first!')),
      );
      return;
    }
    if (_roomNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room name!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _firestore.collection('rooms').add({
        'floorId': _selectedFloorId,
        'name': _roomNameController.text.trim(),
        'capacity': 0,
        'rows': 0,
        'cols': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _roomNameController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Room added!'),
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
    setState(() => _isLoading = false);
  }

  Future<void> _deleteRoom(String roomId) async {
    bool? confirm = await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Room'),
            content: const Text(
              'This will delete all Seats in this room. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      QuerySnapshot seatsSnapshot =
          await _firestore
              .collection('seats')
              .where('roomId', isEqualTo: roomId)
              .get();
      for (var seatDoc in seatsSnapshot.docs) {
        await _firestore.collection('seats').doc(seatDoc.id).delete();
      }
      await _firestore.collection('rooms').doc(roomId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Room and seats deleted!'),
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
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ListView(
        children: [
          const Text(
            'Manage Rooms',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('buildings').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return DropdownButtonFormField<String>(
                          value: null,
                          items: const [],
                          hint: const Text('No Buildings'),
                          onChanged: null,
                          decoration: const InputDecoration(
                            labelText: 'Building',
                            border: OutlineInputBorder(),
                          ),
                        );
                      }
                      var items = snapshot.data!.docs.map((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(data['name'] ?? 'Unnamed'),
                        );
                      }).toList();
                      return DropdownButtonFormField<String>(
                        value: _selectedBuildingId,
                        items: items,
                        decoration: const InputDecoration(
                          labelText: 'Building',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _selectedBuildingId = value;
                            _selectedFloorId = null;
                          });
                        },
                        hint: const Text('Select Building'),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  StreamBuilder<QuerySnapshot>(
                    stream: _getFloors(),
                    builder: (context, snapshot) {
                      if (_selectedBuildingId == null) {
                        return DropdownButtonFormField<String>(
                          value: null,
                          items: const [],
                          hint: const Text('Select Building first'),
                          onChanged: null,
                          decoration: const InputDecoration(
                            labelText: 'Floor',
                            border: OutlineInputBorder(),
                          ),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return DropdownButtonFormField<String>(
                          value: null,
                          items: const [],
                          hint: const Text('No Floors'),
                          onChanged: null,
                          decoration: const InputDecoration(
                            labelText: 'Floor',
                            border: OutlineInputBorder(),
                          ),
                        );
                      }
                      var items = snapshot.data!.docs.map((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(data['name'] ?? 'Unnamed'),
                        );
                      }).toList();
                      return DropdownButtonFormField<String>(
                        value: _selectedFloorId,
                        items: items,
                        decoration: const InputDecoration(
                          labelText: 'Floor',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _selectedFloorId = value;
                          });
                        },
                        hint: const Text('Select Floor'),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _roomNameController,
                    decoration: const InputDecoration(
                      labelText: 'Room Name (e.g. Room 101)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _addRoom,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    child: _isLoading
                        ? const Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : const Text(
                            'Add Room',
                            style: TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Room List',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _selectedFloorId == null
              ? const Center(
                  child: Text('Select a building and floor to see rooms'),
                )
              : StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('rooms')
                      .where('floorId', isEqualTo: _selectedFloorId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError)
                      return Center(
                        child: Text('Error: ${snapshot.error}'),
                      );
                    if (snapshot.connectionState == ConnectionState.waiting)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Text('No rooms added yet.'),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                            var doc = snapshot.data!.docs[index];
                            var data = doc.data() as Map<String, dynamic>;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.door_front_door,
                                  color: Colors.blue,
                                ),
                                title: Text(data['name'] ?? 'Unnamed'),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteRoom(doc.id),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
        ],
      ),
    );
  }
}

// ============================================================
// 4. MANAGE SEATS & QR SCREEN (Fixed)
// ============================================================
class ManageSeatsScreen extends StatefulWidget {
  const ManageSeatsScreen({super.key});

  @override
  State<ManageSeatsScreen> createState() => _ManageSeatsScreenState();
}

class _ManageSeatsScreenState extends State<ManageSeatsScreen> {
  String? _selectedBuildingId;
  String? _selectedFloorId;
  String? _selectedRoomId;
  final TextEditingController _bulkCountController = TextEditingController();
  final TextEditingController _singleSeatController = TextEditingController();
  bool _isLoading = false;
  final Set<String> _downloadingSeats = {};
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ QR Code Image Generation Function
  Future<Uint8List?> _generateQrImageBytes(String data) async {
    try {
      final qrCode = QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.Q,
      );
      final qrImage = QrImage(qrCode);
      final moduleCount = qrCode.moduleCount;
      const scale = 8;

      final img = im.Image(
        width: moduleCount * scale,
        height: moduleCount * scale,
        numChannels: 3,
      );

      for (int y = 0; y < moduleCount; y++) {
        for (int x = 0; x < moduleCount; x++) {
          final dark = qrImage.isDark(y, x);
          final v = dark ? 0 : 255;
          for (int dy = 0; dy < scale; dy++) {
            for (int dx = 0; dx < scale; dx++) {
              img.setPixelRgb(x * scale + dx, y * scale + dy, v, v, v);
            }
          }
        }
      }

      final jpgBytes = im.encodeJpg(img, quality: 90);
      return Uint8List.fromList(jpgBytes);
    } catch (e) {
      print('❌ QR Generation Error: $e');
      return null;
    }
  }

  // ✅ PDF Download Function (direct save to Downloads)
  Future<void> _downloadPdf(Uint8List bytes, String filename) async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('easy_sit/pdf');
        await platform.invokeMethod('savePdf', {'bytes': bytes, 'filename': filename});
      } else {
        Directory dir;
        try {
          dir = await getApplicationDocumentsDirectory();
        } catch (_) {
          dir = Directory.systemTemp;
        }
        await File('${dir.path}/$filename').writeAsBytes(bytes);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF saved to Downloads!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      try {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Stream<QuerySnapshot> _getFloors() {
    if (_selectedBuildingId == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('floors')
        .where('buildingId', isEqualTo: _selectedBuildingId)
        .snapshots();
  }

  Stream<QuerySnapshot> _getRooms() {
    if (_selectedFloorId == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('rooms')
        .where('floorId', isEqualTo: _selectedFloorId)
        .snapshots();
  }

  Stream<QuerySnapshot> _getSeats() {
    if (_selectedRoomId == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('seats')
        .where('roomId', isEqualTo: _selectedRoomId)
        .snapshots();
  }

  Future<void> _addSeatsBulk() async {
    if (_selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a room first!')),
      );
      return;
    }
    int count = int.tryParse(_bulkCountController.text) ?? 0;
    if (count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid seat count!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      QuerySnapshot existingSeats =
          await _firestore
              .collection('seats')
              .where('roomId', isEqualTo: _selectedRoomId)
              .get();

      int startNumber = existingSeats.docs.length + 1;

      for (int i = 0; i < count; i++) {
        int seatNum = startNumber + i;
        DocumentReference docRef = await _firestore.collection('seats').add({
          'roomId': _selectedRoomId,
          'seatNumber': seatNum.toString(),
          'status': 'available',
          'createdAt': FieldValue.serverTimestamp(),
        });
        await docRef.update({'qrData': 'SEAT:${docRef.id}'});
      }
      _bulkCountController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count seats added!'),
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
    setState(() => _isLoading = false);
  }

  Future<void> _addSingleSeat() async {
    if (_selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a room first!')),
      );
      return;
    }
    String seatNumber = _singleSeatController.text.trim();
    if (seatNumber.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a seat number!')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      DocumentReference docRef = await _firestore.collection('seats').add({
        'roomId': _selectedRoomId,
        'seatNumber': seatNumber,
        'status': 'available',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await docRef.update({'qrData': 'SEAT:${docRef.id}'});
      _singleSeatController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seat added!'),
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
    setState(() => _isLoading = false);
  }

  Future<void> _deleteSeat(String seatId) async {
    bool? confirm = await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Seat'),
            content: const Text('Are you sure?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirm != true) return;

    try {
      await _firestore.collection('seats').doc(seatId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seat deleted!'),
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

  // ✅ All QR Codes PDF - at least 8 QRs per page with heading
  Future<void> _printAllQrs() async {
    if (_selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a room first!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Fetch building, floor, room names
      String buildingName = 'Unknown';
      String floorName = 'Unknown';
      String roomName = 'Unknown';

      if (_selectedBuildingId != null) {
        final bDoc = await _firestore.collection('buildings').doc(_selectedBuildingId).get();
        if (bDoc.exists) buildingName = bDoc.data()?['name'] ?? 'Unknown';
      }
      if (_selectedFloorId != null) {
        final fDoc = await _firestore.collection('floors').doc(_selectedFloorId).get();
        if (fDoc.exists) floorName = fDoc.data()?['name'] ?? 'Unknown';
      }
      if (_selectedRoomId != null) {
        final rDoc = await _firestore.collection('rooms').doc(_selectedRoomId).get();
        if (rDoc.exists) roomName = rDoc.data()?['name'] ?? 'Unknown';
      }

      QuerySnapshot seatsSnapshot =
          await _firestore
              .collection('seats')
              .where('roomId', isEqualTo: _selectedRoomId)
              .get();

      if (seatsSnapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No seats to export!')));
        }
        setState(() => _isLoading = false);
        return;
      }

      var sortedDocs = List<QueryDocumentSnapshot>.from(seatsSnapshot.docs);
      sortedDocs.sort((a, b) {
        var aNum = int.tryParse((a.data() as Map)['seatNumber'] ?? '0') ?? 0;
        var bNum = int.tryParse((b.data() as Map)['seatNumber'] ?? '0') ?? 0;
        return aNum.compareTo(bNum);
      });

      final pdfDoc = pw.Document();

      // Grid layout: 4 columns, at least 8 QRs per page
      const int cols = 4;
      const double qrImageSize = 100.0;
      const double cellHeight = 140.0; // QR(100) + space(8) + text(20) + padding
      const double rowSpacing = 15.0;

      // Generate all cells first
      List<pw.Widget> allCells = [];

      for (int i = 0; i < sortedDocs.length; i++) {
        var data = sortedDocs[i].data() as Map<String, dynamic>;
        String seatNumber = data['seatNumber'] ?? '?';
        String seatId = sortedDocs[i].id;

        String qrData = data['qrData'] ?? 'SEAT:$seatId';
        Uint8List? qrBytes = await _generateQrImageBytes(qrData);

        allCells.add(
          pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              qrBytes != null
                  ? pw.Image(
                      pw.MemoryImage(qrBytes),
                      width: qrImageSize,
                      height: qrImageSize,
                      fit: pw.BoxFit.fill,
                    )
                  : pw.Container(
                      width: qrImageSize,
                      height: qrImageSize,
                      color: pw_pdf.PdfColor.fromInt(0xffc8c8c8),
                      child: pw.Center(
                        child: pw.Text('QR Error', style: const pw.TextStyle(fontSize: 10)),
                      ),
                    ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Seat #$seatNumber',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        );
      }

      // Calculate rows per page (at least 2 rows = 8 QRs minimum)
      const double usablePageHeight = 801.89; // A4 height - 40 margins
      const double headerHeight = 70.0;
      int rowsPerPage = ((usablePageHeight - headerHeight) / (cellHeight + rowSpacing)).floor();
      if (rowsPerPage < 2) rowsPerPage = 2;
      int itemsPerPage = cols * rowsPerPage;

      // Add pages
      for (int start = 0; start < allCells.length; start += itemsPerPage) {
        int end = (start + itemsPerPage > allCells.length) ? allCells.length : start + itemsPerPage;
        var pageCells = allCells.sublist(start, end);

        List<pw.Widget> rows = [];
        for (int j = 0; j < pageCells.length; j += cols) {
          int rowEnd = (j + cols > pageCells.length) ? pageCells.length : j + cols;
          var rowCells = pageCells.sublist(j, rowEnd);

          rows.add(
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: rowCells,
            ),
          );
          if (rowEnd < pageCells.length) {
            rows.add(pw.SizedBox(height: rowSpacing));
          }
        }

        pdfDoc.addPage(
          pw.Page(
            margin: const pw.EdgeInsets.all(20),
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  '$buildingName - $floorName - $roomName',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Seat QR Codes',
                  style: pw.TextStyle(
                    fontSize: 14,
                    color: pw_pdf.PdfColors.grey,
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Column(children: rows),
              ],
            ),
          ),
        );
      }

      final pdfBytes = await pdfDoc.save();
      await _downloadPdf(pdfBytes, 'seats_qr_codes.pdf');
    } catch (e) {
      print('❌ PDF Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  // ✅ Single Seat QR PDF
  Future<void> _printSingleQr(
    String seatId,
    String seatNumber,
    String qrData,
  ) async {
    setState(() => _downloadingSeats.add(seatId));

    try {
      Uint8List? qrBytes = await _generateQrImageBytes(qrData);

      final pdfDoc = pw.Document();

      pdfDoc.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(40),
          build:
              (context) => pw.Center(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (qrBytes != null)
                      pw.Image(
                        pw.MemoryImage(qrBytes),
                        width: 250,
                        height: 250,
                        fit: pw.BoxFit.fill,
                      )
                    else
                      pw.Container(
                        width: 250,
                        height: 250,
                        color: pw_pdf.PdfColor.fromInt(0xffc8c8c8),
                        child: pw.Center(
                          child: pw.Text('QR Generation Failed'),
                        ),
                      ),
                    pw.SizedBox(height: 20),
                    pw.Text(
                      'Seat $seatNumber',
                      style: pw.TextStyle(
                        fontSize: 28,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'EasySit - Scan to Book',
                      style: pw.TextStyle(
                        fontSize: 16,
                        color: pw_pdf.PdfColors.grey,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'ID: $seatId',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: pw_pdf.PdfColors.grey,
                      ),
                    ),
                  ],
                ),
              ),
        ),
      );

      final pdfBytes = await pdfDoc.save();
      await _downloadPdf(pdfBytes, 'seat_$seatNumber.pdf');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Seat $seatNumber QR saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Single QR Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _downloadingSeats.remove(seatId));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ListView(
        children: [
          const Text(
            'Manage Seats & QR',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Building Dropdown
                  SizedBox(
                    width: 300,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestore.collection('buildings').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return DropdownButtonFormField<String>(
                            value: null,
                            items: [],
                            hint: const Text('No Buildings'),
                            onChanged: null,
                            decoration: const InputDecoration(
                              labelText: 'Building',
                              border: OutlineInputBorder(),
                            ),
                          );
                        }
                        var items =
                            snapshot.data!.docs.map((doc) {
                              var data = doc.data() as Map<String, dynamic>;
                              return DropdownMenuItem<String>(
                                value: doc.id,
                                child: Text(data['name'] ?? 'Unnamed'),
                              );
                            }).toList();
                        return DropdownButtonFormField<String>(
                          value: _selectedBuildingId,
                          items: items,
                          decoration: const InputDecoration(
                            labelText: 'Building',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _selectedBuildingId = value;
                              _selectedFloorId = null;
                              _selectedRoomId = null;
                            });
                          },
                          hint: const Text('Select Building'),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 15),
                  // Floor Dropdown
                  SizedBox(
                    width: 300,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _getFloors(),
                      builder: (context, snapshot) {
                        if (_selectedBuildingId == null) {
                          return DropdownButtonFormField<String>(
                            value: null,
                            items: [],
                            hint: const Text('Select Building first'),
                            onChanged: null,
                            decoration: const InputDecoration(
                              labelText: 'Floor',
                              border: OutlineInputBorder(),
                            ),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return DropdownButtonFormField<String>(
                            value: null,
                            items: [],
                            hint: const Text('No Floors'),
                            onChanged: null,
                            decoration: const InputDecoration(
                              labelText: 'Floor',
                              border: OutlineInputBorder(),
                            ),
                          );
                        }
                        var items =
                            snapshot.data!.docs.map((doc) {
                              var data = doc.data() as Map<String, dynamic>;
                              return DropdownMenuItem<String>(
                                value: doc.id,
                                child: Text(data['name'] ?? 'Unnamed'),
                              );
                            }).toList();
                        return DropdownButtonFormField<String>(
                          value: _selectedFloorId,
                          items: items,
                          decoration: const InputDecoration(
                            labelText: 'Floor',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _selectedFloorId = value;
                              _selectedRoomId = null;
                            });
                          },
                          hint: const Text('Select Floor'),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 15),
                  // Room Dropdown
                  SizedBox(
                    width: 300,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _getRooms(),
                      builder: (context, snapshot) {
                        if (_selectedFloorId == null) {
                          return DropdownButtonFormField<String>(
                            value: null,
                            items: [],
                            hint: const Text('Select Floor first'),
                            onChanged: null,
                            decoration: const InputDecoration(
                              labelText: 'Room',
                              border: OutlineInputBorder(),
                            ),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return DropdownButtonFormField<String>(
                            value: null,
                            items: [],
                            hint: const Text('No Rooms'),
                            onChanged: null,
                            decoration: const InputDecoration(
                              labelText: 'Room',
                              border: OutlineInputBorder(),
                            ),
                          );
                        }
                        var items =
                            snapshot.data!.docs.map((doc) {
                              var data = doc.data() as Map<String, dynamic>;
                              return DropdownMenuItem<String>(
                                value: doc.id,
                                child: Text(data['name'] ?? 'Unnamed'),
                              );
                            }).toList();
                        return DropdownButtonFormField<String>(
                          value: _selectedRoomId,
                          items: items,
                          decoration: const InputDecoration(
                            labelText: 'Room',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _selectedRoomId = value;
                            });
                          },
                          hint: const Text('Select Room'),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),
                  // Bulk Add
                  const Text(
                    'Bulk Add Seats',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _bulkCountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Seat Count',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _addSeatsBulk,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                        child:
                            _isLoading
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text(
                                  'Add Bulk',
                                  style: TextStyle(color: Colors.white),
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  // Single Add
                  const Text(
                    'Add Single Seat',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _singleSeatController,
                          decoration: const InputDecoration(
                            labelText: 'Seat Number',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _addSingleSeat,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                        child:
                            _isLoading
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text(
                                  'Add',
                                  style: TextStyle(color: Colors.white),
                                ),
                      ),
                    ],
                  ),
                  if (_selectedRoomId != null) ...[
                    const SizedBox(height: 15),
                    const Divider(),
                    const SizedBox(height: 10),
                    // ✅ Print All QR Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _printAllQrs,
                        icon:
                            _isLoading
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.print, color: Colors.white),
                        label: const Text(
                          'Print / Download All QR Codes',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Seats',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: _getSeats(),
              builder: (context, snapshot) {
                if (_selectedRoomId == null) {
                  return const Center(
                    child: Text('Select a room to view seats'),
                  );
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No seats in this room. Add some!'),
                  );
                }
                var docs = snapshot.data!.docs;
                docs.sort((a, b) {
                  var aNum =
                      int.tryParse((a.data() as Map)['seatNumber'] ?? '0') ?? 0;
                  var bNum =
                      int.tryParse((b.data() as Map)['seatNumber'] ?? '0') ?? 0;
                  return aNum.compareTo(bNum);
                });
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    String seatNumber = data['seatNumber'] ?? '?';
                    String status = data['status'] ?? 'available';
                    String qrData = data['qrData'] ?? 'SEAT:${doc.id}';
                    MaterialColor seatColor =
                        status == 'booked'
                            ? Colors.red
                            : status == 'pending'
                            ? Colors.orange
                            : Colors.green;
                    return Card(
                      elevation: 2,
                      color: seatColor.shade100,
                      child: Stack(
                        children: [
                          Center(
                            child: Text(
                              seatNumber,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: seatColor.shade700,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => _deleteSeat(doc.id),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: GestureDetector(
                              onTap:
                                  _downloadingSeats.contains(doc.id)
                                      ? null
                                      : () => _printSingleQr(
                                        doc.id,
                                        seatNumber,
                                        qrData,
                                      ),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child:
                                    _downloadingSeats.contains(doc.id)
                                        ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Icon(
                                          Icons.qr_code,
                                          size: 18,
                                          color: Colors.black54,
                                        ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bulkCountController.dispose();
    _singleSeatController.dispose();
    super.dispose();
  }
}

// ============================================================
// 6. SEND NOTIFICATION SCREEN
// ============================================================
class SendNotificationScreen extends StatefulWidget {
  const SendNotificationScreen({super.key});

  @override
  State<SendNotificationScreen> createState() => _SendNotificationScreenState();
}

class _SendNotificationScreenState extends State<SendNotificationScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _sendNotification() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message')),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      await _firestore.collection('notifications').add({
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'userId': 'all',
      });
      _titleController.clear();
      _messageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification sent to all students!'),
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
    setState(() => _isSending = false);
  }

  Future<void> _deleteNotification(String docId) async {
    try {
      await _firestore.collection('notifications').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification deleted.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ListView(
        children: [
          const Text(
            'Send Notification to All Students',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'This notification will appear for all students in real-time.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Notification Title',
                      hintText: 'e.g. Library Closure Notice',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _messageController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Notification Message',
                      hintText: 'Type your message here...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.message),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _sendNotification,
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                      label: Text(
                        _isSending ? 'Sending...' : 'Send to All Students',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Sent Notifications',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream:
                  _firestore
                      .collection('notifications')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No notifications sent yet.'),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    Timestamp? ts = data['timestamp'] as Timestamp?;
                    String timeStr = '';
                    if (ts != null) {
                      DateTime dt = ts.toDate();
                      timeStr =
                          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    }
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Icon(Icons.notifications, color: Colors.white),
                        ),
                        title: Text(
                          data['title'] ?? 'No Title',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data['message'] ?? ''),
                            if (timeStr.isNotEmpty)
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteNotification(doc.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

// ============================================================
// 7. STUDENT BEHAVIOR SCREEN
// ============================================================
class StudentBehaviorScreen extends StatefulWidget {
  const StudentBehaviorScreen({super.key});

  @override
  State<StudentBehaviorScreen> createState() => _StudentBehaviorScreenState();
}

class _StudentBehaviorScreenState extends State<StudentBehaviorScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';

  Future<void> _toggleBlockStatus(String userId, bool currentStatus) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isBlocked': !currentStatus,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? 'Student blocked successfully.' : 'Student unblocked successfully.'),
            backgroundColor: !currentStatus ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Student Behavior',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage student access to the application.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              labelText: 'Search by Name, Email, or ID',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase().trim();
              });
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .where('userType', isEqualTo: 'student')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No students found.'));
                }

                var docs = snapshot.data!.docs.toList();
                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    String fullName = (data['fullName'] ?? '').toString().toLowerCase();
                    String email = (data['email'] ?? '').toString().toLowerCase();
                    String studentId = (data['studentId'] ?? '').toString().toLowerCase();
                    return fullName.contains(_searchQuery) || 
                           email.contains(_searchQuery) || 
                           studentId.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return const Center(child: Text('No matching students found.'));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    bool isBlocked = data['isBlocked'] ?? false;
                    String fullName = data['fullName'] ?? 'Unknown Name';
                    String studentId = data['studentId'] ?? 'Unknown ID';
                    String email = data['email'] ?? 'No email';

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isBlocked ? Colors.red.shade100 : Colors.blue.shade100,
                          child: Icon(
                            isBlocked ? Icons.block : Icons.person,
                            color: isBlocked ? Colors.red : Colors.blue,
                          ),
                        ),
                        title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$studentId • $email'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isBlocked ? 'Blocked' : 'Active',
                              style: TextStyle(
                                color: isBlocked ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Switch(
                              value: isBlocked,
                              activeColor: Colors.red,
                              onChanged: (value) => _toggleBlockStatus(doc.id, isBlocked),
                            ),
                          ],
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
    );
  }
}
