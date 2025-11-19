import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:html' as html;
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/lobby_websocket_service.dart';
import '../services/auth_service.dart';
import '../dialogs/join_game_dialog.dart';
import '../dialogs/rejoin_join_choice_dialog.dart';
import '../dialogs/invalid_game_code_dialog.dart';
import '../dialogs/rejoin_error_dialogs.dart';
import '../widgets/logo_section.dart';
import '../widgets/main_action_selection.dart';
import '../widgets/create_game_section.dart';
import '../widgets/join_game_section.dart';
import '../widgets/rejoin_game_section.dart';
import '../widgets/available_games_section.dart';
import '../utils/home_screen_utils.dart';
import 'game_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? initialGameCode;

  const HomeScreen({super.key, this.initialGameCode});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _gameCodeController = TextEditingController();
  final LobbyWebSocketService _lobbyService = LobbyWebSocketService();

  String? _gameId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _availableGames = [];
  String? _currentUsername;

  // Active game state
  String? _activeGameId;
  String? _activeGameCode;
  String? _activePlayerId;
  bool _isCheckingActiveGame = false;

  // UI state
  bool _showCreateGameSection = false;
  bool _showJoinGameSection = false;
  bool _showRejoinSection = false;
  String? _selectedAction;

  @override
  void initState() {
    super.initState();
    _initializeHomeScreen();
  }

  void _initializeHomeScreen() {
    _loadCurrentUser();
    _connectLobbyWebSocket();
    _handleInitialGameCode();
    _checkForActiveGames();
  }

  void _loadCurrentUser() {
    setState(() {
      _currentUsername = AuthService.currentUsername;
    });
  }

  void _connectLobbyWebSocket() {
    _lobbyService.connect();
    _lobbyService.gameListStream.listen((games) {
      if (mounted) {
        setState(() {
          _availableGames = games;
        });
      }
    });
  }

  void _handleInitialGameCode() {
    if (widget.initialGameCode != null) {
      _gameCodeController.text = widget.initialGameCode!;
      _checkGameCode(widget.initialGameCode!);
    } else {
      final urlGameCode = StorageService.getGameCodeFromUrl();
      if (urlGameCode != null) {
        _gameCodeController.text = urlGameCode;
        _checkGameCodeAndSuggestAction(urlGameCode);
      }
    }
  }

  @override
  void dispose() {
    _gameCodeController.dispose();
    _lobbyService.dispose();
    super.dispose();
  }

  // Game code checking methods
  Future<void> _checkGameCode(String gameCode) async {
    try {
      final data = await ApiService.getGameByCode(gameCode);
      setState(() {
        _gameId = data['game_id'];
      });

      if (widget.initialGameCode != null ||
          _gameCodeController.text == gameCode) {
        _showJoinGameDialog(gameCode, data['game_id']);
      } else {
        HomeScreenUtils.showSuccessSnackBar(
            context, 'Game found: ${data['game_id']}');
      }
    } on GameEndedException catch (e) {
      HomeScreenUtils.showErrorSnackBar(
          context, 'This game has ended: ${e.message}');
      if (widget.initialGameCode != null) {
        _showInvalidGameCodeDialog(gameCode);
      }
    } on ApiException {
      if (widget.initialGameCode != null) {
        _showInvalidGameCodeDialog(gameCode);
      }
    }
  }

  Future<void> _checkGameCodeAndSuggestAction(String gameCode) async {
    try {
      final data = await ApiService.getGameByCode(gameCode);
      final gameId = data['game_id'];

      setState(() {
        _gameId = gameId;
      });

      // No need to check for existing player name since we're using authentication

      _showRejoinOrJoinDialog(gameCode, gameId);
    } on ApiException {
      if (widget.initialGameCode != null) {
        _showInvalidGameCodeDialog(gameCode);
      }
    }
  }

  // Dialog methods
  void _showJoinGameDialog(String gameCode, String gameId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => JoinGameDialog(
        gameCode: gameCode,
        preFilledName: _currentUsername,
        onJoin: (playerName) => _joinGameDirectly(gameCode),
      ),
    );
  }

  void _showRejoinOrJoinDialog(String gameCode, String gameId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RejoinJoinChoiceDialog(
        gameCode: gameCode,
        playerName: _currentUsername ?? '',
        onRejoin: () {
          Navigator.of(context).pop();
          _selectAction('rejoin');
        },
        onJoin: () {
          Navigator.of(context).pop();
          _showJoinGameDialog(gameCode, gameId);
        },
        onCancel: () {
          Navigator.of(context).pop();
          _clearGameCodeAndReturnHome();
        },
      ),
    );
  }

  void _showInvalidGameCodeDialog(String gameCode) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => InvalidGameCodeDialog(
        gameCode: gameCode,
        onGoHome: () {
          Navigator.of(context).pop();
          _clearGameCodeAndReturnHome();
        },
      ),
    );
  }

  void _showRejoinNotPossibleDialog(String gameId, String reason) {
    showDialog(
      context: context,
      builder: (context) => RejoinNotPossibleDialog(
        reason: reason,
        onJoinNormally: () {
          Navigator.of(context).pop();
          _showJoinGameDialog(_gameCodeController.text.trim(), gameId);
        },
        onCancel: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showRejoinFallbackDialog(String gameId) {
    showDialog(
      context: context,
      builder: (context) => RejoinFallbackDialog(
        onJoinNormally: () {
          Navigator.of(context).pop();
          _showJoinGameDialog(_gameCodeController.text.trim(), gameId);
        },
        onCancel: () => Navigator.of(context).pop(),
      ),
    );
  }

  // Game action methods
  Future<void> _createGame() async {
    if (_currentUsername == null) {
      HomeScreenUtils.showWarningSnackBar(
          context, 'Please log in first');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final data = await ApiService.createGame();
      setState(() {
        _gameId = data['game_id'];
        _gameCodeController.text = data['game_code'];
        _showCreateGameSection = true;
        _selectedAction = 'create';
      });

      HomeScreenUtils.showSuccessSnackBar(
          context, 'Game created: ${data['game_code']}');
    } catch (e) {
      HomeScreenUtils.showErrorSnackBar(context, 'Error creating game: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinGameByCode() async {
    if (_gameCodeController.text.isEmpty) {
      HomeScreenUtils.showWarningSnackBar(
          context, 'Please enter a game code');
      return;
    }

    if (_currentUsername == null) {
      HomeScreenUtils.showWarningSnackBar(
          context, 'Please log in first');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final data = await ApiService.joinGameByCode(_gameCodeController.text);
      setState(() {
        _gameId = data['game_id'];
      });

      if (data['session_token'] != null) {
        ApiService.storeSessionToken(
            data['game_id'], _currentUsername!, data['session_token']);
      }

      _navigateToGame(
          data['game_id'], data['player_id'], _currentUsername!);
    } on ApiException catch (e) {
      _handleJoinError(e);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinGameDirectly(String gameCode) async {
    if (_currentUsername == null) {
      HomeScreenUtils.showWarningSnackBar(
          context, 'Please log in first');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final data = await ApiService.joinGameByCode(gameCode);

      if (data['session_token'] != null) {
        ApiService.storeSessionToken(
            data['game_id'], _currentUsername!, data['session_token']);
      }

      _navigateToGame(data['game_id'], data['player_id'], _currentUsername!);
    } on ApiException catch (e) {
      _handleJoinError(e);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _rejoinGame() async {
    // With the new unified join endpoint, rejoin is the same as join
    // The backend automatically detects if the user owns a slot and rejoins them
    // or joins them as a new player if they don't own a slot
    await _joinGameByCode();
  }

  void _tryRejoinFallback() async {
    try {
      final gameCodeData =
          await ApiService.getGameByCode(_gameCodeController.text.trim());
      _showRejoinFallbackDialog(gameCodeData['game_id']);
    } catch (e) {
      // Fallback also failed, just show the error
    }
  }

  void _handleJoinError(ApiException e) {
    if (e.statusCode == 410 || HomeScreenUtils.isGameEndedError(e.message)) {
      HomeScreenUtils.showErrorSnackBar(
          context, 'This game has ended and is no longer available.');
      _lobbyService.connect(); // Refresh game list
    } else {
      // With the new unified join endpoint, disconnected player errors should not occur
      // as the backend automatically handles rejoining or joining as new player
      HomeScreenUtils.showErrorSnackBar(context, 'Error: ${e.message}');
    }
  }

  void _navigateToGame(String gameId, String playerId, String playerName) {
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
  }

  Future<void> _deleteGame(String gameId) async {
    if (gameId.isEmpty) {
      HomeScreenUtils.showErrorSnackBar(context, 'Invalid game ID');
      return;
    }

    try {
      final data = await ApiService.deleteGame(gameId);
      HomeScreenUtils.showSuccessSnackBar(
          context, data['message'] ?? 'Game deleted successfully');
      // Game list will auto-refresh via WebSocket updates
    } on ApiException catch (e) {
      HomeScreenUtils.showErrorSnackBar(context, 'Error deleting game: ${e.message}');
    } catch (e) {
      HomeScreenUtils.showErrorSnackBar(context, 'Error deleting game: $e');
    }
  }

  // UI state management
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

  void _clearGameCodeAndReturnHome() {
    _resetToMainMenu();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  // Active game detection
  Future<void> _checkForActiveGames() async {
    if (_currentUsername == null) {
      // Wait a bit for username to load
      await Future.delayed(const Duration(milliseconds: 100));
      if (_currentUsername == null) return;
    }

    setState(() {
      _isCheckingActiveGame = true;
    });

    try {
      // Scan localStorage for session tokens
      final keys = html.window.localStorage.keys;
      for (final key in keys) {
        if (key.startsWith('uno_session_')) {
          // Extract gameId and playerName from key format: uno_session_{gameId}_{playerName}
          final parts = key.split('_');
          if (parts.length >= 4) {
            final gameId = parts[2];
            final playerName = parts.sublist(3).join('_');
            
            // Only check games for the current user
            if (playerName == _currentUsername) {
              try {
                // Check if user has an active slot in this game
                final slotData = await ApiService.getMySlot(gameId);
                
                if (slotData['has_slot'] == true) {
                  // Get game state to check if game is in progress
                  try {
                    final gameState = await ApiService.getGameState(gameId);
                    
                    // Only show rejoin button if game has started and is not over
                    if (gameState['game_started'] == true && gameState['winner'] == null) {
                      // Get game code
                      final gameCode = gameState['game_code'];
                      
                      setState(() {
                        _activeGameId = gameId;
                        _activeGameCode = gameCode;
                        _activePlayerId = slotData['player_id'];
                        _isCheckingActiveGame = false;
                      });
                      return; // Found an active game, stop searching
                    }
                  } catch (e) {
                    // Game might not exist or user doesn't have access
                    continue;
                  }
                }
              } catch (e) {
                // Slot check failed, continue to next game
                continue;
              }
            }
          }
        }
      }
      
      // No active game found
      setState(() {
        _activeGameId = null;
        _activeGameCode = null;
        _activePlayerId = null;
        _isCheckingActiveGame = false;
      });
    } catch (e) {
      print('Error checking for active games: $e');
      setState(() {
        _isCheckingActiveGame = false;
      });
    }
  }

  Future<void> _rejoinActiveGame() async {
    if (_activeGameId == null || _activePlayerId == null || _currentUsername == null) {
      HomeScreenUtils.showErrorSnackBar(context, 'Unable to rejoin game');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Use the existing join endpoint which will automatically rejoin if user owns a slot
      if (_activeGameCode != null) {
        final data = await ApiService.joinGameByCode(_activeGameCode!);
        
        if (data['session_token'] != null) {
          ApiService.storeSessionToken(
              data['game_id'], _currentUsername!, data['session_token']);
        }

        _navigateToGame(data['game_id'], data['player_id'], _currentUsername!);
      } else {
        // Fallback: try to get game code from game state
        final gameState = await ApiService.getGameState(_activeGameId!);
        final gameCode = gameState['game_code'];
        
        final data = await ApiService.joinGameByCode(gameCode);
        
        if (data['session_token'] != null) {
          ApiService.storeSessionToken(
              data['game_id'], _currentUsername!, data['session_token']);
        }

        _navigateToGame(data['game_id'], data['player_id'], _currentUsername!);
      }
    } on ApiException catch (e) {
      HomeScreenUtils.showErrorSnackBar(context, 'Error rejoining game: ${e.message}');
      // Clear active game state if rejoin failed
      setState(() {
        _activeGameId = null;
        _activeGameCode = null;
        _activePlayerId = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _rejoinGameFromList(String gameCode, String gameId) async {
    if (_currentUsername == null) {
      HomeScreenUtils.showWarningSnackBar(context, 'Please log in first');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final data = await ApiService.joinGameByCode(gameCode);
      
      if (data['session_token'] != null) {
        ApiService.storeSessionToken(
            data['game_id'], _currentUsername!, data['session_token']);
      }

      _navigateToGame(data['game_id'], data['player_id'], _currentUsername!);
    } on ApiException catch (e) {
      HomeScreenUtils.showErrorSnackBar(context, 'Error rejoining game: ${e.message}');
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
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await AuthService.logout();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                  );
                }
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout),
                    const SizedBox(width: 8),
                    Text('Logout (${_currentUsername ?? 'Unknown'})'),
                  ],
                ),
              ),
            ],
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
                    const LogoSection(),

                    const SizedBox(height: 24),

                    // Welcome message
                    if (_currentUsername != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Welcome, $_currentUsername!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Active Game Rejoin Button (if user has an active game)
                    if (_activeGameId != null && _selectedAction == null) ...[
                      Container(
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
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.replay, color: Colors.orange),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Game in Progress',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'You have an active game. Rejoin to continue playing.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (_activeGameCode != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Game Code: ${_activeGameCode}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isLoading ? null : _rejoinActiveGame,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.replay, size: 24),
                                label: Text(
                                  _isLoading ? 'Rejoining...' : 'Rejoin Game',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Main Action Selection (if no action selected)
                    if (_selectedAction == null)
                      MainActionSelection(
                        isPlayerNameEntered: _currentUsername != null,
                        onActionSelected: _selectAction,
                      ),

                    // Create Game Section
                    if (_showCreateGameSection)
                      CreateGameSection(
                        isLoading: _isLoading,
                        gameId: _gameId,
                        gameCode: _gameCodeController.text.isNotEmpty
                            ? _gameCodeController.text
                            : null,
                        onCreateGame: _createGame,
                        onBackToMenu: _resetToMainMenu,
                      ),

                    // Join Game Section
                    if (_showJoinGameSection)
                      JoinGameSection(
                        gameCodeController: _gameCodeController,
                        isLoading: _isLoading,
                        onJoinGame: _joinGameByCode,
                        onBackToMenu: _resetToMainMenu,
                      ),

                    // Rejoin Game Section
                    if (_showRejoinSection)
                      RejoinGameSection(
                        gameCodeController: _gameCodeController,
                        isLoading: _isLoading,
                        onRejoinGame: _rejoinGame,
                        onJoinAsNewPlayer: () => _selectAction('join'),
                        onBackToMenu: _resetToMainMenu,
                      ),

                    // Available Games Section (if any)
                    if (_availableGames.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      AvailableGamesSection(
                        availableGames: _availableGames,
                        gameCodeController: _gameCodeController,
                        playerName: _currentUsername ?? '',
                        onActionSelected: _selectAction,
                        onJoinGameDirectly: _joinGameDirectly,
                        onDeleteGame: _deleteGame,
                        onRejoinGame: _rejoinGameFromList,
                      ),
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
}
