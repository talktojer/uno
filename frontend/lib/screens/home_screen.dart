import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;
import '../websocket/websocket_manager.dart';
import '../config/app_config.dart';
import 'game_screen.dart';

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

    // Load saved player name from local storage
    _loadSavedPlayerName();

    // Handle initial game code from URL
    if (widget.initialGameCode != null) {
      _gameCodeController.text = widget.initialGameCode!;
      _checkGameCode(widget.initialGameCode!);
    }

    // Check URL for game code on web (for direct navigation)
    _checkUrlForGameCode();
  }

  // Load saved player name from local storage
  void _loadSavedPlayerName() {
    try {
      final savedName = html.window.localStorage['uno_player_name'];
      if (savedName != null && savedName.isNotEmpty) {
        _playerNameController.text = savedName;
        print('Loaded saved player name: $savedName');
      } else {
        print('No saved player name found in local storage');
      }
    } catch (e) {
      print('Error loading saved player name: $e');
    }
  }

  // Save player name to local storage
  void _savePlayerName(String name) {
    try {
      if (name.trim().isNotEmpty) {
        html.window.localStorage['uno_player_name'] = name.trim();
        print('Saved player name: ${name.trim()}');
      }
    } catch (e) {
      print('Error saving player name: $e');
    }
  }

  // Clear saved player name from local storage
  void _clearSavedPlayerName() {
    try {
      html.window.localStorage.remove('uno_player_name');
      _playerNameController.clear();
      print('Cleared saved player name');
      setState(() {});
    } catch (e) {
      print('Error clearing saved player name: $e');
    }
  }

  // Check if there's a saved player name
  bool get _hasSavedName {
    try {
      final savedName = html.window.localStorage['uno_player_name'];
      return savedName != null && savedName.isNotEmpty;
    } catch (e) {
      return false;
    }
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
          // Check if this game code is valid and suggest appropriate action
          _checkGameCodeAndSuggestAction(gameCode);
        }
      }
    } catch (e) {
      // Not running on web or error occurred
    }
  }

  Future<void> _checkGameCodeAndSuggestAction(String gameCode) async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/games/code/$gameCode'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final gameId = data['game_id'];
        final disconnectedCount = data['disconnected_players'] ?? 0;

        setState(() {
          _gameId = gameId;
        });

        // Check if user has played this game before by looking for session tokens
        bool hasExistingSession = false;
        String? existingPlayerName;
        try {
          // Check all possible session keys for this game
          final keys = html.window.localStorage.keys;
          for (final key in keys) {
            if (key.startsWith('uno_session_${gameId}_')) {
              hasExistingSession = true;
              // Extract player name from session key
              final parts = key.split('_');
              if (parts.length >= 3) {
                existingPlayerName = parts.sublist(2).join('_');
              }
              break;
            }
          }
        } catch (e) {
          print('Error checking local storage: $e');
        }

        // If there are disconnected players or user has existing session, suggest rejoin
        if (disconnectedCount > 0 || hasExistingSession) {
          // Pre-fill player name if we found an existing session
          if (existingPlayerName != null &&
              _playerNameController.text.isEmpty) {
            _playerNameController.text = existingPlayerName;
            _savePlayerName(existingPlayerName);
          }
          _showRejoinOrJoinDialog(gameCode, gameId);
        } else {
          // No disconnected players or existing session, show normal join dialog
          _showRejoinOrJoinDialog(gameCode, gameId);
        }
      }
    } catch (e) {
      // Game code not found or error occurred
      if (widget.initialGameCode != null) {
        _showInvalidGameCodeDialog(gameCode);
      }
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
      } else if (response.statusCode == 410) {
        // Game has ended
        final errorData = json.decode(response.body);
        final errorMessage = errorData['detail'] ?? 'Game has ended';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('This game has ended: $errorMessage'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
        if (widget.initialGameCode != null) {
          _showInvalidGameCodeDialog(gameCode);
        }
      }
    } catch (e) {
      // Game code not found or error occurred
      if (widget.initialGameCode != null) {
        _showInvalidGameCodeDialog(gameCode);
      }
    }
  }

  void _showRejoinOrJoinDialog(String gameCode, String gameId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Game Found'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Game code "$gameCode" found!'),
              const SizedBox(height: 8),
              const Text(
                'This game has disconnected players. You can either:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('• Rejoin if you were playing this game before'),
              const Text('• Join as a new player'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Text(
                  'Your name "${_playerNameController.text.isNotEmpty ? _playerNameController.text : 'is ready'}" is automatically filled in for rejoining',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearGameCodeAndReturnHome();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _selectAction('rejoin');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Rejoin Game'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showJoinGameDialog(gameCode, gameId);
              },
              child: const Text('Join as New Player'),
            ),
          ],
        );
      },
    );
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
    // Pre-fill with saved player name if available
    if (_playerNameController.text.isNotEmpty) {
      nameController.text = _playerNameController.text;
    }
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

        // Store session token for potential rejoin
        if (data['session_token'] != null) {
          final storageKey = 'uno_session_${data['game_id']}_$playerName';
          html.window.localStorage[storageKey] = data['session_token'];
          print(
              'Stored session token for game ${data['game_id']} and player $playerName');
        }

        // Save player name for future use
        _savePlayerName(playerName);

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

        // Check if this is a game ended error
        if (response.statusCode == 410 ||
            errorMessage.contains('Game has ended')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  const Text('This game has ended and is no longer available.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
          // Refresh the game list to remove ended games
          _connectLobbyWebSocket();
        }
        // Check if this is a disconnected player error
        else if (errorMessage.contains('disconnected player') ||
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

        // Save player name for future use
        _savePlayerName(_playerNameController.text);

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

        // Store session token for potential rejoin
        if (data['session_token'] != null) {
          final storageKey =
              'uno_session_${data['game_id']}_${_playerNameController.text}';
          html.window.localStorage[storageKey] = data['session_token'];
          print(
              'Stored session token for game ${data['game_id']} and player ${_playerNameController.text}');
        }

        // Save player name for future use
        _savePlayerName(_playerNameController.text);

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

      // First check if this player has an active session
      final sessionUrl =
          '$apiBaseUrl/api/games/$gameId/session/${_playerNameController.text.trim()}';
      print('Rejoin: Checking session at: $sessionUrl');

      final sessionResponse = await http.get(Uri.parse(sessionUrl));
      print('Rejoin: Session response status: ${sessionResponse.statusCode}');
      print('Rejoin: Session response body: ${sessionResponse.body}');

      if (sessionResponse.statusCode == 200) {
        final sessionData = json.decode(sessionResponse.body);
        if (sessionData['has_session']) {
          print('Rejoin: Player has active session, checking if can rejoin');

          // Now check if we can rejoin using the correct endpoint
          final checkUrl =
              '$apiBaseUrl/api/games/$gameId/can-rejoin/${_playerNameController.text.trim()}';
          print('Rejoin: Checking can-rejoin at: $checkUrl');

          final checkResponse = await http.get(Uri.parse(checkUrl));

          print(
              'Rejoin: Can-rejoin response status: ${checkResponse.statusCode}');
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

              print(
                  'Rejoin: Rejoin response status: ${rejoinResponse.statusCode}');
              print('Rejoin: Rejoin response body: ${rejoinResponse.body}');

              if (rejoinResponse.statusCode == 200) {
                final data = json.decode(rejoinResponse.body);
                final playerId = data['player_id'];
                final playerName = _playerNameController.text.trim();

                print(
                    'Rejoin: Successfully rejoined with player ID: $playerId');

                // Save player name for future use
                _savePlayerName(playerName);

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
        } else {
          print('Rejoin: Player has no active session, cannot rejoin');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'You have not played this game before. Use "Join as New Player" instead.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            ),
          );
        }
      } else {
        print('Rejoin: Session check failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text('Failed to check player session. Please try again.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        );
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
          Row(
            children: [
              Expanded(
                child: TextField(
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
                    // Save the name as the user types
                    if (value.trim().isNotEmpty) {
                      _savePlayerName(value);
                    }
                  },
                ),
              ),
              if (_playerNameController.text.isNotEmpty) ...[
                SizedBox(width: 8),
                IconButton(
                  onPressed: _clearSavedPlayerName,
                  icon: Icon(Icons.clear, color: Colors.grey[600]),
                  tooltip: 'Clear saved name',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    padding: EdgeInsets.all(8),
                  ),
                ),
              ],
            ],
          ),

          SizedBox(height: 8),

          // Help text about names and rejoining
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _hasSavedName
                  ? Colors.green.withOpacity(0.1)
                  : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _hasSavedName
                      ? Colors.green.withOpacity(0.3)
                      : Colors.blue.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(
                    _hasSavedName
                        ? Icons.check_circle
                        : Icons.lightbulb_outline,
                    color: _hasSavedName ? Colors.green : Colors.blue,
                    size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _hasSavedName
                        ? 'Your name "${_playerNameController.text}" is saved and will be remembered when you rejoin games'
                        : 'Tip: Your name is automatically saved and will be remembered when you rejoin games',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          _hasSavedName ? Colors.green[700] : Colors.blue[700],
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
                    'Your name is automatically filled in. If you want to rejoin as a different player, change the name above.',
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
                                  if (_playerNameController.text
                                      .trim()
                                      .isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                            'Please enter your name first'),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: Colors.orange,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: _borderRadius),
                                      ),
                                    );
                                    return;
                                  }
                                  _joinGameDirectly(game['game_code'] ?? '',
                                      _playerNameController.text.trim());
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
