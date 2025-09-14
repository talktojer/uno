import 'dart:html' as html;

class StorageService {
  static const String _playerNameKey = 'uno_player_name';

  // Player name management
  static String? getSavedPlayerName() {
    try {
      return html.window.localStorage[_playerNameKey];
    } catch (e) {
      print('Error loading saved player name: $e');
      return null;
    }
  }

  static void savePlayerName(String name) {
    try {
      if (name.trim().isNotEmpty) {
        html.window.localStorage[_playerNameKey] = name.trim();
      }
    } catch (e) {
      print('Error saving player name: $e');
    }
  }

  static void clearPlayerName() {
    try {
      html.window.localStorage.remove(_playerNameKey);
    } catch (e) {
      print('Error clearing player name: $e');
    }
  }

  static bool hasSavedName() {
    try {
      final savedName = html.window.localStorage[_playerNameKey];
      return savedName != null && savedName.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // URL management
  static String? getGameCodeFromUrl() {
    try {
      final uri = html.window.location;
      final pathname = uri.pathname;
      if (pathname != null &&
          pathname.length == 6 &&
          pathname.startsWith('/')) {
        final gameCode = pathname.substring(1);
        if (gameCode.length == 5) {
          return gameCode;
        }
      }
    } catch (e) {
      // Not running on web or error occurred
    }
    return null;
  }

  // Clipboard operations
  static Future<void> copyToClipboard(String text) async {
    try {
      await html.window.navigator.clipboard?.writeText(text);
    } catch (e) {
      print('Error copying to clipboard: $e');
    }
  }
}
