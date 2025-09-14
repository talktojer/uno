import 'package:flutter/material.dart';
import '../config/mobile_config.dart';
import '../game_widgets/opponent_card_widget.dart';

class OpponentSection extends StatelessWidget {
  final Map<String, dynamic>? opponent;
  final double spacing;

  const OpponentSection({
    super.key,
    required this.opponent,
    required this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MobileConfig.isMobile(context);
    final isTablet = MobileConfig.isTablet(context);
    final isDesktop = MobileConfig.isDesktop(context);

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
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person,
                  color: Colors.white,
                  size: isMobile ? 18 : 20,
                ),
                SizedBox(width: spacing / 2),
                Text(
                  opponent?['name'] ?? 'Opponent',
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
          SizedBox(height: spacing * 0.625),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                opponent?['cards']?.length ?? 0,
                (index) => OpponentCardWidget(
                  cardCount: opponent?['cards']?.length ?? 0,
                  isMobile: isMobile,
                  isTablet: isTablet,
                  isDesktop: isDesktop,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
