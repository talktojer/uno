import 'package:flutter/material.dart';
import '../config/mobile_config.dart';
import '../game_widgets/uno_card_widget.dart';

class PlayerCardsSection extends StatelessWidget {
  final Map<String, dynamic>? myPlayer;
  final Map<String, dynamic> gameState;
  final String playerName;
  final bool gameStarted;
  final bool isMyTurn;
  final String playerId;
  final Animation<double>? cardAnimation;
  final Function(int) onCardTap;
  final VoidCallback onDrawCard;

  const PlayerCardsSection({
    super.key,
    required this.myPlayer,
    required this.gameState,
    required this.playerName,
    required this.gameStarted,
    required this.isMyTurn,
    required this.playerId,
    this.cardAnimation,
    required this.onCardTap,
    required this.onDrawCard,
  });

  bool _isCardPlayable(Map<String, dynamic> card) {
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

  @override
  Widget build(BuildContext context) {
    final isMobile = MobileConfig.isMobile(context);
    final spacing = MobileConfig.getSpacing(context);
    final buttonHeight = MobileConfig.getButtonHeight(context);

    if (myPlayer == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(spacing),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: spacing * 1.25,
                vertical: spacing * 0.75),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.4),
                  Colors.white.withOpacity(0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: Colors.white.withOpacity(0.8),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                    size: isMobile ? 16 : 18,
                  ),
                ),
                SizedBox(width: spacing / 2),
                Text(
                  '$playerName (You)',
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        offset: const Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing),
          Container(
            height: MobileConfig.getPlayerCardsHeight(context),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  myPlayer!['cards'].length,
                  (index) => UnoCardWidget(
                    card: myPlayer!['cards'][index],
                    isPlayable: _isCardPlayable(myPlayer!['cards'][index]),
                    onTap: gameStarted && isMyTurn
                        ? () => onCardTap(index)
                        : null,
                    animation: cardAnimation,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: spacing * 1.25),
          if (gameStarted && isMyTurn)
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFED8936), // Orange
                      Color(0xFFDD6B20), // Dark orange
                    ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: onDrawCard,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(vertical: spacing),
                    minimumSize: Size(0, buttonHeight),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline,
                          size: isMobile ? 20 : 24),
                      SizedBox(width: spacing / 2),
                      Text(
                        'Draw Card',
                        style: TextStyle(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
