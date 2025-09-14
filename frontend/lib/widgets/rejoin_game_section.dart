import 'package:flutter/material.dart';

class RejoinGameSection extends StatelessWidget {
  final TextEditingController gameCodeController;
  final bool isLoading;
  final VoidCallback onRejoinGame;
  final VoidCallback onJoinAsNewPlayer;
  final VoidCallback onBackToMenu;

  const RejoinGameSection({
    super.key,
    required this.gameCodeController,
    required this.isLoading,
    required this.onRejoinGame,
    required this.onJoinAsNewPlayer,
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
              const Icon(Icons.replay, color: Colors.orange),
              const SizedBox(width: 12),
              Text(
                'Rejoin Game',
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
            'Reconnect to a game you were playing if you got disconnected. '
            'This will restore your exact game state and cards.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),

          // Info box about rejoining
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your name is automatically filled in. If you want to rejoin as a different player, change the name above.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: gameCodeController,
            decoration: InputDecoration(
              labelText: 'Game Code',
              hintText: 'Enter the 5-character game code',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: const Icon(Icons.qr_code, color: Colors.orange),
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
                  ? onRejoinGame
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
                  : const Icon(Icons.replay, size: 24),
              label: Text(
                isLoading ? 'Rejoining...' : 'Rejoin Game',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
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

          // Alternative option
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onJoinAsNewPlayer,
              icon: const Icon(Icons.login, size: 20),
              label: const Text('Join as New Player Instead'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue[600],
                padding: const EdgeInsets.symmetric(vertical: 12),
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
