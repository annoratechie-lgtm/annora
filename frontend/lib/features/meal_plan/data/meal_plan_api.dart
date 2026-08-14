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
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw MealPlanApiException('Please sign in to view your meal plan.');
    }

    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/meal-plans/${user.id}'),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> fetchIngredients(String mealPlanId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw MealPlanApiException('Please sign in to view ingredients.');
    }

    final uri = Uri.parse('$baseUrl/api/v1/meal-plans/$mealPlanId/ingredients')
        .replace(queryParameters: {'user_id': user.id});
    final response = await _client.get(uri);
    return _decode(response);
  }

  Future<Map<String, dynamic>> fetchGroceryList(String mealPlanId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw MealPlanApiException('Please sign in to view your grocery list.');
    }

    final uri = Uri.parse('$baseUrl/api/v1/meal-plans/$mealPlanId/grocery-list')
        .replace(queryParameters: {'user_id': user.id});
    final response = await _client.get(uri);
    return _decode(response);
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
