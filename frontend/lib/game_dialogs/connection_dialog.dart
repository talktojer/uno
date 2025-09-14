import 'package:flutter/material.dart';

class ConnectionDialog extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final bool isReconnecting;
  final VoidCallback? onReconnect;

  const ConnectionDialog({
    super.key,
    required this.isConnected,
    required this.isConnecting,
    required this.isReconnecting,
    this.onReconnect,
  });

  static void show(
    BuildContext context, {
    required bool isConnected,
    required bool isConnecting,
    required bool isReconnecting,
    VoidCallback? onReconnect,
  }) {
    showDialog(
      context: context,
      builder: (context) => ConnectionDialog(
        isConnected: isConnected,
        isConnecting: isConnecting,
        isReconnecting: isReconnecting,
        onReconnect: onReconnect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connection Status'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.green
                      : isConnecting
                          ? Colors.blue
                          : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isConnected
                    ? 'Connected'
                    : isConnecting
                        ? 'Connecting'
                        : 'Disconnected',
                style: TextStyle(
                  color: isConnected
                      ? Colors.green
                      : isConnecting
                          ? Colors.blue
                          : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (isConnecting) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Connecting...'),
              ],
            ),
          ],
          if (isReconnecting) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Reconnecting...'),
              ],
            ),
          ],
          if (!isConnected && !isReconnecting && !isConnecting) ...[
            const SizedBox(height: 16),
            const Text(
              'Your connection to the game server was lost. This can happen when:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text('• You switched to another app',
                style: TextStyle(fontSize: 12)),
            const Text('• Your device went to sleep',
                style: TextStyle(fontSize: 12)),
            const Text('• Network connection changed',
                style: TextStyle(fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (!isConnected && !isReconnecting && !isConnecting && onReconnect != null)
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onReconnect!();
            },
            child: const Text('Reconnect'),
          ),
      ],
    );
  }
}
