import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _usernameKey = 'username';
  static const String _lastUsernameKey =
      'last_username'; // For remembering username

  static String? _currentToken;
  static String? _currentUsername;
  static bool _isTokenValidated = false;

  // Get current token
  static String? get currentToken => _currentToken;
  static String? get currentUsername => _currentUsername;
  static bool get isLoggedIn =>
      _currentToken != null && _currentUsername != null && _isTokenValidated;

  // Initialize auth service with token validation
  static Future<void> initialize() async {
    await _loadStoredCredentials();
    if (_currentToken != null) {
      // Validate token on startup
      await _validateToken();
    }
  }

  // Validate stored token
  static Future<bool> _validateToken() async {
    if (_currentToken == null) {
      _isTokenValidated = false;
      return false;
    }

    try {
      final userInfo = await getCurrentUser();
      if (userInfo != null) {
        _isTokenValidated = true;
        return true;
      } else {
        // Token is invalid, clear it
        await clearCredentials();
        _isTokenValidated = false;
        return false;
      }
    } catch (e) {
      // Network error - assume token is still valid for now
      _isTokenValidated = true;
      return true;
    }
  }

  // Load stored credentials from SharedPreferences
  static Future<void> _loadStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _currentToken = prefs.getString(_tokenKey);
    _currentUsername = prefs.getString(_usernameKey);
  }

  // Get last used username (for pre-filling login form)
  static Future<String?> getLastUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastUsernameKey);
  }

  // Save last used username
  static Future<void> _saveLastUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUsernameKey, username);
  }

  // Store credentials
  static Future<void> _storeCredentials(String token, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_usernameKey, username);
    _currentToken = token;
    _currentUsername = username;
  }

  // Clear credentials
  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
    _currentToken = null;
    _currentUsername = null;
    _isTokenValidated = false;
  }

  // Sign up
  static Future<AuthResult> signUp(String username, String pin) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/auth/signup'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'pin': pin,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storeCredentials(data['access_token'], data['username']);
        await _saveLastUsername(data['username']);
        _isTokenValidated = true;
        return AuthResult.success(data['username']);
      } else {
        final error = jsonDecode(response.body);
        return AuthResult.error(error['detail'] ?? 'Sign up failed');
      }
    } catch (e) {
      return AuthResult.error('Network error: $e');
    }
  }

  // Login
  static Future<AuthResult> login(String username, String pin) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/auth/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'pin': pin,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storeCredentials(data['access_token'], data['username']);
        await _saveLastUsername(data['username']);
        _isTokenValidated = true;
        return AuthResult.success(data['username']);
      } else {
        final error = jsonDecode(response.body);
        return AuthResult.error(error['detail'] ?? 'Login failed');
      }
    } catch (e) {
      return AuthResult.error('Network error: $e');
    }
  }

  // Get current user info
  static Future<UserInfo?> getCurrentUser() async {
    if (_currentToken == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/auth/me'),
        headers: {
          'Authorization': 'Bearer $_currentToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return UserInfo(
          username: data['username'],
          createdAt: DateTime.parse(data['created_at']),
        );
      } else if (response.statusCode == 401) {
        // Token expired or invalid
        await clearCredentials();
        _isTokenValidated = false;
        return null;
      }
    } catch (e) {
      // Network error, keep current credentials but mark as unvalidated
      _isTokenValidated = false;
    }
    return null;
  }

  // Logout
  static Future<void> logout() async {
    await clearCredentials();
  }

  // Get authorization header
  static Map<String, String> getAuthHeaders() {
    if (_currentToken == null) return {};
    return {'Authorization': 'Bearer $_currentToken'};
  }

  // Validate PIN format
  static bool isValidPin(String pin) {
    return pin.length == 4 && pin.contains(RegExp(r'^\d+$'));
  }

  // Validate username format
  static bool isValidUsername(String username) {
    final trimmed = username.trim();
    return trimmed.length >= 3 && trimmed.length <= 20;
  }
}

class AuthResult {
  final bool isSuccess;
  final String? username;
  final String? error;

  AuthResult._(this.isSuccess, this.username, this.error);

  factory AuthResult.success(String username) {
    return AuthResult._(true, username, null);
  }

  factory AuthResult.error(String error) {
    return AuthResult._(false, null, error);
  }
}

class UserInfo {
  final String username;
  final DateTime createdAt;

  UserInfo({required this.username, required this.createdAt});
}
