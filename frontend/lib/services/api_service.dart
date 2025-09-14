import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;
import '../config/app_config.dart';

class ApiService {
  static const String _apiBaseUrl = apiBaseUrl;

  // Game creation
  static Future<Map<String, dynamic>> createGame() async {
    final response =
        await http.post(Uri.parse('$_apiBaseUrl/api/games/create'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to create game: ${response.statusCode}');
    }
  }

  // Join game by code
  static Future<Map<String, dynamic>> joinGameByCode(
      String gameCode, String playerName) async {
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/api/games/join-by-code'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'game_code': gameCode,
        'player_name': playerName,
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
      Uri.parse('$_apiBaseUrl/api/games/code/$gameCode'),
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

  // Check player session
  static Future<Map<String, dynamic>> checkPlayerSession(
      String gameId, String playerName) async {
    final response = await http.get(
      Uri.parse('$_apiBaseUrl/api/games/$gameId/session/$playerName'),
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
      Uri.parse('$_apiBaseUrl/api/games/$gameId/can-rejoin/$playerName'),
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
  static Future<Map<String, dynamic>> rejoinGame(
      String gameId, String playerName) async {
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/api/games/$gameId/rejoin'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'player_name': playerName,
      }),
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
