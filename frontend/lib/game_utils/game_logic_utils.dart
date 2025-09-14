class GameLogicUtils {
  // Check if a card is playable
  static bool isCardPlayable(
    Map<String, dynamic> card,
    Map<String, dynamic> gameState,
    String playerId,
  ) {
    if (!gameState['game_started'] || gameState['winner'] != null) {
      return false;
    }

    final players = gameState['players'] as List;
    final currentPlayerIndex = gameState['current_player_index'] as int;

    // Check if it's my turn
    if (players[currentPlayerIndex]['id'] != playerId) {
      return false;
    }

    final currentColor = gameState['current_color'];
    final discardPile = gameState['discard_pile'] as List;

    if (discardPile.isEmpty) return true;

    final topCard = discardPile.last;

    // Wild cards can always be played
    if (card['type'] == 'wild' || card['type'] == 'wild_draw4') {
      return true;
    }

    // Check color match
    if (card['color'] == currentColor) {
      return true;
    }

    // Check value match for number cards
    if (card['type'] == 'number' &&
        topCard['type'] == 'number' &&
        card['value'] == topCard['value']) {
      return true;
    }

    // Check type match for action cards
    if (card['type'] != 'number' && card['type'] == topCard['type']) {
      return true;
    }

    return false;
  }

  // Check if it's the player's turn
  static bool isMyTurn(Map<String, dynamic> gameState, String playerId) {
    final players = gameState['players'] as List;
    final currentPlayerIndex = gameState['current_player_index'] as int;
    return players[currentPlayerIndex]['id'] == playerId;
  }

  // Get the current player
  static Map<String, dynamic>? getCurrentPlayer(Map<String, dynamic> gameState) {
    final players = gameState['players'] as List;
    final currentPlayerIndex = gameState['current_player_index'] as int;
    return players[currentPlayerIndex];
  }

  // Get the player by ID
  static Map<String, dynamic>? getPlayerById(Map<String, dynamic> gameState, String playerId) {
    final players = gameState['players'] as List;
    try {
      return players.firstWhere((p) => p['id'] == playerId);
    } catch (e) {
      return null;
    }
  }

  // Get the opponent (the other player)
  static Map<String, dynamic>? getOpponent(Map<String, dynamic> gameState, String playerId) {
    final players = gameState['players'] as List;
    try {
      return players.firstWhere((p) => p['id'] != playerId);
    } catch (e) {
      return null;
    }
  }

  // Check if game is over
  static bool isGameOver(Map<String, dynamic> gameState) {
    return gameState['winner'] != null;
  }

  // Check if game has started
  static bool isGameStarted(Map<String, dynamic> gameState) {
    return gameState['game_started'] == true;
  }
}
