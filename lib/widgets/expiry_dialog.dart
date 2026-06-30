import 'package:flutter/material.dart';

class ExpiryDialog extends StatelessWidget {
  final String seatNumber;
  final String buildingName;
  final String roomName;
  final ValueNotifier<int> countdownNotifier;

  const ExpiryDialog({
    super.key,
    required this.seatNumber,
    required this.buildingName,
    required this.roomName,
    required this.countdownNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Session Expiring',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Are you still using Seat $seatNumber?',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '$buildingName - $roomName',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: countdownNotifier,
            builder: (context, secs, _) {
              return Text(
                secs > 0 ? 'Auto-releasing in $secs s' : 'Releasing now...',
                style: TextStyle(color: Colors.red.shade600, fontSize: 14),
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Release Seat'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: const Text("Yes, I'm Still Here"),
        ),
      ],
    );
  }
}
