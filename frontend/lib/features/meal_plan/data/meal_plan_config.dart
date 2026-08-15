import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

String get mealPlanBackendUrl {
  final configured = dotenv.env['ANNORA_BACKEND_URL']?.trim();
  final fallback = kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';

  if (configured == null || configured.isEmpty) {
    return fallback;
  }

  // 10.0.2.2 is the Android emulator's host alias and is not reachable
  // from Chrome. Keep the same .env usable across web and Android.
  if (kIsWeb && configured.contains('10.0.2.2')) {
    return configured.replaceFirst('10.0.2.2', 'localhost');
  }

  return configured;
}
