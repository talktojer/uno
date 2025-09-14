import 'package:flutter/material.dart';

class RejoinJoinChoiceDialog extends StatelessWidget {
  final String gameCode;
  final String playerName;
  final VoidCallback onRejoin;
  final VoidCallback onJoin;
  final VoidCallback onCancel;

  const RejoinJoinChoiceDialog({
    super.key,
    required this.gameCode,
    required this.playerName,
    required this.onRejoin,
    required this.onJoin,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Game Found'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Game code "$gameCode" found!'),
          const SizedBox(height: 8),
          const Text(
            'This game has disconnected players. You can either:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text('• Rejoin if you were playing this game before'),
          const Text('• Join as a new player'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Text(
              'Your name "${playerName.isNotEmpty ? playerName : 'is ready'}" is automatically filled in for rejoining',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: onRejoin,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: const Text('Rejoin Game'),
        ),
        ElevatedButton(
          onPressed: onJoin,
          child: const Text('Join as New Player'),
        ),
      ],
    );
  }
}
