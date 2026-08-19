import 'dart:convert';

import 'package:http/http.dart' as http;

class FillerWordAnalysis {
  const FillerWordAnalysis({
    required this.count,
    required this.densityPer100Words,
    required this.examples,
  });

  final int count;
  final double densityPer100Words;
  final List<String> examples;

  factory FillerWordAnalysis.fromJson(Map<String, dynamic> json) {
    return FillerWordAnalysis(
      count: json['count'] as int? ?? 0,
      densityPer100Words: (json['density_per_100_words'] as num?)?.toDouble() ?? 0.0,
      examples: (json['examples'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
    );
  }
}

class LogicPacingAnalysis {
  const LogicPacingAnalysis({
    required this.score,
    required this.assessment,
    required this.pacingIssues,
  });

  final double score;
  final String assessment;
  final List<String> pacingIssues;

  factory LogicPacingAnalysis.fromJson(Map<String, dynamic> json) {
    return LogicPacingAnalysis(
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      assessment: json['assessment'] as String? ?? '',
      pacingIssues: (json['pacing_issues'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
    );
  }
}

class SentimentAnalysis {
  const SentimentAnalysis({
    required this.overall,
    required this.confidence,
    required this.emotionalTone,
  });

  final String overall;
  final double confidence;
  final String emotionalTone;

  factory SentimentAnalysis.fromJson(Map<String, dynamic> json) {
    return SentimentAnalysis(
      overall: json['overall'] as String? ?? 'neutral',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      emotionalTone: json['emotional_tone'] as String? ?? '',
    );
  }
}

class EvaluationResult {
  const EvaluationResult({
    required this.sessionId,
    required this.transcript,
    required this.fillerWords,
    required this.logicPacing,
    required this.sentiment,
    required this.overallScore,
    required this.summary,
    required this.flags,
    this.evaluatedAt,
  });

  final String sessionId;
  final String transcript;
  final FillerWordAnalysis fillerWords;
  final LogicPacingAnalysis logicPacing;
  final SentimentAnalysis sentiment;
  final double overallScore;
  final String summary;
  final List<String> flags;
  final DateTime? evaluatedAt;

  factory EvaluationResult.fromJson(Map<String, dynamic> json) {
    return EvaluationResult(
      sessionId: json['session_id'] as String? ?? '',
      transcript: json['transcript'] as String? ?? '',
      fillerWords: FillerWordAnalysis.fromJson(json['filler_words'] as Map<String, dynamic>? ?? {}),
      logicPacing: LogicPacingAnalysis.fromJson(json['logic_pacing'] as Map<String, dynamic>? ?? {}),
      sentiment: SentimentAnalysis.fromJson(json['sentiment'] as Map<String, dynamic>? ?? {}),
      overallScore: (json['overall_score'] as num?)?.toDouble() ?? 0.0,
      summary: json['summary'] as String? ?? '',
      flags: (json['flags'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      evaluatedAt: json['evaluated_at'] != null ? DateTime.tryParse(json['evaluated_at'] as String) : null,
    );
  }
}

class EvaluationApiException implements Exception {
  const EvaluationApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class EvaluationApi {
  EvaluationApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Future<EvaluationResult> fetchEvaluation(String sessionId) async {
    final uri = Uri.parse('$baseUrl/api/v1/evaluations/$sessionId');

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return EvaluationResult.fromJson(decoded);
    }

    if (response.statusCode == 404) {
      throw const EvaluationApiException('No evaluation found for this session yet.', statusCode: 404);
    }

    throw EvaluationApiException(
      'Failed to load evaluation (status ${response.statusCode})',
      statusCode: response.statusCode,
    );
  }
}