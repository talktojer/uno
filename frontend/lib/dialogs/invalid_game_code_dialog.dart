import 'package:flutter/material.dart';

class InvalidGameCodeDialog extends StatelessWidget {
  final String gameCode;
  final VoidCallback onGoHome;

  const InvalidGameCodeDialog({
    super.key,
    required this.gameCode,
    required this.onGoHome,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invalid Game Code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('The game code "$gameCode" was not found or is invalid.'),
          const SizedBox(height: 16),
          const Text('This could mean:'),
          const SizedBox(height: 8),
          const Text('• The game has ended'),
          const Text('• The game code was mistyped'),
          const Text('• The game no longer exists'),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: onGoHome,
          child: const Text('Go to Home'),
        ),
      ],
    );
  }
}
