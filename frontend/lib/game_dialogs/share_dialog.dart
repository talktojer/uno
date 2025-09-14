import 'package:flutter/material.dart';
import 'dart:html' as html;
import '../config/app_config.dart';
import '../utils/home_screen_utils.dart';

class ShareDialog extends StatelessWidget {
  final String gameCode;

  const ShareDialog({super.key, required this.gameCode});

  static void show(BuildContext context, String gameCode) {
    showDialog(
      context: context,
      builder: (context) => ShareDialog(gameCode: gameCode),
    );
  }

  void _copyToClipboard(BuildContext context) {
    final url = '$baseUrl/$gameCode';
    html.window.navigator.clipboard?.writeText(url);
    HomeScreenUtils.showSuccessSnackBar(context, 'Game URL copied to clipboard!');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final shareUrl = '$baseUrl/$gameCode';

    return AlertDialog(
      title: const Text('Share Game'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Game Code: $gameCode'),
          const SizedBox(height: 16),
          const Text('Share this URL with others:'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey),
            ),
            child: SelectableText(
              shareUrl,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () => _copyToClipboard(context),
          child: const Text('Copy URL'),
        ),
      ],
    );
  }
}
