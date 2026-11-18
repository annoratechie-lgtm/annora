import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AssistantApiException implements Exception {
  final String message;
  final int? statusCode;

  const AssistantApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// One change inside a proposal: "Thursday dinner: Aloo gobhi -> Palak paneer".
class ProposedSwap {
  final String date;
  final String mealType;
  final String fromName;
  final String toName;

  const ProposedSwap(
      {required this.date,
      required this.mealType,
      required this.fromName,
      required this.toName});
}

/// A plan change Annora proposed; applied only when the user taps Apply.
class AssistantAction {
  final String type; // 'swap' | 'new_week'
  final String summary;
  final List<ProposedSwap> swaps;
  final String? startDate;

  const AssistantAction(
      {required this.type,
      required this.summary,
      this.swaps = const [],
      this.startDate});

  static AssistantAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final changes = json['changes'];
    return AssistantAction(
      type: json['type']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      startDate: json['start_date']?.toString(),
      swaps: [
        if (changes is List)
          for (final c in changes.whereType<Map>())
            ProposedSwap(
              date: c['date']?.toString() ?? '',
              mealType: c['meal_type']?.toString() ?? '',
              fromName: (c['from'] is Map ? c['from']['name'] : null)
                      ?.toString() ??
                  '',
              toName:
                  (c['to'] is Map ? c['to']['name'] : null)?.toString() ?? '',
            ),
      ],
    );
  }
}

class ChatMessage {
  final String? id;
  final bool isUser;
  final String text;
  final AssistantAction? action;

  /// proposed | applied | dismissed | failed | expired (null without an action).
  final String? actionStatus;
  final DateTime createdAt;

  /// Shown locally only (e.g. an error); never saved.
  final bool isError;

  ChatMessage({
    this.id,
    required this.isUser,
    required this.text,
    this.action,
    this.actionStatus,
    DateTime? createdAt,
    this.isError = false,
  }) : createdAt = createdAt ?? DateTime.now();

  ChatMessage withStatus(String status) => ChatMessage(
      id: id,
      isUser: isUser,
      text: text,
      action: action,
      actionStatus: status,
      createdAt: createdAt);

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id']?.toString(),
        isUser: json['role'] == 'user',
        text: (json['content'] ?? '').toString(),
        action: AssistantAction.fromJson(json['action']),
        actionStatus: json['action_status']?.toString(),
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
      );
}

class ChatTurn {
  final ChatMessage userMessage;
  final ChatMessage reply;
  final List<String> remembered;
  const ChatTurn(this.userMessage, this.reply, this.remembered);
}

class ApplyResult {
  final ChatMessage message;
  final ChatMessage confirmation;
  const ApplyResult(this.message, this.confirmation);
}

class MemoryFact {
  final String id;
  final String fact;
  final String kind;
  const MemoryFact({required this.id, required this.fact, required this.kind});

  factory MemoryFact.fromJson(Map<String, dynamic> json) => MemoryFact(
        id: json['id'].toString(),
        fact: (json['fact'] ?? '').toString(),
        kind: (json['kind'] ?? 'other').toString(),
      );
}

/// Ask Annora backend: saved chat (one thread per user, kept 90 days),
/// confirm-before-change proposals, and what Annora remembers.
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

  Future<List<ChatMessage>> history() async {
    final body = await _send('GET', '/messages');
    final messages = body['messages'];
    return [
      if (messages is List)
        for (final m in messages.whereType<Map<String, dynamic>>())
          ChatMessage.fromJson(m),
    ];
  }

  Future<ChatTurn> send(String message) async {
    final body = await _send('POST', '/chat', {'message': message});
    return ChatTurn(
      ChatMessage.fromJson(body['user_message'] as Map<String, dynamic>),
      ChatMessage.fromJson(body['reply'] as Map<String, dynamic>),
      [
        if (body['remembered'] is List)
          for (final r in body['remembered'] as List) r.toString(),
      ],
    );
  }

  Future<ApplyResult> apply(String messageId) async {
    final body = await _send('POST', '/messages/$messageId/apply');
    return ApplyResult(
      ChatMessage.fromJson(body['message'] as Map<String, dynamic>),
      ChatMessage.fromJson(body['confirmation'] as Map<String, dynamic>),
    );
  }

  Future<ChatMessage> dismiss(String messageId) async {
    final body = await _send('POST', '/messages/$messageId/dismiss');
    return ChatMessage.fromJson(body['message'] as Map<String, dynamic>);
  }

  Future<void> clearChat() => _send('DELETE', '/messages');

  Future<List<MemoryFact>> memory() async {
    final body = await _send('GET', '/memory');
    final rows = body['memory'];
    return [
      if (rows is List)
        for (final m in rows.whereType<Map<String, dynamic>>())
          MemoryFact.fromJson(m),
    ];
  }

  Future<MemoryFact> addMemory(String fact, {String kind = 'preference'}) async =>
      MemoryFact.fromJson(
          await _send('POST', '/memory', {'fact': fact, 'kind': kind}));

  Future<MemoryFact> updateMemory(String id, String fact) async =>
      MemoryFact.fromJson(await _send('PATCH', '/memory/$id', {'fact': fact}));

  Future<void> deleteMemory(String id) => _send('DELETE', '/memory/$id');

  Future<Map<String, dynamic>> _send(String method, String path,
      [Map<String, dynamic>? json]) async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw const AssistantApiException('Please sign in to use Annora Assist.');
    }
    final request =
        http.Request(method, Uri.parse('$baseUrl/api/v1/assistant$path'))
          ..headers.addAll({
            'Accept': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
            if (json != null) 'Content-Type': 'application/json',
          });
    if (json != null) request.body = jsonEncode(json);

    late final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException {
      throw const AssistantApiException(
          "Couldn't reach Annora. Check your connection and try again.");
    }

    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        body = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body is Map<String, dynamic> ? body['detail'] : null;
      throw AssistantApiException(
        detail is String
            ? detail
            : 'Annora request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return body is Map<String, dynamic> ? body : <String, dynamic>{};
  }
}
