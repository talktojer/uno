import 'dart:async';
import '../websocket/websocket_manager.dart';
import '../config/app_config.dart';

class GameWebSocketService {
  WebSocketManager? _gameWebSocket;
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  bool _isConnected = false;
  bool _isConnecting = true;
  bool _isReconnecting = false;
  bool _canReclaimSlot = false;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isReconnecting => _isReconnecting;
  bool get canReclaimSlot => _canReclaimSlot;

  void connect(String gameId, String playerId, String playerName) {
    final wsUrl = '$wsBaseUrl/ws/$gameId/$playerId';
    print('Connecting to WebSocket: $wsUrl');
    _gameWebSocket = WebSocketManager();
    _gameWebSocket!.connect(wsUrl);

    _gameWebSocket!.onMessage = (message) {
      print('WebSocket received: $message');
      _messageController.add(message);
    };

    _gameWebSocket!.onError = (error) {
      print('WebSocket error: $error');
      _isConnected = false;
      _isConnecting = false;
      _isReconnecting = false;
    };

    _gameWebSocket!.onConnected = () {
      print('WebSocket connected');
      _isConnected = true;
      _isConnecting = false;
      _isReconnecting = false;

      // Wait a bit for the connection to be fully stable before sending messages
      Timer(const Duration(milliseconds: 1000), () {
        if (_gameWebSocket != null && _gameWebSocket!.isConnected) {
          print('Sending initial messages after connection stabilization');

          // Send a ping to confirm the connection is working
          _gameWebSocket!.send({'type': 'ping'});

          // Also send a join message to ensure the server knows we're here
          _gameWebSocket!.send({
            'type': 'join_game',
            'game_id': gameId,
            'player_id': playerId,
            'player_name': playerName,
          });
        }
      });
    };

    _gameWebSocket!.onDisconnected = () {
      print('WebSocket connection closed');
      _isConnected = false;
      _isConnecting = false;
      _isReconnecting = true;
    };
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_gameWebSocket != null && _gameWebSocket!.isConnected) {
      _gameWebSocket!.send(message);
    }
  }

  void reconnect() {
    if (_gameWebSocket != null) {
      _isConnecting = true;
      _isReconnecting = true;
      _gameWebSocket!.reconnect();
    }
  }

  void disconnect() {
    _gameWebSocket?.disconnect();
    _gameWebSocket = null;
    _isConnected = false;
    _isConnecting = false;
    _isReconnecting = false;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }

  void setCanReclaimSlot(bool canReclaim) {
    _canReclaimSlot = canReclaim;
  }
}
