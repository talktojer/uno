import 'package:flutter/material.dart';

class RejoinNotPossibleDialog extends StatelessWidget {
  final String reason;
  final VoidCallback onJoinNormally;
  final VoidCallback onCancel;

  const RejoinNotPossibleDialog({
    super.key,
    required this.reason,
    required this.onJoinNormally,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cannot Rejoin'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('You cannot rejoin this game because:'),
          const SizedBox(height: 8),
          Text(reason, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text(
              'Would you like to try joining the game normally instead?'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: onJoinNormally,
          child: const Text('Join Normally'),
        ),
      ],
    );
  }
}

class RejoinFallbackDialog extends StatelessWidget {
  final VoidCallback onJoinNormally;
  final VoidCallback onCancel;

  const RejoinFallbackDialog({
    super.key,
    required this.onJoinNormally,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rejoin Not Available'),
      content: const Text(
        'The rejoin feature is not available for this game. '
        'Would you like to try joining the game normally instead?',
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: onJoinNormally,
          child: const Text('Join Normally'),
        ),
      ],
    );
  }
}
