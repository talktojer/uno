import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/storage_service.dart';

class CreateGameSection extends StatelessWidget {
  final bool isLoading;
  final String? gameId;
  final String? gameCode;
  final VoidCallback onCreateGame;
  final VoidCallback onBackToMenu;

  const CreateGameSection({
    super.key,
    required this.isLoading,
    this.gameId,
    this.gameCode,
    required this.onCreateGame,
    required this.onBackToMenu,
  });

  void _copyToClipboard(BuildContext context) {
    if (gameCode != null) {
      final url = '$baseUrl/$gameCode';
      StorageService.copyToClipboard(url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Game URL copied to clipboard!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.add_circle_outline, color: Colors.green),
              const SizedBox(width: 12),
              Text(
                'Create New Game',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Create a new UNO game and share the code with a friend to start playing.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : onCreateGame,
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.add_circle_outline, size: 24),
              label: Text(
                isLoading ? 'Creating Game...' : 'Create Game',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),

          // Game Code Display (if game was created)
          if (gameId != null && gameCode != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'Game Code: $gameCode',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share this code with others to join your game!',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Full URL: $baseUrl/$gameCode',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[600],
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.green),
                        onPressed: () => _copyToClipboard(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Back button
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onBackToMenu,
              icon: const Icon(Icons.arrow_back, size: 20),
              label: const Text('Back to Menu'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
