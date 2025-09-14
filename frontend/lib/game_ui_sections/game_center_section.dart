import 'package:flutter/material.dart';
import '../config/mobile_config.dart';
import '../game_widgets/uno_card_widget.dart';

class GameCenterSection extends StatelessWidget {
  final Map<String, dynamic> gameState;
  final double spacing;

  const GameCenterSection({
    super.key,
    required this.gameState,
    required this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MobileConfig.isMobile(context);
    final isTablet = MobileConfig.isTablet(context);
    final cardDimensions = MobileConfig.getCardDimensions(context);
    final discardPile = gameState['discard_pile'] as List;

    return Container(
      height: MobileConfig.getGameCenterHeight(context),
      padding: EdgeInsets.all(spacing),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Draw pile
          Container(
            width: cardDimensions.width * 0.75,
            height: cardDimensions.height * 0.85,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2D3748),
                  Color(0xFF4A5568),
                  Color(0xFF2D3748),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: isMobile ? 28 : (isTablet ? 36 : 40),
                  height: isMobile ? 28 : (isTablet ? 36 : 40),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(
                        isMobile ? 14 : (isTablet ? 18 : 20)),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.style,
                    color: Colors.white,
                    size: isMobile ? 16 : (isTablet ? 20 : 24),
                  ),
                ),
                SizedBox(
                    height: isMobile ? 4 : (isTablet ? 6 : 8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 4 : (isTablet ? 6 : 8),
                    vertical: isMobile ? 2 : (isTablet ? 3 : 4),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${gameState['deck']?.length ?? 0}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 10 : (isTablet ? 12 : 14),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Discard pile
          Container(
            width: cardDimensions.width * 0.75,
            height: cardDimensions.height * 0.85,
            child: discardPile.isNotEmpty
                ? UnoCardWidget(
                    card: discardPile.last,
                    isPlayable: false,
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 2),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.inbox,
                        color: Colors.white.withOpacity(0.6),
                        size: isMobile ? 20 : (isTablet ? 26 : 30),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
