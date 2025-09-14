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
        HomeScreenUtils.showInfoSnackBar(
          context,
          'Drew a card: ${message['card']['color']} ${message['card']['type']}',
        );
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
