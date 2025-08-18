import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;
import 'config/mobile_theme.dart';

// API Configuration
const String apiBaseUrl = 'https://uno-api.jersweb.net';
const String wsBaseUrl = 'wss://uno-api.jersweb.net';
const String baseUrl = 'https://uno.jersweb.net';

void main() {
  runApp(const UNOGameApp());
}

class UNOGameApp extends StatelessWidget {
  const UNOGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNO Game',
      theme: MobileTheme.getLightTheme(),
      darkTheme: MobileTheme.getDarkTheme(),
      themeMode: ThemeMode
          .system, // Automatically switch between light/dark based on system
      home: const HomeScreen(),
      onGenerateRoute: (settings) {
        // Handle game code routes like /ABC12
        if (settings.name != null && settings.name!.length == 5) {
          return MaterialPageRoute(
            builder: (context) => HomeScreen(initialGameCode: settings.name!),
          );
        }
        return null;
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String? initialGameCode;

  const HomeScreen({super.key, this.initialGameCode});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _playerNameController = TextEditingController();
  final TextEditingController _gameIdController = TextEditingController();
  final TextEditingController _gameCodeController = TextEditingController();
  String? _gameId;
  String? _playerId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _availableGames = [];
  WebSocketChannel? _lobbyChannel;

  // Helper method for consistent border radius
  static BorderRadius get _borderRadius => BorderRadius.circular(8);

  @override
  void dispose() {
    _playerNameController.dispose();
    _gameIdController.dispose();
    _gameCodeController.dispose();
    _lobbyChannel?.sink.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _connectLobbyWebSocket();

    // Handle initial game code from URL
    if (widget.initialGameCode != null) {
      _gameCodeController.text = widget.initialGameCode!;
      _checkGameCode(widget.initialGameCode!);
    }

    // Check URL for game code on web
    _checkUrlForGameCode();
  }

  void _checkUrlForGameCode() {
    try {
      final uri = html.window.location;
      final pathname = uri.pathname;
      if (pathname != null &&
          pathname.length == 6 &&
          pathname.startsWith('/')) {
        final gameCode = pathname.substring(1);
        if (gameCode.length == 5) {
          _gameCodeController.text = gameCode;
          _checkGameCode(gameCode);
        }
      }
    } catch (e) {
      // Not running on web or error occurred
    }
  }

  Future<void> _checkGameCode(String gameCode) async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/games/code/$gameCode'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _gameId = data['game_id'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Game found: ${data['game_id']}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
      }
    } catch (e) {
      // Game code not found or error occurred
    }
  }

  void _connectLobbyWebSocket() {
    // Generate a temporary player ID for lobby connection
    final tempPlayerId = 'lobby_${DateTime.now().millisecondsSinceEpoch}';
    final wsUrl = '$wsBaseUrl/ws/lobby/$tempPlayerId';
    _lobbyChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

    _lobbyChannel!.stream.listen(
      (data) {
        print('Lobby WebSocket received: $data'); // Debug log
        final message = json.decode(data);
        if (message['type'] == 'game_list_update') {
          setState(() {
            _availableGames = List<Map<String, dynamic>>.from(message['games']);
          });
          print('Game list updated: ${message['games']}'); // Debug log
        } else if (message['type'] == 'pong') {
          print('Lobby pong received'); // Debug log
        }
      },
      onError: (error) {
        print('Lobby WebSocket error: $error'); // Debug log
      },
      onDone: () {
        print('Lobby WebSocket connection closed'); // Debug log
      },
    );

    // Send a ping to test the connection
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_lobbyChannel != null) {
        _lobbyChannel!.sink.add(json.encode({'type': 'ping'}));
      }
    });
  }

  Future<void> _createGame() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response =
          await http.post(Uri.parse('$apiBaseUrl/api/games/create'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _gameId = data['game_id'];
          _gameCodeController.text = data['game_code'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Game created: ${data['game_code']}'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        // Game list will be updated automatically via WebSocket
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating game: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinGame() async {
    if (_gameIdController.text.isEmpty || _playerNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter both game ID and your name'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/games/${_gameIdController.text}/join'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'player_name': _playerNameController.text}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _playerId = data['player_id'];
          _gameId = _gameIdController.text;
        });

        // Navigate to game screen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => GameScreen(
                gameId: _gameId!,
                playerId: _playerId!,
                playerName: _playerNameController.text,
              ),
            ),
          );
        }
      } else {
        final errorData = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Error: ${errorData['detail'] ?? 'Failed to join game'}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error joining game: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinGameByCode() async {
    if (_gameCodeController.text.isEmpty ||
        _playerNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter both game code and your name'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/games/join-by-code'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'game_code': _gameCodeController.text,
          'player_name': _playerNameController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _playerId = data['player_id'];
          _gameId = data['game_id'];
        });

        // Navigate to game screen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => GameScreen(
                gameId: _gameId!,
                playerId: _playerId!,
                playerName: _playerNameController.text,
              ),
            ),
          );
        }
      } else {
        final errorData = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Error: ${errorData['detail'] ?? 'Failed to join game'}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error joining game: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('UNO Game'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
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
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isSmallScreen ? 16.0 : 24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isSmallScreen ? 20.0 : 30.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo and Title
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Column(
                            children: [
                              Text(
                                'UNO',
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Two Player Game',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Player Name Input
                        TextField(
                          controller: _playerNameController,
                          decoration: const InputDecoration(
                            labelText: 'Your Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                            hintText: 'Enter your name',
                          ),
                          textInputAction: TextInputAction.next,
                        ),

                        const SizedBox(height: 20),

                        // Game Code Input
                        TextField(
                          controller: _gameCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Game Code (5 characters)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.qr_code),
                            hintText: 'Enter 5-character game code',
                          ),
                          textInputAction: TextInputAction.done,
                          maxLength: 5,
                          textCapitalization: TextCapitalization.characters,
                        ),

                        const SizedBox(height: 20),

                        // Game ID Input (for backward compatibility)
                        TextField(
                          controller: _gameIdController,
                          decoration: const InputDecoration(
                            labelText: 'Game ID (to join existing game)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.games),
                            hintText: 'Enter game ID to join',
                          ),
                          textInputAction: TextInputAction.done,
                        ),

                        const SizedBox(height: 30),

                        // Action Buttons
                        if (isSmallScreen) ...[
                          // Stacked buttons for small screens
                          Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _createGame,
                                  child: Text(_isLoading
                                      ? 'Creating...'
                                      : 'Create Game'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed:
                                      _isLoading ? null : _joinGameByCode,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(_isLoading
                                      ? 'Joining...'
                                      : 'Join by Code'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _joinGame,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(_isLoading
                                      ? 'Joining...'
                                      : 'Join by Game ID'),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          // Side-by-side buttons for larger screens
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _createGame,
                                  child: Text(_isLoading
                                      ? 'Creating...'
                                      : 'Create Game'),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed:
                                      _isLoading ? null : _joinGameByCode,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(_isLoading
                                      ? 'Joining...'
                                      : 'Join by Code'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _joinGame,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(_isLoading
                                  ? 'Joining...'
                                  : 'Join by Game ID'),
                            ),
                          ),
                        ],

                        // Game Code Display
                        if (_gameId != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle,
                                        color: Colors.green),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Game Code: ${_gameCodeController.text}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Share this code with others to join your game!',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Full URL: $baseUrl/${_gameCodeController.text}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green[600],
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.copy,
                                          color: Colors.green),
                                      onPressed: () {
                                        // Copy to clipboard
                                        final url =
                                            '$baseUrl/${_gameCodeController.text}';
                                        html.window.navigator.clipboard
                                            ?.writeText(url);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                                'Game URL copied to clipboard!'),
                                            behavior: SnackBarBehavior.floating,
                                            backgroundColor: Colors.green,
                                            shape: RoundedRectangleBorder(
                                                borderRadius: _borderRadius),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 30),

                        // Available Games Section
                        if (_availableGames.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.list, color: Colors.blue),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Available Games:',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 150,
                                  child: ListView.builder(
                                    itemCount: _availableGames.length,
                                    itemBuilder: (context, index) {
                                      final game = _availableGames[index];
                                      return Card(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        child: ListTile(
                                          title: Text(
                                            'Game Code: ${game['game_code'] ?? 'N/A'}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Status: ${game['status']} (${game['active_players'] ?? game['player_count']}/2 players)',
                                              ),
                                              if (game['game_id'] != null)
                                                Text(
                                                  'Game ID: ${game['game_id']}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                            ],
                                          ),
                                          trailing: (game['status'] ==
                                                      'waiting' ||
                                                  game['status'] ==
                                                      'waiting_for_replacement')
                                              ? Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.copy,
                                                          color: Colors.blue),
                                                      onPressed: () {
                                                        _gameCodeController
                                                                .text =
                                                            game['game_code'] ??
                                                                '';
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                                'Game code ${game['game_code']} copied to input field'),
                                                            behavior:
                                                                SnackBarBehavior
                                                                    .floating,
                                                            backgroundColor:
                                                                Colors.blue,
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    _borderRadius),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.play_arrow,
                                                          color: Colors.green),
                                                      onPressed: () {
                                                        _gameCodeController
                                                                .text =
                                                            game['game_code'] ??
                                                                '';
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                                'Game code ${game['game_code']} copied to input field'),
                                                            behavior:
                                                                SnackBarBehavior
                                                                    .floating,
                                                            backgroundColor:
                                                                Colors.green,
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    _borderRadius),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                )
                                              : null,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? _gameState;
  WebSocketChannel? _channel;
  late AnimationController _cardAnimationController;
  late Animation<double> _cardAnimation;

  // Helper method for consistent border radius
  static BorderRadius get _borderRadius => BorderRadius.circular(8);

  @override
  void initState() {
    super.initState();
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _cardAnimation = CurvedAnimation(
      parent: _cardAnimationController,
      curve: Curves.easeInOut,
    );
    _connectWebSocket();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _cardAnimationController.dispose();
    super.dispose();
  }

  void _connectWebSocket() {
    final wsUrl = '$wsBaseUrl/ws/${widget.gameId}/${widget.playerId}';
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    _channel!.stream.listen(
      (data) {
        print('WebSocket received: $data'); // Debug log
        final message = json.decode(data);
        if (message['type'] == 'game_update') {
          setState(() {
            _gameState = message['game_state'];
          });
          print('Game state updated: ${message['game_state']}'); // Debug log
        } else if (message['type'] == 'game_started') {
          // Don't update game state here - it should come from the game_update message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Game started! ${message['message']}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
          print('Game started: ${message['message']}'); // Debug log
        } else if (message['type'] == 'player_replaced') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${message['message']}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
          print('Player replaced: ${message['message']}'); // Debug log
        } else if (message['type'] == 'player_disconnected') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${message['message']}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
          print('Player disconnected: ${message['message']}'); // Debug log
        } else if (message['type'] == 'card_drawn') {
          // Update game state with the new card drawn information
          setState(() {
            _gameState = message['game_state'];
          });
          print('Card drawn: ${message['card']}'); // Debug log
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Drew a card: ${message['card']['color']} ${message['card']['type']}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.purple,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
        } else if (message['type'] == 'card_played') {
          // Update game state after a card is played
          setState(() {
            _gameState = message['game_state'];
          });
          print('Card played: ${message['result']}'); // Debug log
          if (message['result']?['game_over'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('Game Over! ${message['result']['winner']} wins!'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.amber,
                shape: RoundedRectangleBorder(borderRadius: _borderRadius),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        } else if (message['type'] == 'error') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${message['message']}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
        } else if (message['type'] == 'pong') {
          print('Pong received'); // Debug log
        } else {
          print('Unknown message type: ${message['type']}'); // Debug log
          print('Full message: $message'); // Debug log
        }
      },
      onError: (error) {
        print('WebSocket error: $error'); // Debug log
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WebSocket error: $error'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
      },
      onDone: () {
        print('WebSocket connection closed'); // Debug log
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Connection closed'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
      },
    );

    // Send a ping to test the connection
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_channel != null) {
        _channel!.sink.add(json.encode({'type': 'ping'}));
      }
    });

    // Fallback: fetch initial game state via HTTP if WebSocket doesn't provide it
    Timer(const Duration(seconds: 2), () {
      if (_gameState == null) {
        print('WebSocket fallback: fetching game state via HTTP');
        _fetchGameStateFallback();
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
    if (_channel != null) {
      _channel!.sink.add(json.encode({
        'type': 'start_game',
      }));
    }
  }

  Future<void> _playCard(int cardIndex) async {
    if (_channel != null && _gameState != null) {
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

      _channel!.sink.add(json.encode({
        'type': 'play_card',
        'card_index': cardIndex,
        'new_color': newColor,
      }));
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
    if (_channel != null && _gameState != null) {
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

      _channel!.sink.add(json.encode({
        'type': 'draw_card',
      }));
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

  Color _getColorFromString(String colorString) {
    switch (colorString.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'black':
        return Colors.black;
      default:
        return Colors.grey;
    }
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
    Color cardColor;
    String cardText;
    IconData? cardIcon;

    switch (card['color']) {
      case 'red':
        cardColor = Colors.red;
        break;
      case 'blue':
        cardColor = Colors.blue;
        break;
      case 'green':
        cardColor = Colors.green;
        break;
      case 'yellow':
        cardColor = Colors.yellow;
        break;
      case 'black':
        cardColor = Colors.black;
        break;
      default:
        cardColor = Colors.grey;
    }

    switch (card['type']) {
      case 'number':
        cardText = card['value'].toString();
        break;
      case 'skip':
        cardText = '⏭';
        cardIcon = Icons.skip_next;
        break;
      case 'reverse':
        cardText = '↔';
        cardIcon = Icons.swap_horiz;
        break;
      case 'draw2':
        cardText = '+2';
        cardIcon = Icons.add;
        break;
      case 'wild':
        cardText = 'WILD';
        break;
      case 'wild_draw4':
        cardText = '+4';
        break;
      default:
        cardText = '?';
    }

    return GestureDetector(
      onTap: isPlayable ? onTap : null, // Only allow tap if card is playable
      child: AnimatedBuilder(
        animation: _cardAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_cardAnimation.value * 0.1),
            child: Container(
              width: 60,
              height: 90,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: cardColor == Colors.black ? Colors.grey[800] : cardColor,
                borderRadius: _borderRadius,
                border: Border.all(
                  color: isPlayable ? Colors.white : Colors.grey,
                  width: isPlayable ? 3 : 1,
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
                child: cardIcon != null
                    ? Icon(cardIcon, color: Colors.white, size: 24)
                    : Text(
                        cardText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
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
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(32),
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
                          const Icon(
                            Icons.emoji_events,
                            size: 100,
                            color: Colors.yellow,
                          ),
                          const SizedBox(height: 20),
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
                          const SizedBox(height: 20),
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
                    const SizedBox(height: 40),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 30, vertical: 15),
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
          child: Column(
            children: [
              // Opponent's cards
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Text(
                        opponent?['name'] ?? 'Opponent',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          opponent?['cards']?.length ?? 0,
                          (index) => Container(
                            width: 40,
                            height: 60,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: Colors.blue[800],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: const Center(
                              child: Icon(Icons.style, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Turn indicator
              if (gameStarted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isMyTurn ? Colors.yellow : Colors.grey,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      isMyTurn
                          ? 'YOUR TURN!'
                          : '${currentPlayer['name']}\'s turn',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),

              // Game center area
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Draw pile
                      Container(
                        width: 60,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.blue[800],
                          borderRadius: _borderRadius,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.style,
                                color: Colors.white, size: 20),
                            Text(
                              '${_gameState!['deck']?.length ?? 0}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Discard pile
                      if (discardPile.isNotEmpty)
                        _buildCard(discardPile.last, isPlayable: false),
                    ],
                  ),
                ),
              ),

              // Current color indicator
              if (gameStarted)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Current Color: ',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _getColorFromString(currentColor),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // My cards
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Text(
                        '${widget.playerName} (You)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (myPlayer != null) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            myPlayer['cards'].length,
                            (index) => _buildCard(
                              myPlayer['cards'][index],
                              isPlayable: _isCardPlayable(
                                  myPlayer['cards'][index], _gameState!),
                              onTap: gameStarted && isMyTurn
                                  ? () => _playCard(index)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (gameStarted && isMyTurn)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _drawCard,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Draw Card'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),

              // Start game button
              if (!gameStarted && players.length == 2)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _startGame,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Start Game'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// UNO Card model for type safety
class UNOCard {
  final String color;
  final String type;
  final int? value;

  UNOCard({
    required this.color,
    required this.type,
    this.value,
  });

  factory UNOCard.fromJson(Map<String, dynamic> json) {
    return UNOCard(
      color: json['color'],
      type: json['type'],
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'color': color,
      'type': type,
      'value': value,
    };
  }
}
