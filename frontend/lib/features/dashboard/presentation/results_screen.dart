import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/glass_theme.dart';
import '../data/evaluation_api.dart';
import 'widgets/skills_radar_chart.dart';

final evaluationProvider = FutureProvider.family<EvaluationResult, String>((ref, sessionId) async {
  final token = ref.watch(authProvider).token;
  if (token == null) {
    throw const EvaluationApiException('You must be signed in to view results.');
  }
  final api = EvaluationApi(baseUrl: 'http://localhost:8080', token: token);
  return api.fetchEvaluation(sessionId);
});

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evaluationAsync = ref.watch(evaluationProvider(sessionId));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: evaluationAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _buildError(context, ref, error),
            data: (evaluation) => _buildResults(context, evaluation),
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, Object error) {
    final isNotFound = error is EvaluationApiException && error.statusCode == 404;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isNotFound ? Icons.hourglass_bottom : Icons.error_outline,
                color: isNotFound ? Colors.amber : Colors.redAccent,
                size: 40,
              ),
              const SizedBox(height: 16),
              Text(
                isNotFound ? 'Evaluation not ready yet' : 'Something went wrong',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                isNotFound
                    ? 'Your assessment may still be processing. Try again in a moment.'
                    : error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(evaluationProvider(sessionId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, EvaluationResult evaluation) {
    final hasSkillData = evaluation.logicPacing.score > 0 ||
        evaluation.fillerWords.densityPer100Words > 0 ||
        evaluation.sentiment.confidence > 0;

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
            hasData: hasSkillData,
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
                  evaluation.summary.isEmpty ? 'No summary available.' : evaluation.summary,
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
                  value: evaluation.sentiment.overall.isEmpty
                      ? 'N/A'
                      : evaluation.sentiment.overall.toUpperCase(),
                ),
                _SentimentTimelineTile(
                  label: 'Confidence',
                  value: '${(evaluation.sentiment.confidence * 100).toStringAsFixed(0)}%',
                ),
                _SentimentTimelineTile(
                  label: 'Emotional Tone',
                  value: evaluation.sentiment.emotionalTone.isEmpty
                      ? 'Not available'
                      : evaluation.sentiment.emotionalTone,
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
