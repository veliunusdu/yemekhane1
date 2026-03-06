import 'dart:io';
import 'package:flutter/foundation.dart';

/// Returns the correct API base URL depending on the platform.
/// - Android emulator: 10.0.2.2 (maps to host machine's localhost)
/// - Everything else (Web, Windows, iOS simulator): 127.0.0.1
String get apiBaseUrl {
  if (!kIsWeb && Platform.isAndroid) {
    return 'http://10.0.2.2:3001';
  }
  return 'http://127.0.0.1:3001';
}
