import 'package:flutter/material.dart';
import '../utils/home_screen_utils.dart';

class GameMessageHandler {
  static void handleMessage(
    BuildContext context,
    Map<String, dynamic> message,
    Function(Map<String, dynamic>) onGameStateUpdate,
  ) {
    final messageType = message['type'];
    
    switch (messageType) {
      case 'game_update':
        onGameStateUpdate(message['game_state']);
        break;
        
      case 'game_started':
        HomeScreenUtils.showSuccessSnackBar(
          context,
          'Game started! ${message['message']}',
        );
        break;
        
      case 'player_replaced':
        HomeScreenUtils.showInfoSnackBar(
          context,
          message['message'],
        );
        break;
        
      case 'player_disconnected':
        HomeScreenUtils.showWarningSnackBar(
          context,
          message['message'],
        );
        break;
        
      case 'player_reclaimed_slot':
        HomeScreenUtils.showSuccessSnackBar(
          context,
          message['message'],
        );
        break;
        
      case 'card_drawn':
        onGameStateUpdate(message['game_state']);
        // Check if card details are present (only for the player who drew)
        if (message['card'] != null) {
          // This message is for the player who drew - show card details
          final card = message['card'] as Map<String, dynamic>;
          final cardType = card['type'] == 'number' 
              ? '${card['color']} ${card['value']}'
              : '${card['color']} ${card['type']}';
          HomeScreenUtils.showInfoSnackBar(
            context,
            'You drew a card: $cardType',
          );
        } else if (message['player_id'] != null) {
          // This message is for opponents - show generic message
          final gameState = message['game_state'] as Map<String, dynamic>;
          final players = gameState['players'] as List;
          final playerId = message['player_id'] as String;
          
          // Find the player who drew the card
          String? playerName;
          try {
            final player = players.firstWhere(
              (p) => (p as Map<String, dynamic>)['id'] == playerId,
            );
            playerName = (player as Map<String, dynamic>)['name'] as String?;
          } catch (e) {
            playerName = 'Opponent';
          }
          
          HomeScreenUtils.showInfoSnackBar(
            context,
            '$playerName drew a card',
          );
        }
        break;
        
      case 'card_played':
        onGameStateUpdate(message['game_state']);
        if (message['result']?['game_over'] == true) {
          HomeScreenUtils.showSuccessSnackBar(
            context,
            'Game Over! ${message['result']['winner']} wins!',
          );
        }
        break;
        
      case 'error':
        HomeScreenUtils.showErrorSnackBar(
          context,
          'Error: ${message['message']}',
        );
        break;
        
      case 'join_confirmed':
        HomeScreenUtils.showSuccessSnackBar(
          context,
          message['message'],
        );
        break;
        
      case 'pong':
        // Handle ping response silently
        break;
        
      default:
        print('Unknown message type: $messageType');
        print('Full message: $message');
    }
  }
}
