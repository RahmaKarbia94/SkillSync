import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/glass_theme.dart';
import '../data/evaluation_api.dart';
import 'widgets/skills_radar_chart.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  late Future<EvaluationResult> _evaluationFuture;

  @override
  void initState() {
    super.initState();
    _evaluationFuture = _loadEvaluation();
  }

  Future<EvaluationResult> _loadEvaluation() {
    final token = ref.read(authProvider).token;
    if (token == null) {
      throw const EvaluationApiException('You must be signed in to view results.');
    }

    final api = EvaluationApi(baseUrl: 'http://localhost:8080', token: token);
    return api.fetchEvaluation(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: FutureBuilder<EvaluationResult>(
            future: _evaluationFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                );
              }

              final evaluation = snapshot.data!;
              final clarity = (100 - evaluation.fillerWords.densityPer100Words).clamp(0, 100).toDouble();
              final confidence = (evaluation.sentiment.confidence * 100).clamp(0, 100).toDouble();

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Assessment Results',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        _ScoreBadge(score: evaluation.overallScore),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SkillsRadarChart(
                      pacing: evaluation.logicPacing.score,
                      clarity: clarity,
                      confidence: confidence,
                    ),
                    const SizedBox(height: 16),
                    GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Summary',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            evaluation.summary,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sentiment Analysis',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          _SentimentTimelineTile(
                            label: 'Overall Sentiment',
                            value: evaluation.sentiment.overall.toUpperCase(),
                          ),
                          _SentimentTimelineTile(
                            label: 'Confidence',
                            value: '${(evaluation.sentiment.confidence * 100).toStringAsFixed(0)}%',
                          ),
                          _SentimentTimelineTile(
                            label: 'Emotional Tone',
                            value: evaluation.sentiment.emotionalTone,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transcript',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            evaluation.transcript.isEmpty ? 'No transcript available.' : evaluation.transcript,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    if (evaluation.flags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      GlassContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Flags',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            ...evaluation.flags.map(
                              (flag) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.flag_outlined, size: 16, color: Colors.amber),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(flag, style: const TextStyle(color: Colors.white70))),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 75 ? Colors.greenAccent : (score >= 50 ? Colors.amber : Colors.redAccent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        '${score.toStringAsFixed(0)} / 100',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SentimentTimelineTile extends StatelessWidget {
  const _SentimentTimelineTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}