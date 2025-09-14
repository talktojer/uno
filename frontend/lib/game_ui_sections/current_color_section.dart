import 'package:flutter/material.dart';
import '../config/mobile_config.dart';

class CurrentColorSection extends StatelessWidget {
  final bool gameStarted;
  final String currentColor;
  final double spacing;

  const CurrentColorSection({
    super.key,
    required this.gameStarted,
    required this.currentColor,
    required this.spacing,
  });

  Color _getCardColor(String colorString) {
    switch (colorString.toLowerCase()) {
      case 'red':
        return const Color(0xFFE53E3E); // Vibrant red
      case 'blue':
        return const Color(0xFF3182CE); // Vibrant blue
      case 'green':
        return const Color(0xFF38A169); // Vibrant green
      case 'yellow':
        return const Color(0xFFD69E2E); // Vibrant yellow
      case 'black':
        return const Color(0xFF2D3748); // Dark gray
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MobileConfig.isMobile(context);
    final isTablet = MobileConfig.isTablet(context);

    if (!gameStarted) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(spacing),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: spacing * 1.5, vertical: spacing),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.3),
              Colors.white.withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: Colors.white.withOpacity(0.6),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Current Color: ',
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
            Container(
              width: isMobile ? 32 : (isTablet ? 36 : 40),
              height: isMobile ? 32 : (isTablet ? 36 : 40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _getCardColor(currentColor),
                    _getCardColor(currentColor).withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
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
