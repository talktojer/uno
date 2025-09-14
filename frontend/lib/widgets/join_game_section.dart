import 'package:flutter/material.dart';

class JoinGameSection extends StatelessWidget {
  final TextEditingController gameCodeController;
  final bool isLoading;
  final VoidCallback onJoinGame;
  final VoidCallback onBackToMenu;

  const JoinGameSection({
    super.key,
    required this.gameCodeController,
    required this.isLoading,
    required this.onJoinGame,
    required this.onBackToMenu,
  });

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
              const Icon(Icons.login, color: Colors.blue),
              const SizedBox(width: 12),
              Text(
                'Join Existing Game',
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
            'Enter the 5-character game code to join an existing game.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),

          TextField(
            controller: gameCodeController,
            decoration: InputDecoration(
              labelText: 'Game Code',
              hintText: 'Enter 5-character code (e.g., ABC12)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: const Icon(Icons.qr_code, color: Colors.blue),
              counterText: '${gameCodeController.text.length}/5',
            ),
            maxLength: 5,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (gameCodeController.text.length == 5 && !isLoading)
                  ? onJoinGame
                  : null,
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.login, size: 24),
              label: Text(
                isLoading ? 'Joining Game...' : 'Join Game',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),

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
