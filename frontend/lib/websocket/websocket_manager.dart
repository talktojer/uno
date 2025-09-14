import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  bool get isConnected =>
      _channel != null && _channel!.sink != null && !_isConnecting;
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

      // Wait a bit for the connection to be fully established
      Timer(const Duration(milliseconds: 500), () {
        if (_channel != null && _channel!.sink != null) {
          _isConnecting = false;
          _reconnectAttempts = 0;
          print('WebSocket connection established successfully'); // Debug log
          onConnected?.call();

          // Start ping timer
          _startPingTimer();
        } else {
          print('WebSocket connection not ready after 500ms');
          _handleDisconnection();
        }
      });
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
      if (isConnected && _channel != null && _channel!.sink != null) {
        print('Sending ping to WebSocket');
        send({'type': 'ping'});
      } else {
        print('Cannot send ping - connection not ready');
        timer.cancel();
        _pingTimer = null;
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void send(Map<String, dynamic> message) {
    if (isConnected && _channel != null && _channel!.sink != null) {
      try {
        print('Sending WebSocket message: $message');
        _channel!.sink.add(json.encode(message));
      } catch (e) {
        print('Error sending WebSocket message: $e');
        _handleDisconnection();
      }
    } else {
      print(
          'Cannot send message - connection not ready. isConnected: $isConnected, channel: ${_channel != null}, sink: ${_channel?.sink != null}');
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
