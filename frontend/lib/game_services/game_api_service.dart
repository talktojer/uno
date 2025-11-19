import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

class GameApiService {
  // Fetch game state fallback
  static Future<Map<String, dynamic>?> fetchGameState(String gameId) async {
    try {
      final response = await http.get(
        Uri.parse('${apiBaseUrl}/api/games/$gameId'),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('Fallback HTTP request failed: $e');
    }
    return null;
  }

  // Check slot reclamation
  static Future<Map<String, dynamic>> checkSlotReclamation(String gameId, String playerId) async {
    final response = await http.get(
      Uri.parse('${apiBaseUrl}/api/games/$gameId/can-reclaim/$playerId'),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw GameApiException(
        statusCode: response.statusCode,
        message: 'Failed to check slot reclamation',
      );
    }
  }

  // Reclaim slot
  static Future<Map<String, dynamic>> reclaimSlot(String gameId, String originalPlayerId, String playerName) async {
    final response = await http.post(
      Uri.parse('${apiBaseUrl}/api/games/$gameId/reclaim-slot'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'original_player_id': originalPlayerId,
        'player_name': playerName,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw GameApiException(
        statusCode: response.statusCode,
        message: 'Failed to reclaim slot',
      );
    }
  }
}

class GameApiException implements Exception {
  final int statusCode;
  final String message;

  GameApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'GameApiException: $message (Status: $statusCode)';
}
