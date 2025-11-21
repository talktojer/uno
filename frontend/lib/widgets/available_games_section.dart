import 'package:flutter/material.dart';
import 'dart:html' as html;
import '../config/app_config.dart';
import '../services/storage_service.dart';

class AvailableGamesSection extends StatelessWidget {
  final List<Map<String, dynamic>> availableGames;
  final TextEditingController gameCodeController;
  final String playerName;
  final Function(String) onActionSelected;
  final Function(String) onJoinGameDirectly;
  final Function(String) onDeleteGame;
  final Function(String, String)? onRejoinGame;

  const AvailableGamesSection({
    super.key,
    required this.availableGames,
    required this.gameCodeController,
    required this.playerName,
    required this.onActionSelected,
    required this.onJoinGameDirectly,
    required this.onDeleteGame,
    this.onRejoinGame,
  });

  void _copyGameCode(BuildContext context, String gameCode) {
    if (gameCode.isEmpty) return;

    // Copy full game URL to clipboard while also priming the join form
    final url = '$baseUrl/$gameCode';
    StorageService.copyToClipboard(url);

    gameCodeController.text = gameCode;
    onActionSelected('join');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Game URL copied to clipboard! ($url)'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _joinGameDirectly(BuildContext context, String gameCode) {
    onJoinGameDirectly(gameCode);
  }

  bool _isUserInGame(String gameId, String playerName) {
    try {
      // Check if there's a session token for this game and player
      // Format: uno_session_{gameId}_{playerName}
      final expectedKey = 'uno_session_${gameId}_$playerName';
      if (html.window.localStorage.containsKey(expectedKey)) {
        return true;
      }
      
      // Fallback: check if there's any session token for this game
      // (in case player name doesn't match exactly)
      final keys = html.window.localStorage.keys;
      for (final key in keys) {
        if (key.startsWith('uno_session_${gameId}_')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error checking if user is in game: $e');
      return false;
    }
  }

  void _rejoinGame(BuildContext context, String gameCode, String gameId) {
    if (onRejoinGame != null) {
      onRejoinGame!(gameCode, gameId);
    } else {
      // Fallback to join directly
      onJoinGameDirectly(gameCode);
    }
  }

  Future<void> _confirmAndDeleteGame(
      BuildContext context, String gameId, String gameCode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Game'),
        content: Text('Are you sure you want to delete game $gameCode? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onDeleteGame(gameId);
    }
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Show rejoin button if user is in the game and it's in progress
                        // Show for any game that has started (game_started == true) and user has a session token
                        if (game['game_id'] != null &&
                            game['game_started'] == true &&
                            _isUserInGame(game['game_id'], playerName)) ...[
                          IconButton(
                            icon: const Icon(Icons.replay, color: Colors.orange),
                            tooltip: 'Rejoin Game',
                            onPressed: () => _rejoinGame(
                                context,
                                game['game_code'] ?? '',
                                game['game_id'] ?? ''),
                          ),
                        ],
                        // Show join/copy buttons for waiting games
                        if (game['status'] == 'waiting' ||
                            game['status'] == 'waiting_for_replacement') ...[
                          IconButton(
                            icon: const Icon(Icons.copy, color: Colors.blue),
                            tooltip: 'Copy Game Code',
                            onPressed: () => _copyGameCode(
                                context, game['game_code'] ?? ''),
                          ),
                          IconButton(
                            icon: const Icon(Icons.play_arrow,
                                color: Colors.green),
                            tooltip: 'Join Game',
                            onPressed: () => _joinGameDirectly(
                                context, game['game_code'] ?? ''),
                          ),
                        ],
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Delete Game',
                          onPressed: () => _confirmAndDeleteGame(
                              context,
                              game['game_id'] ?? '',
                              game['game_code'] ?? ''),
                        ),
                      ],
                    ),
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
