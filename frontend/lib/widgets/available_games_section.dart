import 'package:flutter/material.dart';

class AvailableGamesSection extends StatelessWidget {
  final List<Map<String, dynamic>> availableGames;
  final TextEditingController gameCodeController;
  final String playerName;
  final Function(String) onActionSelected;
  final Function(String) onJoinGameDirectly;

  const AvailableGamesSection({
    super.key,
    required this.availableGames,
    required this.gameCodeController,
    required this.playerName,
    required this.onActionSelected,
    required this.onJoinGameDirectly,
  });

  void _copyGameCode(BuildContext context, String gameCode) {
    gameCodeController.text = gameCode;
    onActionSelected('join');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Game code $gameCode copied to join form'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _joinGameDirectly(BuildContext context, String gameCode) {
    onJoinGameDirectly(gameCode);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
              const Icon(Icons.list, color: Colors.blue),
              const SizedBox(width: 12),
              Text(
                'Available Games',
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
            'Games waiting for players. Click the copy icon to use a game code.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: availableGames.length,
              itemBuilder: (context, index) {
                final game = availableGames[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      'Game Code: ${game['game_code'] ?? 'N/A'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status: ${game['status']} (${game['active_players'] ?? game['player_count']}/2 players)',
                        ),
                        if (game['game_id'] != null)
                          Text(
                            'Game ID: ${game['game_id']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                    trailing: (game['status'] == 'waiting' ||
                            game['status'] == 'waiting_for_replacement')
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon:
                                    const Icon(Icons.copy, color: Colors.blue),
                                onPressed: () => _copyGameCode(
                                    context, game['game_code'] ?? ''),
                              ),
                              IconButton(
                                icon: const Icon(Icons.play_arrow,
                                    color: Colors.green),
                                onPressed: () => _joinGameDirectly(
                                    context, game['game_code'] ?? ''),
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
