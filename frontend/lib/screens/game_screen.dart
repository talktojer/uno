import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:html' as html;
import '../game_services/game_websocket_service.dart';
import '../game_services/game_api_service.dart';
import '../game_dialogs/color_picker_dialog.dart';
import '../game_dialogs/share_dialog.dart';
import '../game_dialogs/connection_dialog.dart';
import '../game_ui_sections/opponent_section.dart';
import '../game_ui_sections/game_center_section.dart';
import '../game_ui_sections/player_cards_section.dart';
import '../game_ui_sections/turn_indicator_section.dart';
import '../game_ui_sections/current_color_section.dart';
import '../game_ui_sections/game_over_section.dart';
import '../game_utils/game_logic_utils.dart';
import '../game_utils/game_message_handler.dart';
import '../config/mobile_config.dart';
import '../utils/home_screen_utils.dart';

class GameScreen extends StatefulWidget {
  final String gameId;
  final String playerId;
  final String playerName;

  const GameScreen({
    super.key,
    required this.gameId,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Map<String, dynamic>? _gameState;
  final GameWebSocketService _webSocketService = GameWebSocketService();
  late AnimationController _cardAnimationController;
  late Animation<double> _cardAnimation;

  // Add window resize listener for responsive updates
  StreamSubscription<html.Event>? _resizeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _cardAnimation = CurvedAnimation(
      parent: _cardAnimationController,
      curve: Curves.elasticOut,
    );
    _connectWebSocket();
    _setupResizeListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webSocketService.dispose();
    _cardAnimationController.dispose();
    _resizeSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _checkAndReconnectIfNeeded();
        break;
      default:
        // Keep connection alive for other states
        break;
    }
  }

  void _checkAndReconnectIfNeeded() {
    if (!_webSocketService.isConnected &&
        !_webSocketService.isReconnecting &&
        !_webSocketService.isConnecting) {
      _checkSlotReclamation();
    }
  }

  void _setupResizeListener() {
    try {
      _resizeSubscription = html.window.onResize.listen((event) {
        if (mounted) {
          setState(() {});
        }
      });
    } catch (e) {
      print('Could not setup resize listener: $e');
    }
  }

  void _connectWebSocket() {
    _webSocketService.connect(widget.gameId, widget.playerId, widget.playerName);
    
    _webSocketService.messageStream.listen((message) {
      GameMessageHandler.handleMessage(
        context,
        message,
        (gameState) {
          setState(() {
            _gameState = gameState;
          });
        },
      );
    });

    // Fallback: fetch initial game state via HTTP if WebSocket doesn't provide it
    Timer(const Duration(seconds: 2), () {
      if (_gameState == null) {
        _fetchGameStateFallback();
      }
    });

    // Connection timeout: if we're still connecting after 15 seconds, show an error
    Timer(const Duration(seconds: 15), () {
      if (_webSocketService.isConnecting && !_webSocketService.isConnected) {
        setState(() {});
        HomeScreenUtils.showErrorSnackBar(
          context,
          'Connection timeout. Please check your internet connection.',
        );
      }
    });
  }

  Future<void> _fetchGameStateFallback() async {
    try {
      final gameState = await GameApiService.fetchGameState(widget.gameId);
      if (gameState != null && mounted) {
        setState(() {
          _gameState = gameState;
        });
      }
    } catch (e) {
      print('Fallback HTTP request failed: $e');
    }
  }

  Future<void> _checkSlotReclamation() async {
    try {
      setState(() {});
      final data = await GameApiService.checkSlotReclamation(widget.gameId, widget.playerId);
      
      if (data['can_reclaim'] == true) {
        _webSocketService.setCanReclaimSlot(true);
        setState(() {});
        await _reclaimSlot();
      } else {
        _webSocketService.setCanReclaimSlot(false);
        setState(() {});
        _manualReconnect();
      }
    } catch (e) {
      _webSocketService.setCanReclaimSlot(false);
      setState(() {});
      _manualReconnect();
    }
  }

