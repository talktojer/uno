import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;
import '../config/app_config.dart';
import 'auth_service.dart';

class ApiService {
  // Helper method to get headers with authentication
  static Map<String, String> _getHeaders() {
    final headers = {'Content-Type': 'application/json'};
    headers.addAll(AuthService.getAuthHeaders());
    return headers;
  }

  // Game creation
  static Future<Map<String, dynamic>> createGame() async {
    final response = await http.post(
      Uri.parse('${apiBaseUrl}/api/games/create'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: errorData['detail'] ?? 'Failed to create game',
      );
    }
  }

  // Join game by code
  static Future<Map<String, dynamic>> joinGameByCode(String gameCode) async {
    final response = await http.post(
      Uri.parse('${apiBaseUrl}/api/games/join-by-code'),
      headers: _getHeaders(),
      body: json.encode({
        'game_code': gameCode,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: errorData['detail'] ?? 'Failed to join game',
      );
    }
  }

  // Get game by code
  static Future<Map<String, dynamic>> getGameByCode(String gameCode) async {
    final response = await http.get(
      Uri.parse('${apiBaseUrl}/api/games/code/$gameCode'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 410) {
      final errorData = json.decode(response.body);
      throw GameEndedException(errorData['detail'] ?? 'Game has ended');
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Game not found',
      );
    }
  }

  // List games
  static Future<Map<String, dynamic>> listGames() async {
    final response = await http.get(
      Uri.parse('${apiBaseUrl}/api/games'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to list games',
      );
    }
  }

  // Get game state
  static Future<Map<String, dynamic>> getGameState(String gameId) async {
    final response = await http.get(
      Uri.parse('${apiBaseUrl}/api/games/$gameId'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to get game state',
      );
    }
  }

  // Get my slot information in a game
  static Future<Map<String, dynamic>> getMySlot(String gameId) async {
    final response = await http.get(
      Uri.parse('${apiBaseUrl}/api/games/$gameId/my-slot'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to get slot information',
      );
    }
  }

  // Check player session
  static Future<Map<String, dynamic>> checkPlayerSession(
      String gameId, String playerName) async {
    final response = await http.get(
      Uri.parse('${apiBaseUrl}/api/games/$gameId/session/$playerName'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to check player session',
      );
    }
  }

  // Check if player can rejoin
  static Future<Map<String, dynamic>> canRejoin(
      String gameId, String playerName) async {
    final response = await http.get(
      Uri.parse('${apiBaseUrl}/api/games/$gameId/can-rejoin/$playerName'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to check rejoin eligibility',
      );
    }
  }

  // Rejoin game
  static Future<Map<String, dynamic>> rejoinGame(String gameId) async {
    final response = await http.post(
      Uri.parse('${apiBaseUrl}/api/games/$gameId/rejoin'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: errorData['detail'] ?? 'Failed to rejoin game',
      );
    }
  }

  // Delete game
  static Future<Map<String, dynamic>> deleteGame(String gameId) async {
    final response = await http.delete(
      Uri.parse('${apiBaseUrl}/api/games/$gameId'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: errorData['detail'] ?? 'Failed to delete game',
      );
    }
  }

  // Store session token
  static void storeSessionToken(
      String gameId, String playerName, String sessionToken) {
    try {
      final storageKey = 'uno_session_${gameId}_$playerName';
      html.window.localStorage[storageKey] = sessionToken;
    } catch (e) {
      print('Error storing session token: $e');
    }
  }

  // Check for existing session
  static bool hasExistingSession(String gameId) {
    try {
      final keys = html.window.localStorage.keys;
      return keys.any((key) => key.startsWith('uno_session_${gameId}_'));
    } catch (e) {
      return false;
    }
  }

  // Get existing player name from session
  static String? getExistingPlayerName(String gameId) {
    try {
      final keys = html.window.localStorage.keys;
      for (final key in keys) {
        if (key.startsWith('uno_session_${gameId}_')) {
          final parts = key.split('_');
          if (parts.length >= 3) {
            return parts.sublist(2).join('_');
          }
        }
      }
    } catch (e) {
      print('Error getting existing player name: $e');
    }
    return null;
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

class GameEndedException implements Exception {
  final String message;

  GameEndedException(this.message);

  @override
  String toString() => 'GameEndedException: $message';
}
