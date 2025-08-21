import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;
import 'dart:io';
import 'package:flutter/services.dart';
import 'config/mobile_theme.dart';
import 'config/mobile_config.dart';

// WebSocket Connection Manager for handling reconnections
class WebSocketManager {
  WebSocketChannel? _channel;
  String? _url;
  String? _gameId;
  String? _playerId;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 10;
  final Duration _reconnectDelay = const Duration(seconds: 2);
  final Duration _pingInterval = const Duration(seconds: 30);

  // Callbacks
  Function(Map<String, dynamic>)? onMessage;
  Function(String)? onError;
  Function()? onConnected;
  Function()? onDisconnected;

  bool get isConnected => _channel != null && _channel!.sink != null;
  bool get isConnecting => _isConnecting;

  // Check if the connection is ready to send/receive messages
  bool get isReady => isConnected && !_isConnecting;

  void connect(String url, {String? gameId, String? playerId}) {
    _url = url;
    _gameId = gameId;
    _playerId = playerId;
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    _connectInternal();
  }

  void _connectInternal() {
    if (_isConnecting || !_shouldReconnect) return;

    _isConnecting = true;
    print('Attempting to connect to WebSocket: $_url');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url!));

      _channel!.stream.listen(
        (data) {
          try {
            final message = json.decode(data);
            print('WebSocket received raw data: $data'); // Debug log
            onMessage?.call(message);
          } catch (e) {
            print('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          print('WebSocket error type: ${error.runtimeType}'); // Debug log
          onError?.call(error.toString());
          _handleDisconnection();
        },
        onDone: () {
          print('WebSocket connection closed');
          onDisconnected?.call();
          _handleDisconnection();
        },
      );

      _isConnecting = false;
      _reconnectAttempts = 0;
      print('WebSocket connection established successfully'); // Debug log
      onConnected?.call();

      // Start ping timer
      _startPingTimer();
    } catch (e) {
      print('Error connecting to WebSocket: $e');
      _isConnecting = false;
      _handleDisconnection();
    }
  }

  void _handleDisconnection() {
    if (!_shouldReconnect) return;

    _stopPingTimer();

    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = Duration(
        milliseconds:
            (_reconnectDelay.inMilliseconds * _reconnectAttempts).clamp(
          1000, // Min 1 second
          30000, // Max 30 seconds
        ),
      );

      print(
          'Attempting to reconnect in ${delay.inMilliseconds}ms (attempt $_reconnectAttempts/$_maxReconnectAttempts)');

      _reconnectTimer = Timer(delay, () {
        if (_shouldReconnect) {
          _connectInternal();
        }
      });
    } else {
      print('Max reconnection attempts reached. Giving up.');
      _shouldReconnect = false;
    }
  }

  void _startPingTimer() {
    _pingTimer = Timer.periodic(_pingInterval, (timer) {
      if (isConnected) {
        send({'type': 'ping'});
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void send(Map<String, dynamic> message) {
    if (isConnected) {
      try {
        _channel!.sink.add(json.encode(message));
      } catch (e) {
        print('Error sending WebSocket message: $e');
        _handleDisconnection();
      }
    }
  }

  void reconnect() {
    _reconnectAttempts = 0;
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    _connectInternal();
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
  }
}

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
  final TextEditingController _gameCodeController = TextEditingController();
  String? _gameId;
  String? _playerId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _availableGames = [];
  WebSocketManager? _lobbyWebSocket;

  // New state variables for improved UX
  bool _showCreateGameSection = false;
  bool _showJoinGameSection = false;
  bool _showRejoinSection = false;
  String? _selectedAction;

  // Helper method for consistent border radius
  static BorderRadius get _borderRadius => BorderRadius.circular(12);

  @override
  void dispose() {
    _playerNameController.dispose();
    _gameCodeController.dispose();
    _lobbyWebSocket?.disconnect();
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

    // Check URL for game code on web (for direct navigation)
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
          // Check if this game code is valid and show join dialog
          _checkGameCode(gameCode);
        }
      }
    } catch (e) {
      // Not running on web or error occurred
    }
  }

  void _clearGameCodeAndReturnHome() {
    setState(() {
      _gameCodeController.clear();
      _gameId = null;
      _selectedAction = null;
      _showCreateGameSection = false;
      _showJoinGameSection = false;
      _showRejoinSection = false;
    });

    // Navigate back to home without game code
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
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

        // If we have a game code from URL, show a dialog to enter player name
        if (widget.initialGameCode != null ||
            _gameCodeController.text == gameCode) {
          _showJoinGameDialog(gameCode, data['game_id']);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Game found: ${data['game_id']}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
        }
      }
    } catch (e) {
      // Game code not found or error occurred
      if (widget.initialGameCode != null) {
        _showInvalidGameCodeDialog(gameCode);
      }
    }
  }

  void _showInvalidGameCodeDialog(String gameCode) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Invalid Game Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('The game code "$gameCode" was not found or is invalid.'),
              const SizedBox(height: 16),
              const Text('This could mean:'),
              const SizedBox(height: 8),
              const Text('• The game has ended'),
              const Text('• The game code was mistyped'),
              const Text('• The game no longer exists'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearGameCodeAndReturnHome();
              },
              child: const Text('Go to Home'),
            ),
          ],
        );
      },
    );
  }

  void _showJoinGameDialog(String gameCode, String gameId) {
    final nameController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Join Game'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('You\'re joining game: $gameCode'),
                  const SizedBox(height: 8),
                  Text(
                    'This will join you as a new player. If you were playing this game before and got disconnected, use the "Rejoin Game" option instead.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Your Name',
                      border: OutlineInputBorder(),
                      hintText: 'Enter your name to join',
                    ),
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    enabled: !isLoading,
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty && !isLoading) {
                        setDialogState(() {
                          isLoading = true;
                        });
                        Navigator.of(context).pop();
                        _joinGameDirectly(gameCode, value.trim());
                      }
                    },
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Joining game...'),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                if (!isLoading) ...[
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _clearGameCodeAndReturnHome();
                    },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (nameController.text.trim().isNotEmpty) {
                        setDialogState(() {
                          isLoading = true;
                        });
                        Navigator.of(context).pop();
                        _joinGameDirectly(gameCode, nameController.text.trim());
                      }
                    },
                    child: const Text('Join Game'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _joinGameDirectly(String gameCode, String playerName) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/games/join-by-code'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'game_code': gameCode,
          'player_name': playerName,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Navigate directly to game screen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => GameScreen(
                gameId: data['game_id'],
                playerId: data['player_id'],
                playerName: playerName,
              ),
            ),
          );
        }
      } else {
        final errorData = json.decode(response.body);
        final errorMessage = errorData['detail'] ?? 'Failed to join game';

        // Check if this is a disconnected player error
        if (errorMessage.contains('disconnected player') ||
            errorMessage.contains('reconnect feature')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'This slot belongs to a disconnected player. Use "Rejoin Game" instead.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              action: SnackBarAction(
                label: 'Rejoin',
                textColor: Colors.white,
                onPressed: () {
                  _selectAction('rejoin');
                },
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $errorMessage'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
        }
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

  void _connectLobbyWebSocket() {
    // Generate a temporary player ID for lobby connection
    final tempPlayerId = 'lobby_${DateTime.now().millisecondsSinceEpoch}';
    final wsUrl = '$wsBaseUrl/ws/lobby/$tempPlayerId';
    _lobbyWebSocket = WebSocketManager();
    _lobbyWebSocket!.connect(wsUrl);

    _lobbyWebSocket!.onMessage = (message) {
      print('Lobby WebSocket received: $message'); // Debug log
      final messageData = message;
      if (messageData['type'] == 'game_list_update') {
        setState(() {
          _availableGames =
              List<Map<String, dynamic>>.from(messageData['games']);
        });
        print('Game list updated: ${messageData['games']}'); // Debug log
      } else if (messageData['type'] == 'pong') {
        print('Lobby pong received'); // Debug log
      }
    };

    _lobbyWebSocket!.onError = (error) {
      print('Lobby WebSocket error: $error'); // Debug log
    };

    _lobbyWebSocket!.onDisconnected = () {
      print('Lobby WebSocket connection closed'); // Debug log
    };

    // Send a ping to test the connection
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_lobbyWebSocket != null && _lobbyWebSocket!.isConnected) {
        _lobbyWebSocket!.send({'type': 'ping'});
      }
    });
  }

  Future<void> _createGame() async {
    if (_playerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter your name first'),
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
      final response =
          await http.post(Uri.parse('$apiBaseUrl/api/games/create'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _gameId = data['game_id'];
          _gameCodeController.text = data['game_code'];
          _showCreateGameSection = true;
          _selectedAction = 'create';
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
        final errorMessage = errorData['detail'] ?? 'Failed to join game';

        // Check if this is a disconnected player error
        if (errorMessage.contains('disconnected player') ||
            errorMessage.contains('reconnect feature')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'This slot belongs to a disconnected player. Use "Rejoin Game" instead.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              action: SnackBarAction(
                label: 'Rejoin',
                textColor: Colors.white,
                onPressed: () {
                  _selectAction('rejoin');
                },
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $errorMessage'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
        }
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

  Future<void> _rejoinGame() async {
    if (_playerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter your name'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      );
      return;
    }

    if (_gameCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a game code'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print(
          'Rejoin: Starting rejoin process for game code: ${_gameCodeController.text.trim()}');
      print('Rejoin: Player name: ${_playerNameController.text.trim()}');

      // First, get the game ID from the game code
      final gameCodeResponse = await http.get(
        Uri.parse(
            '$apiBaseUrl/api/games/code/${_gameCodeController.text.trim()}'),
      );

      print(
          'Rejoin: Game code response status: ${gameCodeResponse.statusCode}');
      print('Rejoin: Game code response body: ${gameCodeResponse.body}');

      if (gameCodeResponse.statusCode != 200) {
        throw Exception('Game code not found');
      }

      final gameCodeData = json.decode(gameCodeResponse.body);
      final gameId = gameCodeData['game_id'];
      print('Rejoin: Found game ID: $gameId');

      // Now check if we can rejoin using the correct endpoint
      final checkUrl =
          '$apiBaseUrl/api/games/$gameId/can-rejoin/${_playerNameController.text.trim()}';
      print('Rejoin: Checking can-rejoin at: $checkUrl');

      final checkResponse = await http.get(Uri.parse(checkUrl));

      print('Rejoin: Can-rejoin response status: ${checkResponse.statusCode}');
      print('Rejoin: Can-rejoin response body: ${checkResponse.body}');

      if (checkResponse.statusCode == 200) {
        final checkData = json.decode(checkResponse.body);
        if (checkData['can_rejoin']) {
          print('Rejoin: Can rejoin, proceeding with rejoin request');

          // Try to rejoin the game
          final rejoinResponse = await http.post(
            Uri.parse('$apiBaseUrl/api/games/$gameId/rejoin'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'player_name': _playerNameController.text.trim(),
            }),
          );

          print('Rejoin: Rejoin response status: ${rejoinResponse.statusCode}');
          print('Rejoin: Rejoin response body: ${rejoinResponse.body}');

          if (rejoinResponse.statusCode == 200) {
            final data = json.decode(rejoinResponse.body);
            final playerId = data['player_id'];
            final playerName = _playerNameController.text.trim();

            print('Rejoin: Successfully rejoined with player ID: $playerId');

            // Successfully rejoined - navigate to game
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => GameScreen(
                    gameId: gameId,
                    playerId: playerId,
                    playerName: playerName,
                  ),
                ),
              );
            }
          } else {
            final errorData = json.decode(rejoinResponse.body);
            throw Exception(errorData['detail'] ?? 'Failed to rejoin game');
          }
        } else {
          print('Rejoin: Cannot rejoin, reason: ${checkData['message']}');
          // Can't rejoin - show the reason and offer to join normally
          _showRejoinNotPossibleDialog(gameId, checkData['message']);
        }
      } else {
        print('Rejoin: Can-rejoin check failed, trying fallback');
        // If can-rejoin check fails, try to join normally as a fallback
        _showRejoinFallbackDialog(gameId);
      }
    } catch (e) {
      print('Rejoin: Error occurred: $e');
      // If any step fails, show error and offer to join normally
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rejoin failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      );

      // Try to get game ID for fallback
      try {
        final gameCodeResponse = await http.get(
          Uri.parse(
              '$apiBaseUrl/api/games/code/${_gameCodeController.text.trim()}'),
        );
        if (gameCodeResponse.statusCode == 200) {
          final gameCodeData = json.decode(gameCodeResponse.body);
          final gameId = gameCodeData['game_id'];
          _showRejoinFallbackDialog(gameId);
        }
      } catch (fallbackError) {
        // If even fallback fails, just show the error
        print('Rejoin: Fallback also failed: $fallbackError');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showRejoinNotPossibleDialog(String gameId, String reason) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cannot Rejoin'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You cannot rejoin this game because:'),
              const SizedBox(height: 8),
              Text(reason, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text(
                  'Would you like to try joining the game normally instead?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showJoinGameDialog(_gameCodeController.text.trim(), gameId);
              },
              child: const Text('Join Normally'),
            ),
          ],
        );
      },
    );
  }

  void _showRejoinFallbackDialog(String gameId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rejoin Not Available'),
          content:
              const Text('The rejoin feature is not available for this game. '
                  'Would you like to try joining the game normally instead?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showJoinGameDialog(_gameCodeController.text.trim(), gameId);
              },
              child: const Text('Join Normally'),
            ),
          ],
        );
      },
    );
  }

  // New helper methods for improved UX
  void _selectAction(String action) {
    setState(() {
      _selectedAction = action;
      _showCreateGameSection = action == 'create';
      _showJoinGameSection = action == 'join';
      _showRejoinSection = action == 'rejoin';
    });
  }

  void _resetToMainMenu() {
    setState(() {
      _selectedAction = null;
      _showCreateGameSection = false;
      _showJoinGameSection = false;
      _showRejoinSection = false;
      _gameId = null;
      _gameCodeController.clear();
    });
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
        centerTitle: true,
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
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: isSmallScreen ? 16.0 : 24.0,
              right: isSmallScreen ? 16.0 : 24.0,
              top: isSmallScreen ? 16.0 : 24.0,
              bottom: isSmallScreen ? 32.0 : 48.0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  children: [
                    // Logo and Title Section
                    _buildLogoSection(),

                    const SizedBox(height: 24),

                    // Player Name Input (Always visible)
                    _buildPlayerNameSection(),

                    const SizedBox(height: 24),

                    // Main Action Selection (if no action selected)
                    if (_selectedAction == null) _buildMainActionSelection(),

                    // Create Game Section
                    if (_showCreateGameSection) _buildCreateGameSection(),

                    // Join Game Section
                    if (_showJoinGameSection) _buildJoinGameSection(),

                    // Rejoin Game Section
                    if (_showRejoinSection) _buildRejoinGameSection(),

                    // Available Games Section (if any)
                    if (_availableGames.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildAvailableGamesSection(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: const EdgeInsets.all(24),
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
    );
  }

  Widget _buildPlayerNameSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, color: Colors.blue),
              SizedBox(width: 12),
              Text(
                'Your Name',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          TextField(
            controller: _playerNameController,
            decoration: InputDecoration(
              hintText: 'Enter your name to start',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: Icon(Icons.edit, color: Colors.blue),
            ),
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              // Enable/disable action buttons based on name input
              setState(() {});
            },
          ),

          SizedBox(height: 8),

          // Help text about names and rejoining
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.blue, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tip: Use the same name if you want to rejoin a game later',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainActionSelection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What would you like to do?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 20),

          // Create Game Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _playerNameController.text.trim().isNotEmpty
                  ? () => _selectAction('create')
                  : null,
              icon: Icon(Icons.add_circle_outline, size: 24),
              label: Text(
                'Create New Game',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),

          SizedBox(height: 16),

          // Join Game Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _playerNameController.text.trim().isNotEmpty
                  ? () => _selectAction('join')
                  : null,
              icon: Icon(Icons.login, size: 24),
              label: Text(
                'Join Existing Game',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),

          SizedBox(height: 16),

          // Rejoin Game Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _playerNameController.text.trim().isNotEmpty
                  ? () => _selectAction('rejoin')
                  : null,
              icon: Icon(Icons.replay, size: 24),
              label: Text(
                'Rejoin Game (Restore Progress)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),

          SizedBox(height: 8),

          // Small info text about rejoin
          Text(
            'Use this if you got disconnected and want to continue your game with the same cards and progress',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 16),

          // Divider and explanation
          Divider(color: Colors.grey[300]),
          SizedBox(height: 8),
          Text(
            'Not sure? Use "Join Existing Game" if you\'re new to the game, or "Rejoin Game" if you were playing before.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCreateGameSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_circle_outline, color: Colors.green),
              SizedBox(width: 12),
              Text(
                'Create New Game',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Create a new UNO game and share the code with a friend to start playing.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _createGame,
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(Icons.add_circle_outline, size: 24),
              label: Text(
                _isLoading ? 'Creating Game...' : 'Create Game',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),

          // Game Code Display (if game was created)
          if (_gameId != null && _gameCodeController.text.isNotEmpty) ...[
            SizedBox(height: 20),
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
                      const Icon(Icons.check_circle, color: Colors.green),
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
                        icon: const Icon(Icons.copy, color: Colors.green),
                        onPressed: () {
                          // Copy to clipboard
                          final url = '$baseUrl/${_gameCodeController.text}';
                          html.window.navigator.clipboard?.writeText(url);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  const Text('Game URL copied to clipboard!'),
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

          SizedBox(height: 16),

          // Back button
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _resetToMainMenu,
              icon: Icon(Icons.arrow_back, size: 20),
              label: Text('Back to Menu'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinGameSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.login, color: Colors.blue),
              SizedBox(width: 12),
              Text(
                'Join Existing Game',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Enter the 5-character game code to join an existing game.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 20),

          TextField(
            controller: _gameCodeController,
            decoration: InputDecoration(
              labelText: 'Game Code',
              hintText: 'Enter 5-character code (e.g., ABC12)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: Icon(Icons.qr_code, color: Colors.blue),
              counterText: '${_gameCodeController.text.length}/5',
            ),
            maxLength: 5,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
          ),

          SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_gameCodeController.text.length == 5 &&
                      _playerNameController.text.trim().isNotEmpty &&
                      !_isLoading)
                  ? _joinGameByCode
                  : null,
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(Icons.login, size: 24),
              label: Text(
                _isLoading ? 'Joining Game...' : 'Join Game',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),

          SizedBox(height: 16),

          // Back button
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _resetToMainMenu,
              icon: Icon(Icons.arrow_back, size: 20),
              label: Text('Back to Menu'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejoinGameSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.replay, color: Colors.orange),
              SizedBox(width: 12),
              Text(
                'Rejoin Game',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Reconnect to a game you were playing if you got disconnected. '
            'This will restore your exact game state and cards.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 20),

          // Info box about rejoining
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Enter the same name you used when you first joined the game.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[700],
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20),

          TextField(
            controller: _gameCodeController,
            decoration: InputDecoration(
              labelText: 'Game Code',
              hintText: 'Enter the 5-character game code',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: Icon(Icons.qr_code, color: Colors.orange),
              counterText: '${_gameCodeController.text.length}/5',
            ),
            maxLength: 5,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
          ),

          SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_gameCodeController.text.length == 5 &&
                      _playerNameController.text.trim().isNotEmpty &&
                      !_isLoading)
                  ? _rejoinGame
                  : null,
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(Icons.replay, size: 24),
              label: Text(
                _isLoading ? 'Rejoining...' : 'Rejoin Game',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),

          SizedBox(height: 16),

          // Alternative option
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                // Switch to join mode instead
                _selectAction('join');
              },
              icon: Icon(Icons.login, size: 20),
              label: Text('Join as New Player Instead'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue[600],
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          SizedBox(height: 16),

          // Back button
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _resetToMainMenu,
              icon: Icon(Icons.arrow_back, size: 20),
              label: Text('Back to Menu'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableGamesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list, color: Colors.blue),
              SizedBox(width: 12),
              Text(
                'Available Games',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Games waiting for players. Click the copy icon to use a game code.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: _availableGames.length,
              itemBuilder: (context, index) {
                final game = _availableGames[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      'Game Code: ${game['game_code'] ?? 'N/A'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                    trailing: (game['status'] == 'waiting' ||
                            game['status'] == 'waiting_for_replacement')
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon:
                                    const Icon(Icons.copy, color: Colors.blue),
                                onPressed: () {
                                  _gameCodeController.text =
                                      game['game_code'] ?? '';
                                  _selectAction('join');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Game code ${game['game_code']} copied to join form'),
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: Colors.blue,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: _borderRadius),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.play_arrow,
                                    color: Colors.green),
                                onPressed: () {
                                  _gameCodeController.text =
                                      game['game_code'] ?? '';
                                  _selectAction('join');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Ready to join game ${game['game_code']}'),
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: Colors.green,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: _borderRadius),
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

      // Send a ping to confirm the connection is working
      _gameWebSocket!.send({'type': 'ping'});

      // Also send a join message to ensure the server knows we're here
      _gameWebSocket!.send({
        'type': 'join_game',
        'game_id': widget.gameId,
        'player_id': widget.playerId,
        'player_name': widget.playerName,
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

    // Send a ping to test the connection
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_gameWebSocket != null && _gameWebSocket!.isConnected) {
        _gameWebSocket!.send({'type': 'ping'});
      }
    });

    // Fallback: fetch initial game state via HTTP if WebSocket doesn't provide it
    Timer(const Duration(seconds: 2), () {
      if (_gameState == null) {
        print('WebSocket fallback: fetching game state via HTTP');
        _fetchGameStateFallback();
      }
    });

    // Connection timeout: if we're still connecting after 10 seconds, show an error
    Timer(const Duration(seconds: 10), () {
      if (_isConnecting && !_isConnected) {
        print('Connection timeout - still connecting after 10 seconds');
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
    Timer(const Duration(seconds: 5), () {
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
