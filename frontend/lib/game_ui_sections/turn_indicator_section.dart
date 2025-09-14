import 'package:flutter/material.dart';
import '../config/mobile_config.dart';

class TurnIndicatorSection extends StatelessWidget {
  final bool gameStarted;
  final bool isMyTurn;
  final Map<String, dynamic> currentPlayer;
  final double spacing;

  const TurnIndicatorSection({
    super.key,
    required this.gameStarted,
    required this.isMyTurn,
    required this.currentPlayer,
    required this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MobileConfig.isMobile(context);

    if (!gameStarted) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: spacing, vertical: spacing / 2),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: spacing * 1.5, vertical: spacing),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isMyTurn
                ? [
                    const Color(0xFFF6E05E), // Bright yellow
                    const Color(0xFFECC94B), // Medium yellow
                    const Color(0xFFD69E2E), // Dark yellow
                  ]
                : [
                    const Color(0xFFA0AEC0), // Light gray
                    const Color(0xFF718096), // Medium gray
                    const Color(0xFF4A5568), // Dark gray
                  ],
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isMyTurn
                ? Colors.white
                : Colors.white.withOpacity(0.6),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMyTurn) ...[
              Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: isMobile ? 20 : 24,
              ),
              SizedBox(width: spacing / 2),
            ],
            Text(
              isMyTurn
                  ? 'YOUR TURN!'
                  : '${currentPlayer['name']}\'s turn',
              style: TextStyle(
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.5),
                    offset: const Offset(1, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
