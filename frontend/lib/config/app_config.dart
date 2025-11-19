import 'dart:js' as js;

// API Configuration - reads from window.APP_CONFIG or uses defaults
String get apiBaseUrl {
  try {
    final config = js.context['APP_CONFIG'];
    if (config != null && config['apiBaseUrl'] != null) {
      return config['apiBaseUrl'] as String;
    }
  } catch (e) {
    print('Error reading API_BASE_URL from config: $e');
  }
  // Default fallback
  return 'https://uno-api.jersweb.net';
}

String get wsBaseUrl {
  try {
    final config = js.context['APP_CONFIG'];
    if (config != null && config['wsBaseUrl'] != null) {
      return config['wsBaseUrl'] as String;
    }
  } catch (e) {
    print('Error reading WS_BASE_URL from config: $e');
  }
  // Default fallback
  return 'wss://uno-api.jersweb.net';
}

String get baseUrl {
  try {
    final config = js.context['APP_CONFIG'];
    if (config != null && config['baseUrl'] != null) {
      return config['baseUrl'] as String;
    }
  } catch (e) {
    print('Error reading BASE_URL from config: $e');
  }
  // Default fallback
  return 'https://uno.jersweb.net';
}
