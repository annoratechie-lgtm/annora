import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class MealPlanApiException implements Exception {
  final String message;
  MealPlanApiException(this.message);

  @override
  String toString() => message;
}

class MealPlanApi {
  final String baseUrl;
  final http.Client _client;
  final SupabaseClient _supabase;

  MealPlanApi({
    required this.baseUrl,
    http.Client? client,
    SupabaseClient? supabase,
  })  : _client = client ?? http.Client(),
        _supabase = supabase ?? Supabase.instance.client;

  Future<Map<String, dynamic>> fetchMealPlan() async {
    final user = _requireUser();
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/meal-plans/${user.id}'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> generateMealPlan({DateTime? startDate}) async {
    final user = _requireUser();
    final date = startDate ?? DateTime.now();
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/meal-plans/generate'),
      headers: {
        ...await _headers(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'user_id': user.id,
        'start_date': _dateOnly(date),
      }),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> fetchIngredients(String mealPlanId) async {
    final user = _requireUser();
    final uri = Uri.parse('$baseUrl/api/v1/meal-plans/$mealPlanId/ingredients')
        .replace(queryParameters: {'user_id': user.id});
    final response = await _client.get(uri, headers: await _headers());
    return _decode(response);
  }

  Future<Map<String, dynamic>> generateIngredients(String mealPlanId) async {
    final user = _requireUser();
    final uri = Uri.parse('$baseUrl/api/v1/meal-plans/$mealPlanId/ingredients')
        .replace(queryParameters: {'user_id': user.id});
    final response = await _client.post(uri, headers: await _headers());
    return _decode(response);
  }

  Future<Map<String, dynamic>> fetchGroceryList(String mealPlanId) async {
    final user = _requireUser();
    final uri = Uri.parse('$baseUrl/api/v1/meal-plans/$mealPlanId/grocery-list')
        .replace(queryParameters: {'user_id': user.id});
    final response = await _client.get(uri, headers: await _headers());
    return _decode(response);
  }

  Future<Map<String, dynamic>> generateGroceryList(String mealPlanId) async {
    final user = _requireUser();
    final uri = Uri.parse('$baseUrl/api/v1/meal-plans/$mealPlanId/grocery-list')
        .replace(queryParameters: {'user_id': user.id});
    final response = await _client.post(uri, headers: await _headers());
    return _decode(response);
  }

  User _requireUser() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw MealPlanApiException('Please sign in to use meal planning.');
    }
    return user;
  }

  Future<Map<String, String>> _headers() async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw MealPlanApiException('Your session has expired. Please sign in again.');
    }
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  String _dateOnly(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body is Map<String, dynamic> ? body['detail'] : null;
      throw MealPlanApiException(
        detail?.toString() ?? 'Meal plan request failed (${response.statusCode}).',
      );
    }
    if (body is! Map<String, dynamic>) {
      throw MealPlanApiException('The backend returned an invalid response.');
    }
    return body;
  }
}