  Future<void> _reclaimSlot() async {
    try {
      await GameApiService.reclaimSlot(
        widget.gameId,
        widget.playerId,
        widget.playerName,
      );
      
      HomeScreenUtils.showSuccessSnackBar(
        context,
        'Successfully reclaimed your slot!',
      );
      
      _webSocketService.setCanReclaimSlot(false);
      setState(() {});
    } catch (e) {
      _webSocketService.setCanReclaimSlot(false);
      setState(() {});
      _manualReconnect();
    }
  }

  void _manualReconnect() {
    _webSocketService.reconnect();
    setState(() {});
  }

  void _manualSlotReclamation() {
    _checkSlotReclamation();
  }

  Future<void> _startGame() async {
    _webSocketService.sendMessage({'type': 'start_game'});
  }

  Future<void> _playCard(int cardIndex) async {
    if (_gameState == null) return;

    // Check if it's actually my turn
    if (!GameLogicUtils.isMyTurn(_gameState!, widget.playerId)) {
      HomeScreenUtils.showWarningSnackBar(context, 'Not your turn!');
      return;
    }

    // Check if game is started and active
    if (!GameLogicUtils.isGameStarted(_gameState!) || GameLogicUtils.isGameOver(_gameState!)) {
      HomeScreenUtils.showWarningSnackBar(context, 'Game is not active!');
      return;
    }

    final myPlayer = GameLogicUtils.getPlayerById(_gameState!, widget.playerId);
    if (myPlayer == null || cardIndex >= myPlayer['cards'].length) {
      HomeScreenUtils.showErrorSnackBar(context, 'Invalid card!');
      return;
    }

    final card = myPlayer['cards'][cardIndex];
    if (!GameLogicUtils.isCardPlayable(card, _gameState!, widget.playerId)) {
      HomeScreenUtils.showErrorSnackBar(context, 'This card cannot be played!');
      return;
    }

    // Handle wild card color selection
    String? newColor;
    if (card['type'] == 'wild' || card['type'] == 'wild_draw4') {
      newColor = await ColorPickerDialog.show(context);
      if (newColor == null) {
        return; // User cancelled color selection
      }
    }

    _cardAnimationController.forward().then((_) {
      _cardAnimationController.reverse();
    });

    _webSocketService.sendMessage({
      'type': 'play_card',
      'card_index': cardIndex,
      'new_color': newColor,
    });
  }

  Future<void> _drawCard() async {
    if (_gameState == null) return;

    // Check if it's actually my turn
    if (!GameLogicUtils.isMyTurn(_gameState!, widget.playerId)) {
      HomeScreenUtils.showWarningSnackBar(context, 'Not your turn!');
      return;
    }

    // Check if game is started and active
    if (!GameLogicUtils.isGameStarted(_gameState!) || GameLogicUtils.isGameOver(_gameState!)) {
      HomeScreenUtils.showWarningSnackBar(context, 'Game is not active!');
      return;
    }

    _webSocketService.sendMessage({'type': 'draw_card'});
  }

  void _showShareDialog() {
    if (_gameState == null || _gameState!['game_code'] == null) return;
    ShareDialog.show(context, _gameState!['game_code']);
  }

