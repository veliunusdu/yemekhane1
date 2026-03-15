import 'package:supabase_flutter/supabase_flutter.dart';

/// Production API URL — set this to your deployed backend HTTPS URL.
/// For local development, override via --dart-define=API_BASE_URL=http://10.0.2.2:3001
const String _kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.yourdomain.com',
);

/// Returns the correct API base URL depending on the environment.
String get apiBaseUrl => _kApiBaseUrl;

/// Returns HTTP headers with the current Supabase session token.
/// Supabase SDK token'ı otomatik yeniler — her zaman güncel token gider.
Future<Map<String, String>> authHeaders() async {
  final session = Supabase.instance.client.auth.currentSession;
  final token = session?.accessToken ?? '';
  return {
    'Content-Type': 'application/json',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
}
