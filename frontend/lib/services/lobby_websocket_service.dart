import 'dart:async';
import '../websocket/websocket_manager.dart';
import '../config/app_config.dart';

class LobbyWebSocketService {
  WebSocketManager? _lobbyWebSocket;
  final StreamController<List<Map<String, dynamic>>> _gameListController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<List<Map<String, dynamic>>> get gameListStream =>
      _gameListController.stream;

  void connect() {
    // Generate a temporary player ID for lobby connection
    final tempPlayerId = 'lobby_${DateTime.now().millisecondsSinceEpoch}';
    final wsUrl = '$wsBaseUrl/ws/lobby/$tempPlayerId';
    _lobbyWebSocket = WebSocketManager();
    _lobbyWebSocket!.connect(wsUrl);

    _lobbyWebSocket!.onMessage = (message) {
      print('Lobby WebSocket received: $message');
      final messageData = message;
      if (messageData['type'] == 'game_list_update') {
        final games = List<Map<String, dynamic>>.from(messageData['games']);
        _gameListController.add(games);
        print('Game list updated: ${messageData['games']}');
      } else if (messageData['type'] == 'pong') {
        print('Lobby pong received');
      }
    };

    _lobbyWebSocket!.onError = (error) {
      print('Lobby WebSocket error: $error');
    };

    _lobbyWebSocket!.onDisconnected = () {
      print('Lobby WebSocket connection closed');
    };

    // Send a ping to test the connection
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_lobbyWebSocket != null && _lobbyWebSocket!.isConnected) {
        _lobbyWebSocket!.send({'type': 'ping'});
      }
    });
  }

  void disconnect() {
    _lobbyWebSocket?.disconnect();
    _lobbyWebSocket = null;
  }

  void dispose() {
    disconnect();
    _gameListController.close();
  }
}