  void _showConnectionDialog() {
    ConnectionDialog.show(
      context,
      isConnected: _webSocketService.isConnected,
      isConnecting: _webSocketService.isConnecting,
      isReconnecting: _webSocketService.isReconnecting,
      onReconnect: _manualReconnect,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_gameState == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading game...'),
            ],
          ),
        ),
      );
    }

    final players = _gameState!['players'] as List;
    final currentPlayer = GameLogicUtils.getCurrentPlayer(_gameState!);
    final myPlayer = GameLogicUtils.getPlayerById(_gameState!, widget.playerId);
    final opponent = GameLogicUtils.getOpponent(_gameState!, widget.playerId);
    final gameStarted = GameLogicUtils.isGameStarted(_gameState!);
    final winner = _gameState!['winner'];
    final currentColor = _gameState!['current_color'];
    final isMyTurn = GameLogicUtils.isMyTurn(_gameState!, widget.playerId);

    // Show game over screen if there's a winner
    if (winner != null) {
      return GameOverSection(
        winner: winner,
        players: players.cast<Map<String, dynamic>>(),
      );
    }

    final isMobile = MobileConfig.isMobile(context);
    final spacing = MobileConfig.getSpacing(context);
    final buttonHeight = MobileConfig.getButtonHeight(context);
    final bottomPadding = MobileConfig.getBottomPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('UNO - ${widget.gameId}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
        centerTitle: true,
        actions: [
          // Connection status indicator
          GestureDetector(
            onTap: _showConnectionDialog,
            child: Container(
              margin: EdgeInsets.only(right: spacing / 2),
              padding: EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _webSocketService.isConnected
                          ? Colors.green
                          : _webSocketService.isConnecting
                              ? Colors.blue
                              : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (_webSocketService.isConnecting || _webSocketService.isReconnecting) ...[
                    const SizedBox(width: 4),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_gameState != null && _gameState!['game_code'] != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _showShareDialog,
            ),
        ],
      ),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // Connection status banner
                        if (!_webSocketService.isConnected)
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: spacing, vertical: spacing / 2),
                            color: _webSocketService.isConnecting
                                ? Colors.blue
                                : _webSocketService.isReconnecting
                                    ? Colors.orange
                                    : Colors.red,
                            child: Row(
                              children: [
                                Icon(
                                  _webSocketService.isConnecting
                                      ? Icons.wifi
                                      : _webSocketService.isReconnecting
                                          ? Icons.wifi_find
                                          : Icons.wifi_off,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: spacing / 2),
                                Expanded(
                                  child: Text(
                                    _webSocketService.isConnecting
                                        ? 'Connecting to game server...'
                                        : _webSocketService.isReconnecting
                                            ? 'Reconnecting to game server...'
                                            : _webSocketService.canReclaimSlot
                                                ? 'Your slot is available to reclaim!'
                                                : 'Disconnected from game server',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (!_webSocketService.isReconnecting) ...[
                                  if (_webSocketService.canReclaimSlot)
                                    TextButton(
                                      onPressed: _manualSlotReclamation,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(
                                            horizontal: spacing / 2),
                                      ),
                                      child: const Text('RECLAIM SLOT'),
                                    ),
                                  if (_webSocketService.canReclaimSlot)
                                    SizedBox(width: spacing / 2),
                                  if (!_webSocketService.isConnecting && !_webSocketService.isConnected)
                                    TextButton(
                                      onPressed: _manualReconnect,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(
                                            horizontal: spacing / 2),
                                      ),
                                      child: const Text('RECONNECT'),
                                    ),
                                ],
                              ],
                            ),
                          ),

                        // Opponent's cards
                        OpponentSection(
                          opponent: opponent,
                          spacing: spacing,
                        ),

                        // Turn indicator
                        TurnIndicatorSection(
                          gameStarted: gameStarted,
                          isMyTurn: isMyTurn,
                          currentPlayer: currentPlayer!,
                          spacing: spacing,
                        ),

                        // Game center area
                        GameCenterSection(
                          gameState: _gameState!,
                          spacing: spacing,
                        ),

                        // Current color indicator
                        CurrentColorSection(
                          gameStarted: gameStarted,
                          currentColor: currentColor,
                          spacing: spacing,
                        ),

                        // My cards
                        if (myPlayer != null)
                          PlayerCardsSection(
                            myPlayer: myPlayer,
                            gameState: _gameState!,
                            playerName: widget.playerName,
                            gameStarted: gameStarted,
                            isMyTurn: isMyTurn,
                            playerId: widget.playerId,
                            cardAnimation: _cardAnimation,
                            onCardTap: _playCard,
                            onDrawCard: _drawCard,
                          ),

                        // Start game button
                        if (!gameStarted && players.length == 2)
                          Container(
                            padding: EdgeInsets.all(spacing),
                            child: SizedBox(
                              width: double.infinity,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF48BB78), // Green
                                      Color(0xFF38A169), // Dark green
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _startGame,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    padding: EdgeInsets.symmetric(
                                        vertical: spacing * 1.25),
                                    minimumSize: Size(0, buttonHeight),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.play_circle_filled,
                                          size: isMobile ? 24 : 28),
                                      SizedBox(width: isMobile ? 8 : 12),
                                      Text(
                                        'Start Game',
                                        style: TextStyle(
                                          fontSize: isMobile ? 18 : 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Responsive bottom padding
                        SizedBox(height: bottomPadding),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
