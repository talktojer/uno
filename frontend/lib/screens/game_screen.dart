import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/services.dart';
import '../websocket/websocket_manager.dart';
import '../config/app_config.dart';
import '../config/mobile_config.dart';
import '../models/uno_card.dart';
import 'home_screen.dart';

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
  WebSocketManager? _gameWebSocket;
  late AnimationController _cardAnimationController;
  late Animation<double> _cardAnimation;
  bool _isConnected = false;
  bool _isConnecting = true; // Start as connecting, not disconnected
  bool _isReconnecting = false;
  bool _canReclaimSlot = false;

  // Add window resize listener for responsive updates
  StreamSubscription<html.Event>? _resizeSubscription;

  // Helper method for consistent border radius
  static BorderRadius get _borderRadius => BorderRadius.circular(8);

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

    // Add window resize listener for responsive updates
    _setupResizeListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gameWebSocket?.disconnect();
    _cardAnimationController.dispose();
    _resizeSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('App resumed - checking WebSocket connection');
        _checkAndReconnectIfNeeded();
        break;
      case AppLifecycleState.paused:
        print('App paused - maintaining WebSocket connection');
        // Keep connection alive, don't disconnect
        break;
      case AppLifecycleState.inactive:
        print('App inactive - maintaining WebSocket connection');
        // Keep connection alive, don't disconnect
        break;
      case AppLifecycleState.detached:
        print('App detached - maintaining WebSocket connection');
        // Keep connection alive, don't disconnect
        break;
      case AppLifecycleState.hidden:
        print('App hidden - maintaining WebSocket connection');
        // Keep connection alive, don't disconnect
        break;
    }
  }

  void _checkAndReconnectIfNeeded() {
    if (_gameWebSocket != null &&
        !_gameWebSocket!.isConnected &&
        !_isReconnecting &&
        !_isConnecting) {
      print('WebSocket not connected, attempting to reconnect...');
      setState(() {
        _isConnecting = true;
      });
      _checkSlotReclamation();
    }
  }

  // Setup window resize listener for responsive updates
  void _setupResizeListener() {
    try {
      _resizeSubscription = html.window.onResize.listen((event) {
        // Force rebuild when window is resized to update responsive layout
        if (mounted) {
          setState(() {});
        }
      });
    } catch (e) {
      print('Could not setup resize listener: $e');
    }
  }

  Future<void> _checkSlotReclamation() async {
    try {
      print('Checking if we can reclaim our slot...');
      setState(() {
        _isConnecting = true;
      });

      // Check if we can reclaim our slot
      final response = await http.get(
        Uri.parse(
            '$apiBaseUrl/api/games/${widget.gameId}/can-reclaim/${widget.playerId}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['can_reclaim'] == true) {
          print('Slot reclamation possible, attempting to reclaim...');
          setState(() {
            _canReclaimSlot = true;
          });
          await _reclaimSlot();
        } else {
          print('Cannot reclaim slot: ${data['reason']}');
          setState(() {
            _canReclaimSlot = false;
            _isConnecting = false;
          });
          // Fall back to manual reconnection
          _manualReconnect();
        }
      } else {
        print('Failed to check slot reclamation: ${response.statusCode}');
        setState(() {
          _canReclaimSlot = false;
          _isConnecting = false;
        });
        // Fall back to manual reconnection
        _manualReconnect();
      }
    } catch (e) {
      print('Error checking slot reclamation: $e');
      setState(() {
        _isConnecting = false;
      });
      // Fall back to manual reconnection
      _manualReconnect();
    }
  }

  Future<void> _reclaimSlot() async {
    try {
      print('Reclaiming our slot...');
      setState(() {
        _isConnecting = true;
      });

      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/games/${widget.gameId}/reclaim-slot'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'original_player_id': widget.playerId,
          'player_name': widget.playerName,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Successfully reclaimed slot: ${data['message']}');

        // Update our player ID to the new one
        // Note: In a real implementation, you might want to update the widget's playerId
        // For now, we'll just show a success message and let the WebSocket handle updates

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully reclaimed your slot!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );

        // The WebSocket should automatically reconnect and update the game state
        setState(() {
          _isConnecting = false;
          _isReconnecting = false;
        });
      } else {
        print(
            'Failed to reclaim slot: ${response.statusCode} - ${response.body}');
        setState(() {
          _isConnecting = false;
        });
        // Fall back to manual reconnection
        _manualReconnect();
      }
    } catch (e) {
      print('Error reclaiming slot: $e');
      setState(() {
        _isConnecting = false;
      });
      // Fall back to manual reconnection
      _manualReconnect();
    }
  }

  void _handleNetworkChange() {
    // Check connection status when network changes
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _gameWebSocket != null && !_gameWebSocket!.isConnected) {
        print('Network changed, checking WebSocket connection...');
        _checkAndReconnectIfNeeded();
      }
    });
  }

  void _connectWebSocket() {
    final wsUrl = '$wsBaseUrl/ws/${widget.gameId}/${widget.playerId}';
    print('Connecting to WebSocket: $wsUrl');
    print(
        'GameScreen: Starting WebSocket connection for game ${widget.gameId}, player ${widget.playerId}'); // Debug log
    _gameWebSocket = WebSocketManager();
    _gameWebSocket!.connect(wsUrl);

    _gameWebSocket!.onMessage = (message) {
      print('WebSocket received: $message'); // Debug log
      final messageData = message;
      if (messageData['type'] == 'game_update') {
        setState(() {
          _gameState = messageData['game_state'];
        });
        print('Game state updated: ${messageData['game_state']}'); // Debug log
      } else if (messageData['type'] == 'game_started') {
        // Don't update game state here - it should come from the game_update message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Game started! ${messageData['message']}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        print('Game started: ${messageData['message']}'); // Debug log
      } else if (messageData['type'] == 'player_replaced') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${messageData['message']}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.blue,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        print('Player replaced: ${messageData['message']}'); // Debug log
      } else if (messageData['type'] == 'player_disconnected') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${messageData['message']}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        print('Player disconnected: ${messageData['message']}'); // Debug log

        // Check if we can reclaim our slot when opponent disconnects
        _checkSlotReclamation();
      } else if (messageData['type'] == 'player_reclaimed_slot') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${messageData['message']}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        print('Player reclaimed slot: ${messageData['message']}'); // Debug log
      } else if (messageData['type'] == 'card_drawn') {
        // Update game state with the new card drawn information
        setState(() {
          _gameState = messageData['game_state'];
        });
        print('Card drawn: ${messageData['card']}'); // Debug log
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Drew a card: ${messageData['card']['color']} ${messageData['card']['type']}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.purple,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
      } else if (messageData['type'] == 'card_played') {
        // Update game state after a card is played
        setState(() {
          _gameState = messageData['game_state'];
        });
        print('Card played: ${messageData['result']}'); // Debug log
        if (messageData['result']?['game_over'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Game Over! ${messageData['result']['winner']} wins!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.amber,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else if (messageData['type'] == 'error') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${messageData['message']}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
      } else if (messageData['type'] == 'pong') {
        print('Pong received'); // Debug log
      } else if (messageData['type'] == 'join_confirmed') {
        print('Join confirmed: ${messageData['message']}'); // Debug log
        // Player successfully joined the game via WebSocket
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(messageData['message']),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
      } else {
        print('Unknown message type: ${messageData['type']}'); // Debug log
        print('Full message: $messageData'); // Debug log
      }
    };

    _gameWebSocket!.onError = (error) {
      print('WebSocket error: $error'); // Debug log
      print(
          'WebSocket error details: ${error.toString()}'); // Additional debug info
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _isReconnecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('WebSocket error: $error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      );
    };

    _gameWebSocket!.onConnected = () {
      print('WebSocket connected');
      print(
          'GameScreen: WebSocket connection established for game ${widget.gameId}'); // Debug log
      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _isReconnecting = false;
      });

      // Wait a bit for the connection to be fully stable before sending messages
      Timer(const Duration(milliseconds: 1000), () {
        if (_gameWebSocket != null && _gameWebSocket!.isConnected) {
          print('Sending initial messages after connection stabilization');

          // Send a ping to confirm the connection is working
          _gameWebSocket!.send({'type': 'ping'});

          // Also send a join message to ensure the server knows we're here
          _gameWebSocket!.send({
            'type': 'join_game',
            'game_id': widget.gameId,
            'player_id': widget.playerId,
            'player_name': widget.playerName,
          });
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to game server'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    };

    _gameWebSocket!.onDisconnected = () {
      print('WebSocket connection closed');
      print(
          'GameScreen: WebSocket connection lost for game ${widget.gameId}'); // Debug log
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _isReconnecting = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Connection lost. Attempting to reconnect...'),
          backgroundColor: Colors.orange,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    };

    // Note: Ping is handled by WebSocketManager, no need for duplicate timer here

    // Fallback: fetch initial game state via HTTP if WebSocket doesn't provide it
    Timer(const Duration(seconds: 2), () {
      if (_gameState == null) {
        print('WebSocket fallback: fetching game state via HTTP');
        _fetchGameStateFallback();
      }
    });

    // Connection timeout: if we're still connecting after 15 seconds, show an error
    Timer(const Duration(seconds: 15), () {
      if (_isConnecting && !_isConnected) {
        print('Connection timeout - still connecting after 15 seconds');
        setState(() {
          _isConnecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Connection timeout. Please check your internet connection.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    });

    // Also add a shorter timeout for the initial connection attempt
    Timer(const Duration(seconds: 8), () {
      if (_isConnecting && !_isConnected) {
        print('Initial connection attempt taking longer than expected...');
        // Don't show an error yet, just log it
      }
    });
  }

  Future<void> _fetchGameStateFallback() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/games/${widget.gameId}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _gameState = data;
        });
        print('Fallback game state loaded: $data');
      }
    } catch (e) {
      print('Fallback HTTP request failed: $e');
    }
  }

  Future<void> _startGame() async {
    if (_gameWebSocket != null) {
      _gameWebSocket!.send({
        'type': 'start_game',
      });
    }
  }

  Future<void> _playCard(int cardIndex) async {
    if (_gameWebSocket != null && _gameState != null) {
      // Check if it's actually my turn
      final players = _gameState!['players'] as List;
      final currentPlayerIndex = _gameState!['current_player_index'] as int;
      final isMyTurn = players[currentPlayerIndex]['id'] == widget.playerId;

      if (!isMyTurn) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Not your turn!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        return;
      }

      // Check if game is started and active
      if (!_gameState!['game_started'] || _gameState!['winner'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Game is not active!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        return;
      }

      // Check if the card is actually playable
      final myPlayer = players.firstWhere(
        (p) => p['id'] == widget.playerId,
        orElse: () => null,
      );

      if (myPlayer == null || cardIndex >= myPlayer['cards'].length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid card!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        return;
      }

      final card = myPlayer['cards'][cardIndex];
      if (!_isCardPlayable(card, _gameState!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('This card cannot be played!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        return;
      }

      // Handle wild card color selection
      String? newColor;
      if (card['type'] == 'wild' || card['type'] == 'wild_draw4') {
        newColor = await _showColorPicker();
        if (newColor == null) {
          return; // User cancelled color selection
        }
      }

      _cardAnimationController.forward().then((_) {
        _cardAnimationController.reverse();
      });

      _gameWebSocket!.send({
        'type': 'play_card',
        'card_index': cardIndex,
        'new_color': newColor,
      });
    }
  }

  Future<String?> _showColorPicker() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choose a Color'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                title: const Text('Red'),
                onTap: () => Navigator.of(context).pop('red'),
              ),
              ListTile(
                leading: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                title: const Text('Blue'),
                onTap: () => Navigator.of(context).pop('blue'),
              ),
              ListTile(
                leading: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                title: const Text('Green'),
                onTap: () => Navigator.of(context).pop('green'),
              ),
              ListTile(
                leading: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.yellow,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                title: const Text('Yellow'),
                onTap: () => Navigator.of(context).pop('yellow'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _drawCard() async {
    if (_gameWebSocket != null && _gameState != null) {
      // Check if it's actually my turn
      final players = _gameState!['players'] as List;
      final currentPlayerIndex = _gameState!['current_player_index'] as int;
      final isMyTurn = players[currentPlayerIndex]['id'] == widget.playerId;

      if (!isMyTurn) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Not your turn!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        return;
      }

      // Check if game is started and active
      if (!_gameState!['game_started'] || _gameState!['winner'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Game is not active!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        return;
      }

      _gameWebSocket!.send({
        'type': 'draw_card',
      });
    }
  }

  void _showShareDialog() {
    if (_gameState == null || _gameState!['game_code'] == null) return;

    final gameCode = _gameState!['game_code'];
    final shareUrl = '$baseUrl/$gameCode';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Share Game'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Game Code: $gameCode'),
              const SizedBox(height: 16),
              Text('Share this URL with others:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey),
                ),
                child: SelectableText(
                  shareUrl,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                // Copy to clipboard
                html.window.navigator.clipboard?.writeText(shareUrl);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Game URL copied to clipboard!'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: _borderRadius),
                  ),
                );
                Navigator.of(context).pop();
              },
              child: const Text('Copy URL'),
            ),
          ],
        );
      },
    );
  }

  bool _isCardPlayable(
      Map<String, dynamic> card, Map<String, dynamic> gameState) {
    if (!gameState['game_started'] || gameState['winner'] != null) {
      return false;
    }

    final players = gameState['players'] as List;
    final currentPlayerIndex = gameState['current_player_index'] as int;
    final myPlayer = players.firstWhere(
      (p) => p['id'] == widget.playerId,
      orElse: () => null,
    );

    if (myPlayer == null) return false;

    // Check if it's my turn
    if (players[currentPlayerIndex]['id'] != widget.playerId) {
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

  Widget _buildCard(Map<String, dynamic> card,
      {bool isPlayable = false, VoidCallback? onTap}) {
    // Get responsive dimensions
    final isMobile = MobileConfig.isMobile(context);
    final isTablet = MobileConfig.isTablet(context);
    final isDesktop = MobileConfig.isDesktop(context);
    final cardDimensions = MobileConfig.getCardDimensions(context);

    final myPlayer = _gameState?['players']?.firstWhere(
      (p) => p['id'] == widget.playerId,
      orElse: () => null,
    );
    final cardCount = myPlayer?['cards']?.length ?? 0;

    // Responsive card sizing based on device type and card count
    final scaling = MobileConfig.getPlayerCardScaling(context, cardCount);
    final cardWidth = cardDimensions.width * scaling['width']!;
    final cardHeight = cardDimensions.height * scaling['height']!;
    final cardMargin = scaling['margin']!;

    return GestureDetector(
      onTap: isPlayable ? onTap : null,
      child: AnimatedBuilder(
        animation: _cardAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_cardAnimation.value * 0.15),
            child: Transform.rotate(
              angle: _cardAnimation.value * 0.1,
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
                child: _buildCardContent(card),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardContent(Map<String, dynamic> card) {
    final cardType = card['type'];
    final cardColor = card['color'];

    // Get responsive dimensions
    final isMobile = MobileConfig.isMobile(context);
    final isTablet = MobileConfig.isTablet(context);
    final isDesktop = MobileConfig.isDesktop(context);

    return Container(
      padding: EdgeInsets.all(isMobile ? 6 : (isTablet ? 7 : 8)),
      child: Column(
        children: [
          // Top left corner
          Align(
            alignment: Alignment.topLeft,
            child: _buildCardCorner(card, isTopLeft: true),
          ),

          // Center content
          Expanded(
            child: Center(
              child: _buildCardCenter(card),
            ),
          ),

          // Bottom right corner (rotated)
          Align(
            alignment: Alignment.bottomRight,
            child: Transform.rotate(
              angle: 3.14159, // 180 degrees
              child: _buildCardCorner(card, isTopLeft: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardCorner(Map<String, dynamic> card,
      {required bool isTopLeft}) {
    final cardType = card['type'];
    final cardColor = card['color'];

    // Get responsive dimensions
    final isMobile = MobileConfig.isMobile(context);
    final isTablet = MobileConfig.isTablet(context);
    final isDesktop = MobileConfig.isDesktop(context);

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

  Widget _buildCardCenter(Map<String, dynamic> card) {
    final cardType = card['type'];
    final cardColor = card['color'];

    // Get responsive dimensions
    final isMobile = MobileConfig.isMobile(context);
    final isTablet = MobileConfig.isTablet(context);
    final isDesktop = MobileConfig.isDesktop(context);

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
        return _buildActionIcon(Icons.skip_next, cardColor,
            size: centerIconSize);
      case 'reverse':
        return _buildActionIcon(Icons.swap_horiz, cardColor,
            size: centerIconSize);
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

  Widget _buildActionIcon(dynamic icon, String cardColor,
      {required double size}) {
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

  Widget _buildActionCornerIcon(String cardType, String cardColor,
      {required double size}) {
    // For corner icons, we want smaller, more appropriate symbols
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
    final currentPlayerIndex = _gameState!['current_player_index'] as int;
    final gameStarted = _gameState!['game_started'] as bool;
    final winner = _gameState!['winner'];
    final currentColor = _gameState!['current_color'];
    final discardPile = _gameState!['discard_pile'] as List;

    final currentPlayer = players[currentPlayerIndex];
    final myPlayer = players.firstWhere(
      (p) => p['id'] == widget.playerId,
      orElse: () => null,
    );

    // Find the opponent (the other player)
    final opponent = players.firstWhere(
      (p) => p['id'] != widget.playerId,
      orElse: () => null,
    );

    // Check if it's my turn
    final isMyTurn = currentPlayer['id'] == widget.playerId;

    // Get responsive dimensions
    final screenSize = MediaQuery.of(context).size;
    final isMobile = MobileConfig.isMobile(context);
    final isTablet = MobileConfig.isTablet(context);
    final isDesktop = MobileConfig.isDesktop(context);

    // Responsive card dimensions
    final cardDimensions = MobileConfig.getCardDimensions(context);
    final spacing = MobileConfig.getSpacing(context);
    final buttonHeight = MobileConfig.getButtonHeight(context);
    final bottomPadding = MobileConfig.getBottomPadding(context);

    if (winner != null) {
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
                            'Winner: ${players.firstWhere((p) => p['id'] == winner)['name']}',
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
                      color: _isConnected
                          ? Colors.green
                          : _isConnecting
                              ? Colors.blue
                              : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (_isConnecting || _isReconnecting) ...[
                    SizedBox(width: 4),
                    SizedBox(
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
              onPressed: () => _showShareDialog(),
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
                        if (!_isConnected)
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: spacing, vertical: spacing / 2),
                            color: _isConnecting
                                ? Colors.blue
                                : _isReconnecting
                                    ? Colors.orange
                                    : Colors.red,
                            child: Row(
                              children: [
                                Icon(
                                  _isConnecting
                                      ? Icons.wifi
                                      : _isReconnecting
                                          ? Icons.wifi_find
                                          : Icons.wifi_off,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: spacing / 2),
                                Expanded(
                                  child: Text(
                                    _isConnecting
                                        ? 'Connecting to game server...'
                                        : _isReconnecting
                                            ? 'Reconnecting to game server...'
                                            : _canReclaimSlot
                                                ? 'Your slot is available to reclaim!'
                                                : 'Disconnected from game server',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (!_isReconnecting) ...[
                                  if (_canReclaimSlot)
                                    TextButton(
                                      onPressed: _manualSlotReclamation,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(
                                            horizontal: spacing / 2),
                                      ),
                                      child: const Text('RECLAIM SLOT'),
                                    ),
                                  if (_canReclaimSlot)
                                    SizedBox(width: spacing / 2),
                                  if (!_isConnecting && !_isConnected)
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
                        Container(
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
                                            offset: Offset(1, 1),
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
                                    (index) {
                                      // Responsive opponent card sizing
                                      final opponentCardCount =
                                          opponent?['cards']?.length ?? 0;
                                      double oppCardWidth,
                                          oppCardHeight,
                                          oppCardMargin;

                                      if (isMobile) {
                                        if (opponentCardCount <= 4) {
                                          oppCardWidth =
                                              cardDimensions.width * 0.75;
                                          oppCardHeight =
                                              cardDimensions.height * 0.7;
                                          oppCardMargin = 1.0;
                                        } else if (opponentCardCount <= 6) {
                                          oppCardWidth =
                                              cardDimensions.width * 0.67;
                                          oppCardHeight =
                                              cardDimensions.height * 0.62;
                                          oppCardMargin = 0.75;
                                        } else if (opponentCardCount <= 8) {
                                          oppCardWidth =
                                              cardDimensions.width * 0.58;
                                          oppCardHeight =
                                              cardDimensions.height * 0.54;
                                          oppCardMargin = 0.5;
                                        } else {
                                          oppCardWidth =
                                              cardDimensions.width * 0.5;
                                          oppCardHeight =
                                              cardDimensions.height * 0.47;
                                          oppCardMargin = 0.25;
                                        }
                                      } else if (isTablet) {
                                        if (opponentCardCount <= 4) {
                                          oppCardWidth =
                                              cardDimensions.width * 0.85;
                                          oppCardHeight =
                                              cardDimensions.height * 0.8;
                                          oppCardMargin = 1.5;
                                        } else if (opponentCardCount <= 6) {
                                          oppCardWidth =
                                              cardDimensions.width * 0.75;
                                          oppCardHeight =
                                              cardDimensions.height * 0.7;
                                          oppCardMargin = 1.25;
                                        } else if (opponentCardCount <= 8) {
                                          oppCardWidth =
                                              cardDimensions.width * 0.67;
                                          oppCardHeight =
                                              cardDimensions.height * 0.62;
                                          oppCardMargin = 1.0;
                                        } else {
                                          oppCardWidth =
                                              cardDimensions.width * 0.58;
                                          oppCardHeight =
                                              cardDimensions.height * 0.54;
                                          oppCardMargin = 0.75;
                                        }
                                      } else {
                                        if (opponentCardCount <= 4) {
                                          oppCardWidth =
                                              cardDimensions.width * 0.9;
                                          oppCardHeight =
                                              cardDimensions.height * 0.85;
                                          oppCardMargin = 2.0;
                                        } else if (opponentCardCount <= 6) {
                                          oppCardWidth =
                                              cardDimensions.width * 0.8;
                                          oppCardHeight =
                                              cardDimensions.height * 0.75;
                                          oppCardMargin = 1.75;
                                        } else if (opponentCardCount <= 8) {
                                          oppCardWidth =
                                              cardDimensions.width * 0.7;
                                          oppCardHeight =
                                              cardDimensions.height * 0.65;
                                          oppCardMargin = 1.5;
                                        } else {
                                          oppCardWidth =
                                              cardDimensions.width * 0.6;
                                          oppCardHeight =
                                              cardDimensions.height * 0.55;
                                          oppCardMargin = 1.25;
                                        }
                                      }

                                      return Container(
                                        width: oppCardWidth,
                                        height: oppCardHeight,
                                        margin: EdgeInsets.symmetric(
                                            horizontal: oppCardMargin),
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
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color:
                                                Colors.white.withOpacity(0.6),
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.3),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.style,
                                            color:
                                                Colors.white.withOpacity(0.8),
                                            size: isMobile
                                                ? 14
                                                : (isTablet ? 18 : 20),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Turn indicator
                        if (gameStarted)
                          Container(
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
                                          const Color(
                                              0xFFF6E05E), // Bright yellow
                                          const Color(
                                              0xFFECC94B), // Medium yellow
                                          const Color(
                                              0xFFD69E2E), // Dark yellow
                                        ]
                                      : [
                                          const Color(0xFFA0AEC0), // Light gray
                                          const Color(
                                              0xFF718096), // Medium gray
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
                                      color: isMyTurn
                                          ? Colors.white
                                          : Colors.white,
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
                          ),

                        // Game center area
                        Container(
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
                                  border:
                                      Border.all(color: Colors.white, width: 2),
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
                                      width:
                                          isMobile ? 28 : (isTablet ? 36 : 40),
                                      height:
                                          isMobile ? 28 : (isTablet ? 36 : 40),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(
                                            isMobile
                                                ? 14
                                                : (isTablet ? 18 : 20)),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.style,
                                        color: Colors.white,
                                        size: isMobile
                                            ? 16
                                            : (isTablet ? 20 : 24),
                                      ),
                                    ),
                                    SizedBox(
                                        height:
                                            isMobile ? 4 : (isTablet ? 6 : 8)),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal:
                                            isMobile ? 4 : (isTablet ? 6 : 8),
                                        vertical:
                                            isMobile ? 2 : (isTablet ? 3 : 4),
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${_gameState!['deck']?.length ?? 0}',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isMobile
                                              ? 10
                                              : (isTablet ? 12 : 14),
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
                                    ? _buildCard(discardPile.last,
                                        isPlayable: false)
                                    : Container(
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.3),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color:
                                                  Colors.white.withOpacity(0.5),
                                              width: 2),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.inbox,
                                            color:
                                                Colors.white.withOpacity(0.6),
                                            size: isMobile
                                                ? 20
                                                : (isTablet ? 26 : 30),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),

                        // Current color indicator
                        if (gameStarted)
                          Container(
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
                                          offset: Offset(1, 1),
                                          blurRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: isMobile ? 32 : (isTablet ? 36 : 40),
                                    height:
                                        isMobile ? 32 : (isTablet ? 36 : 40),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          _getCardColor(currentColor),
                                          _getCardColor(currentColor)
                                              .withOpacity(0.8),
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
                          ),

                        // My cards
                        Container(
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
                                      '${widget.playerName} (You)',
                                      style: TextStyle(
                                        fontSize: isMobile ? 16 : 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black,
                                            offset: Offset(1, 1),
                                            blurRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: spacing),
                              if (myPlayer != null) ...[
                                Container(
                                  height: MobileConfig.getPlayerCardsHeight(
                                      context),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: List.generate(
                                        myPlayer['cards'].length,
                                        (index) => _buildCard(
                                          myPlayer['cards'][index],
                                          isPlayable: _isCardPlayable(
                                              myPlayer['cards'][index],
                                              _gameState!),
                                          onTap: gameStarted && isMyTurn
                                              ? () => _playCard(index)
                                              : null,
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
                                            color:
                                                Colors.black.withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ElevatedButton(
                                        onPressed: _drawCard,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          foregroundColor: Colors.white,
                                          shadowColor: Colors.transparent,
                                          padding: EdgeInsets.symmetric(
                                              vertical: spacing),
                                          minimumSize: Size(0, buttonHeight),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(15),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                            ],
                          ),
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

  void _manualReconnect() {
    if (_gameWebSocket != null) {
      setState(() {
        _isConnecting = true;
        _isReconnecting = true;
      });
      _gameWebSocket!.reconnect();
    }
  }

  void _manualSlotReclamation() {
    setState(() {
      _isConnecting = true;
      _isReconnecting = true;
    });
    _checkSlotReclamation();
  }

  void _showConnectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Connection Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isConnected
                          ? Colors.green
                          : _isConnecting
                              ? Colors.blue
                              : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isConnected
                        ? 'Connected'
                        : _isConnecting
                            ? 'Connecting'
                            : 'Disconnected',
                    style: TextStyle(
                      color: _isConnected
                          ? Colors.green
                          : _isConnecting
                              ? Colors.blue
                              : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_isConnecting) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Connecting...'),
                  ],
                ),
              ],
              if (_isReconnecting) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Reconnecting...'),
                  ],
                ),
              ],
              if (!_isConnected && !_isReconnecting && !_isConnecting) ...[
                const SizedBox(height: 16),
                const Text(
                  'Your connection to the game server was lost. This can happen when:',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                const Text('• You switched to another app',
                    style: TextStyle(fontSize: 12)),
                const Text('• Your device went to sleep',
                    style: TextStyle(fontSize: 12)),
                const Text('• Network connection changed',
                    style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (!_isConnected && !_isReconnecting && !_isConnecting)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _manualReconnect();
                },
                child: const Text('Reconnect'),
              ),
          ],
        );
      },
    );
  }
}

// UNO Card model for type safety
