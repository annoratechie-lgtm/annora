import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfileApiException implements Exception {
  final String message;

  const UserProfileApiException(this.message);

  @override
  String toString() => message;
}

class UserProfileApi {
  final String baseUrl;
  final http.Client _client;
  final SupabaseClient _supabase;

  UserProfileApi({
    required this.baseUrl,
    http.Client? client,
    SupabaseClient? supabase,
  })  : _client = client ?? http.Client(),
        _supabase = supabase ?? Supabase.instance.client;

  Future<Map<String, dynamic>> fetchProfile() async {
    final session = _supabase.auth.currentSession;
    if (_supabase.auth.currentUser == null || session == null) {
      throw const UserProfileApiException(
        'Please sign in to view your profile.',
      );
    }

    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/users/me/profile'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${session.accessToken}',
      },
    );
    return _decodeProfileResponse(response);
  }

  Future<Map<String, dynamic>> syncProfile({
    required String? name,
    required String? phone,
  }) async {
    final user = _supabase.auth.currentUser;
    final session = _supabase.auth.currentSession;
    if (user == null || session == null) {
      throw const UserProfileApiException(
        'Please sign in to update your profile.',
      );
    }

    final response = await _client.put(
      Uri.parse('$baseUrl/api/v1/users/me/profile'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name, 'phone': phone}),
    );
    return _decodeProfileResponse(response);
  }

  Map<String, dynamic> _decodeProfileResponse(http.Response response) {
    dynamic responseBody;
    try {
      responseBody = jsonDecode(response.body);
    } on FormatException {
      responseBody = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail =
          responseBody is Map ? responseBody['detail']?.toString() : null;
      throw UserProfileApiException(
        detail ?? 'Profile request failed (${response.statusCode}).',
      );
    }
    if (responseBody is! Map<String, dynamic>) {
      throw const UserProfileApiException(
        'The backend returned an invalid profile response.',
      );
    }
    return responseBody;
  }
}
