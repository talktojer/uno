import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/lobby_websocket_service.dart';
import '../dialogs/join_game_dialog.dart';
import '../dialogs/rejoin_join_choice_dialog.dart';
import '../dialogs/invalid_game_code_dialog.dart';
import '../dialogs/rejoin_error_dialogs.dart';
import '../widgets/logo_section.dart';
import '../widgets/player_name_section.dart';
import '../widgets/main_action_selection.dart';
import '../widgets/create_game_section.dart';
import '../widgets/join_game_section.dart';
import '../widgets/rejoin_game_section.dart';
import '../widgets/available_games_section.dart';
import '../utils/home_screen_utils.dart';
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
  final LobbyWebSocketService _lobbyService = LobbyWebSocketService();

  String? _gameId;
  String? _playerId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _availableGames = [];

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
    _loadSavedPlayerName();
    _connectLobbyWebSocket();
    _handleInitialGameCode();
  }

  void _loadSavedPlayerName() {
    final savedName = StorageService.getSavedPlayerName();
    if (savedName != null && savedName.isNotEmpty) {
      _playerNameController.text = savedName;
    }
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
    _playerNameController.dispose();
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
    } on ApiException catch (e) {
      if (widget.initialGameCode != null) {
        _showInvalidGameCodeDialog(gameCode);
      }
    }
  }

  Future<void> _checkGameCodeAndSuggestAction(String gameCode) async {
    try {
      final data = await ApiService.getGameByCode(gameCode);
      final gameId = data['game_id'];
      final disconnectedCount = data['disconnected_players'] ?? 0;

      setState(() {
        _gameId = gameId;
      });

      final hasExistingSession = ApiService.hasExistingSession(gameId);
      final existingPlayerName = ApiService.getExistingPlayerName(gameId);

      if (existingPlayerName != null && _playerNameController.text.isEmpty) {
        _playerNameController.text = existingPlayerName;
        StorageService.savePlayerName(existingPlayerName);
      }

      _showRejoinOrJoinDialog(gameCode, gameId);
    } on ApiException catch (e) {
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
        preFilledName: _playerNameController.text.isNotEmpty
            ? _playerNameController.text
            : null,
        onJoin: (playerName) => _joinGameDirectly(gameCode, playerName),
      ),
    );
  }

  void _showRejoinOrJoinDialog(String gameCode, String gameId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RejoinJoinChoiceDialog(
        gameCode: gameCode,
        playerName: _playerNameController.text,
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
    if (_playerNameController.text.trim().isEmpty) {
      HomeScreenUtils.showWarningSnackBar(
          context, 'Please enter your name first');
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

      StorageService.savePlayerName(_playerNameController.text);
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
    if (_gameCodeController.text.isEmpty ||
        _playerNameController.text.isEmpty) {
      HomeScreenUtils.showWarningSnackBar(
          context, 'Please enter both game code and your name');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final data = await ApiService.joinGameByCode(
          _gameCodeController.text, _playerNameController.text);
      setState(() {
        _playerId = data['player_id'];
        _gameId = data['game_id'];
      });

      if (data['session_token'] != null) {
        ApiService.storeSessionToken(
            data['game_id'], _playerNameController.text, data['session_token']);
      }

      StorageService.savePlayerName(_playerNameController.text);
      _navigateToGame(
          data['game_id'], data['player_id'], _playerNameController.text);
    } on ApiException catch (e) {
      _handleJoinError(e);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinGameDirectly(String gameCode, String playerName) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await ApiService.joinGameByCode(gameCode, playerName);

      if (data['session_token'] != null) {
        ApiService.storeSessionToken(
            data['game_id'], playerName, data['session_token']);
      }

      StorageService.savePlayerName(playerName);
      _navigateToGame(data['game_id'], data['player_id'], playerName);
    } on ApiException catch (e) {
      _handleJoinError(e);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _rejoinGame() async {
    if (_playerNameController.text.trim().isEmpty) {
      HomeScreenUtils.showErrorSnackBar(context, 'Please enter your name');
      return;
    }

    if (_gameCodeController.text.trim().isEmpty) {
      HomeScreenUtils.showErrorSnackBar(context, 'Please enter a game code');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final gameCodeData =
          await ApiService.getGameByCode(_gameCodeController.text.trim());
      final gameId = gameCodeData['game_id'];

      final sessionData = await ApiService.checkPlayerSession(
          gameId, _playerNameController.text.trim());

      if (sessionData['has_session']) {
        final checkData = await ApiService.canRejoin(
            gameId, _playerNameController.text.trim());

        if (checkData['can_rejoin']) {
          final data = await ApiService.rejoinGame(
              gameId, _playerNameController.text.trim());
          StorageService.savePlayerName(_playerNameController.text.trim());
          _navigateToGame(
              gameId, data['player_id'], _playerNameController.text.trim());
        } else {
          _showRejoinNotPossibleDialog(gameId, checkData['message']);
        }
      } else {
        HomeScreenUtils.showWarningSnackBar(context,
            'You have not played this game before. Use "Join as New Player" instead.');
      }
    } on ApiException catch (e) {
      HomeScreenUtils.showErrorSnackBar(context, 'Rejoin failed: $e');
      _tryRejoinFallback();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
    } else if (HomeScreenUtils.isDisconnectedPlayerError(e.message)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'This slot belongs to a disconnected player. Use "Rejoin Game" instead.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
          shape: RoundedRectangleBorder(
              borderRadius: HomeScreenUtils.borderRadius),
          action: SnackBarAction(
            label: 'Rejoin',
            textColor: Colors.white,
            onPressed: () => _selectAction('rejoin'),
          ),
        ),
      );
    } else {
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

  void _clearSavedPlayerName() {
    StorageService.clearPlayerName();
    _playerNameController.clear();
    setState(() {});
  }

  void _onPlayerNameChanged(String value) {
    setState(() {});
    if (value.trim().isNotEmpty) {
      StorageService.savePlayerName(value);
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

                    // Player Name Input (Always visible)
                    PlayerNameSection(
                      controller: _playerNameController,
                      hasSavedName: StorageService.hasSavedName(),
                      onClearName: _clearSavedPlayerName,
                      onNameChanged: _onPlayerNameChanged,
                    ),

                    const SizedBox(height: 24),

                    // Main Action Selection (if no action selected)
                    if (_selectedAction == null)
                      MainActionSelection(
                        isPlayerNameEntered:
                            _playerNameController.text.trim().isNotEmpty,
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
                        playerName: _playerNameController.text,
                        onActionSelected: _selectAction,
                        onJoinGameDirectly: _joinGameDirectly,
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
