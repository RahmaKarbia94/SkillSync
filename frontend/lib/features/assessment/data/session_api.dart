import 'dart:convert';

import 'package:http/http.dart' as http;

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.status,
    required this.createdAt,
    this.completedAt,
    required this.hasMedia,
    this.overallScore,
  });

  final String sessionId;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final bool hasMedia;

  /// Null until the AI evaluation pipeline finishes — the dashboard uses
  /// its presence, not just `status`, to distinguish a session whose
  /// recording finished from one whose evaluation is genuinely ready.
  final double? overallScore;

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      sessionId: json['session_id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
      hasMedia: json['has_media'] as bool? ?? false,
      overallScore: (json['overall_score'] as num?)?.toDouble(),
    );
  }
}

class SessionApiException implements Exception {
  const SessionApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SessionApi {
  SessionApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Future<String> startSession() async {
    final uri = Uri.parse('$baseUrl/api/v1/sessions/start');

    final response = await http.post(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 201) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return decoded['session_id'] as String;
    }

    throw SessionApiException(
      'Failed to start session (status ${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Future<List<SessionSummary>> fetchCandidateSessions(String candidateId) async {
    final uri = Uri.parse('$baseUrl/api/v1/sessions/candidate/$candidateId');

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawList = decoded['sessions'] as List<dynamic>? ?? [];
      return rawList
          .map((item) => SessionSummary.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    throw SessionApiException(
      'Failed to load sessions (status ${response.statusCode})',
      statusCode: response.statusCode,
    );
  }
}
