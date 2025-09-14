import 'package:flutter/material.dart';
import '../config/mobile_config.dart';

class UnoCardWidget extends StatelessWidget {
  final Map<String, dynamic> card;
  final bool isPlayable;
  final VoidCallback? onTap;
  final Animation<double>? animation;

  const UnoCardWidget({
    super.key,
    required this.card,
    this.isPlayable = false,
    this.onTap,
    this.animation,
  });

  @override
  Widget build(BuildContext context) {
    // Get responsive dimensions
    final isMobile = MobileConfig.isMobile(context);
    final isTablet = MobileConfig.isTablet(context);
    final isDesktop = MobileConfig.isDesktop(context);
    final cardDimensions = MobileConfig.getCardDimensions(context);

    // Responsive card sizing based on device type and card count
    final scaling = MobileConfig.getPlayerCardScaling(context, 1); // Default scaling
    final cardWidth = cardDimensions.width * scaling['width']!;
    final cardHeight = cardDimensions.height * scaling['height']!;
    final cardMargin = scaling['margin']!;

    return GestureDetector(
      onTap: isPlayable ? onTap : null,
      child: AnimatedBuilder(
        animation: animation ?? const AlwaysStoppedAnimation(0.0),
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + ((animation?.value ?? 0.0) * 0.15),
            child: Transform.rotate(
              angle: (animation?.value ?? 0.0) * 0.1,
              child: Container(
                width: cardWidth,
                height: cardHeight,
                margin: EdgeInsets.symmetric(horizontal: cardMargin),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _getCardColor(card['color']),
                      _getCardColor(card['color']).withOpacity(0.8),
                      _getCardColor(card['color']).withOpacity(0.9),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPlayable ? Colors.white : Colors.grey.shade400,
                    width: isPlayable ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: _buildCardContent(card, isMobile, isTablet, isDesktop),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardContent(Map<String, dynamic> card, bool isMobile, bool isTablet, bool isDesktop) {

    return Container(
      padding: EdgeInsets.all(isMobile ? 6 : (isTablet ? 7 : 8)),
      child: Column(
        children: [
          // Top left corner
          Align(
            alignment: Alignment.topLeft,
            child: _buildCardCorner(card, isTopLeft: true, isMobile: isMobile, isTablet: isTablet, isDesktop: isDesktop),
          ),

          // Center content
          Expanded(
            child: Center(
              child: _buildCardCenter(card, isMobile, isTablet, isDesktop),
            ),
          ),

          // Bottom right corner (rotated)
          Align(
            alignment: Alignment.bottomRight,
            child: Transform.rotate(
              angle: 3.14159, // 180 degrees
              child: _buildCardCorner(card, isTopLeft: false, isMobile: isMobile, isTablet: isTablet, isDesktop: isDesktop),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardCorner(Map<String, dynamic> card, {required bool isTopLeft, required bool isMobile, required bool isTablet, required bool isDesktop}) {
    final cardType = card['type'];
    final cardColor = card['color'];
    final cornerSize = isMobile ? 20.0 : (isTablet ? 22.0 : 24.0);
    final fontSize = isMobile ? 14.0 : (isTablet ? 15.0 : 16.0);
    final iconSize = isMobile ? 16.0 : (isTablet ? 18.0 : 20.0);

    return Container(
      width: cornerSize,
      height: cornerSize,
      child: cardType == 'number'
          ? Text(
              card['value'].toString(),
              style: TextStyle(
                color: _getTextColor(cardColor),
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.5),
                    offset: const Offset(1, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            )
          : _buildActionCornerIcon(cardType, cardColor, size: iconSize),
    );
  }

  Widget _buildCardCenter(Map<String, dynamic> card, bool isMobile, bool isTablet, bool isDesktop) {
    final cardType = card['type'];
    final cardColor = card['color'];

    final centerIconSize = isMobile ? 32.0 : (isTablet ? 36.0 : 40.0);
    final numberFontSize = isMobile ? 28.0 : (isTablet ? 30.0 : 32.0);
    final wildFontSize = isMobile ? 16.0 : (isTablet ? 17.0 : 18.0);
    final wildDraw4FontSize = isMobile ? 24.0 : (isTablet ? 26.0 : 28.0);
    final wildDraw4SubFontSize = isMobile ? 12.0 : (isTablet ? 13.0 : 14.0);
    final colorDotSize = isMobile ? 10.0 : (isTablet ? 11.0 : 12.0);
    final spacing = isMobile ? 3.0 : (isTablet ? 3.5 : 4.0);

    switch (cardType) {
      case 'number':
        return Text(
          card['value'].toString(),
          style: TextStyle(
            color: _getTextColor(cardColor),
            fontSize: numberFontSize,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.5),
                offset: const Offset(2, 2),
                blurRadius: 4,
              ),
            ],
          ),
        );
      case 'skip':
        return _buildActionIcon(Icons.skip_next, cardColor, size: centerIconSize);
      case 'reverse':
        return _buildActionIcon(Icons.swap_horiz, cardColor, size: centerIconSize);
      case 'draw2':
        return _buildActionIcon(Icons.add, cardColor, size: centerIconSize);
      case 'wild':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WILD',
              style: TextStyle(
                color: _getTextColor(cardColor),
                fontSize: wildFontSize,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.5),
                    offset: const Offset(1, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildColorDot('red', size: colorDotSize),
                SizedBox(width: spacing),
                _buildColorDot('blue', size: colorDotSize),
                SizedBox(width: spacing),
                _buildColorDot('green', size: colorDotSize),
                SizedBox(width: spacing),
                _buildColorDot('yellow', size: colorDotSize),
              ],
            ),
          ],
        );
      case 'wild_draw4':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+4',
              style: TextStyle(
                color: _getTextColor(cardColor),
                fontSize: wildDraw4FontSize,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.5),
                    offset: const Offset(1, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing),
            Text(
              'WILD',
              style: TextStyle(
                color: _getTextColor(cardColor),
                fontSize: wildDraw4SubFontSize,
                fontWeight: FontWeight.bold,
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
        );
      default:
        return Text(
          '?',
          style: TextStyle(
            color: _getTextColor(cardColor),
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        );
    }
  }

  Widget _buildActionIcon(dynamic icon, String cardColor, {required double size}) {
    return Icon(
      icon,
      color: _getTextColor(cardColor),
      size: size,
      shadows: [
        Shadow(
          color: Colors.black.withOpacity(0.5),
          offset: const Offset(1, 1),
          blurRadius: 2,
        ),
      ],
    );
  }

  Widget _buildActionCornerIcon(String cardType, String cardColor, {required double size}) {
    final cornerSize = size * 0.8; // Slightly smaller for corners

    switch (cardType) {
      case 'skip':
        return Icon(
          Icons.skip_next,
          color: _getTextColor(cardColor),
          size: cornerSize,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.5),
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        );
      case 'reverse':
        return Icon(
          Icons.swap_horiz,
          color: _getTextColor(cardColor),
          size: cornerSize,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.5),
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        );
      case 'draw2':
        return Icon(
          Icons.add,
          color: _getTextColor(cardColor),
          size: cornerSize,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.5),
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        );
      case 'wild':
        return Icon(
          Icons.color_lens,
          color: _getTextColor(cardColor),
          size: cornerSize,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.5),
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        );
      case 'wild_draw4':
        return Icon(
          Icons.add_circle,
          color: _getTextColor(cardColor),
          size: cornerSize,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.5),
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        );
      default:
        return Icon(
          Icons.help_outline,
          color: _getTextColor(cardColor),
          size: cornerSize,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.5),
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        );
    }
  }

  Widget _buildColorDot(String color, {required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _getCardColor(color),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }

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

  Color _getTextColor(String cardColor) {
    switch (cardColor.toLowerCase()) {
      case 'yellow':
        return const Color(0xFF744210); // Dark brown for yellow cards
      case 'black':
        return Colors.white;
      default:
        return Colors.white;
    }
  }
}
