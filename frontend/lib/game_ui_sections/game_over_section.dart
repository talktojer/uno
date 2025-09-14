import 'package:flutter/material.dart';
import '../config/mobile_config.dart';
import '../screens/home_screen.dart';

class GameOverSection extends StatelessWidget {
  final String winner;
  final List<Map<String, dynamic>> players;

  const GameOverSection({
    super.key,
    required this.winner,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MobileConfig.isMobile(context);
    final spacing = MobileConfig.getSpacing(context);
    final buttonHeight = MobileConfig.getButtonHeight(context);

    final winnerName = players.firstWhere((p) => p['id'] == winner)['name'];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.green, Colors.blue],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(spacing),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(spacing * 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.emoji_events,
                          size: isMobile ? 80 : 100,
                          color: Colors.yellow,
                        ),
                        SizedBox(height: spacing),
                        Text(
                          'Game Over!',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        SizedBox(height: spacing),
                        Text(
                          'Winner: $winnerName',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: spacing * 2),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const HomeScreen()),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: spacing * 2, vertical: spacing),
                        minimumSize: Size(0, buttonHeight),
                      ),
                      child: const Text('Back to Home'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
