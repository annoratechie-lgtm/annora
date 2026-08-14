import 'package:flutter_dotenv/flutter_dotenv.dart';

String get mealPlanBackendUrl =>
    dotenv.env['ANNORA_BACKEND_URL'] ?? 'http://10.0.2.2:8000';
