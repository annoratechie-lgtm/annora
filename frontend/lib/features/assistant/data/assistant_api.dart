import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AssistantApiException implements Exception {
  final String message;

  const AssistantApiException(this.message);

  @override
  String toString() => message;
}

class AssistantApi {
  final String baseUrl;
  final http.Client _client;
  final SupabaseClient _supabase;

  AssistantApi({
    required this.baseUrl,
    http.Client? client,
    SupabaseClient? supabase,
  })  : _client = client ?? http.Client(),
        _supabase = supabase ?? Supabase.instance.client;

  Future<String> ask(String message) async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw const AssistantApiException(
        'Please sign in to use Annora Assist.',
      );
    }

    late final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$baseUrl/api/v1/assistant/chat'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'message': message}),
      );
    } on http.ClientException catch (error) {
      throw AssistantApiException('Could not connect to Annora Assist: $error');
    }

    dynamic body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body is Map<String, dynamic> ? body['detail'] : null;
      throw AssistantApiException(
        detail?.toString() ??
            'Annora Assist request failed (${response.statusCode}).',
      );
    }
    if (body is! Map<String, dynamic> || body['answer'] is! String) {
      throw const AssistantApiException(
        'Annora Assist returned an invalid response.',
      );
    }
    return (body['answer'] as String).trim();
  }
}
