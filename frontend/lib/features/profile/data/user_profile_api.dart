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

  Future<Map<String, dynamic>> syncCurrentProfile() async {
    final user = _supabase.auth.currentUser;
    final session = _supabase.auth.currentSession;
    if (user == null || session == null) {
      throw const UserProfileApiException(
        'Please sign in to update your profile.',
      );
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final name =
        (metadata['full_name'] ?? metadata['name'] ?? metadata['display_name'])
            ?.toString()
            .trim();
    final profileName = name?.isNotEmpty == true
        ? name
        : (user.email?.split('@').first ?? 'Annora member');
    return syncProfile(
      name: profileName,
      phone: metadata['contact_phone']?.toString(),
    );
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
        detail ?? 'Profile update failed (${response.statusCode}).',
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
