import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns the correct API base URL depending on the platform.
String get apiBaseUrl {
  if (!kIsWeb && Platform.isAndroid) {
    return 'http://127.0.0.1:3001';
  }
  return 'http://127.0.0.1:3001';
}

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
