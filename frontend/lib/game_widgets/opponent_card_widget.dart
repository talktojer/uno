import 'package:flutter/material.dart';
import '../config/mobile_config.dart';

class OpponentCardWidget extends StatelessWidget {
  final int cardCount;
  final bool isMobile;
  final bool isTablet;
  final bool isDesktop;

  const OpponentCardWidget({
    super.key,
    required this.cardCount,
    required this.isMobile,
    required this.isTablet,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final cardDimensions = MobileConfig.getCardDimensions(context);
    
    // Responsive opponent card sizing
    double oppCardWidth, oppCardHeight, oppCardMargin;

    if (isMobile) {
      if (cardCount <= 4) {
        oppCardWidth = cardDimensions.width * 0.75;
        oppCardHeight = cardDimensions.height * 0.7;
        oppCardMargin = 1.0;
      } else if (cardCount <= 6) {
        oppCardWidth = cardDimensions.width * 0.67;
        oppCardHeight = cardDimensions.height * 0.62;
        oppCardMargin = 0.75;
      } else if (cardCount <= 8) {
        oppCardWidth = cardDimensions.width * 0.58;
        oppCardHeight = cardDimensions.height * 0.54;
        oppCardMargin = 0.5;
      } else {
        oppCardWidth = cardDimensions.width * 0.5;
        oppCardHeight = cardDimensions.height * 0.47;
        oppCardMargin = 0.25;
      }
    } else if (isTablet) {
      if (cardCount <= 4) {
        oppCardWidth = cardDimensions.width * 0.85;
        oppCardHeight = cardDimensions.height * 0.8;
        oppCardMargin = 1.5;
      } else if (cardCount <= 6) {
        oppCardWidth = cardDimensions.width * 0.75;
        oppCardHeight = cardDimensions.height * 0.7;
        oppCardMargin = 1.25;
      } else if (cardCount <= 8) {
        oppCardWidth = cardDimensions.width * 0.67;
        oppCardHeight = cardDimensions.height * 0.62;
        oppCardMargin = 1.0;
      } else {
        oppCardWidth = cardDimensions.width * 0.58;
        oppCardHeight = cardDimensions.height * 0.54;
        oppCardMargin = 0.75;
      }
    } else {
      if (cardCount <= 4) {
        oppCardWidth = cardDimensions.width * 0.9;
        oppCardHeight = cardDimensions.height * 0.85;
        oppCardMargin = 2.0;
      } else if (cardCount <= 6) {
        oppCardWidth = cardDimensions.width * 0.8;
        oppCardHeight = cardDimensions.height * 0.75;
        oppCardMargin = 1.75;
      } else if (cardCount <= 8) {
        oppCardWidth = cardDimensions.width * 0.7;
        oppCardHeight = cardDimensions.height * 0.65;
        oppCardMargin = 1.5;
      } else {
        oppCardWidth = cardDimensions.width * 0.6;
        oppCardHeight = cardDimensions.height * 0.55;
        oppCardMargin = 1.25;
      }
    }

    return Container(
      width: oppCardWidth,
      height: oppCardHeight,
      margin: EdgeInsets.symmetric(horizontal: oppCardMargin),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.style,
          color: Colors.white.withOpacity(0.8),
          size: isMobile ? 14 : (isTablet ? 18 : 20),
        ),
      ),
    );
  }
}
