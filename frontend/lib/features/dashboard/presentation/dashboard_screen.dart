import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/glass_theme.dart';
import '../../assessment/data/session_api.dart';

// Stands in for a real candidate roster/picker feature, not yet built.
const _testCandidateId = '6a810f08796e48e5f051e7dc';

enum _SessionDisplayStatus { pending, inProgress, processing, completed, failed }

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isStartingSession = false;
  Future<List<SessionSummary>>? _sessionsFuture;

  @override
  void initState() {
    super.initState();
    final authState = ref.read(authProvider);
    if (authState.role == UserRole.recruiter && authState.token != null) {
      _sessionsFuture = SessionApi(baseUrl: 'http://localhost:8080', token: authState.token!)
          .fetchCandidateSessions(_testCandidateId);
    }
  }

  Future<void> _refreshSessions() async {
    final authState = ref.read(authProvider);
    if (authState.token == null) return;
    setState(() {
      _sessionsFuture = SessionApi(baseUrl: 'http://localhost:8080', token: authState.token!)
          .fetchCandidateSessions(_testCandidateId);
    });
  }

  Future<void> _startAssessment() async {
    final token = ref.read(authProvider).token;
    if (token == null) return;

    setState(() => _isStartingSession = true);

    try {
      final api = SessionApi(baseUrl: 'http://localhost:8080', token: token);
      final sessionId = await api.startSession();
      if (!mounted) return;
      context.push('/assessment/$sessionId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start session: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isStartingSession = false);
      }
    }
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  /// Backend session.status is a coarse lifecycle field — `completed`
  /// fires as soon as the recording uploads, before the AI evaluation
  /// necessarily exists. The dashboard resolves the finer-grained display
  /// status by also checking whether an evaluation score has actually
  /// arrived, so "Processing" and "Completed" are visually distinct even
  /// though both share the same backend status value.
  _SessionDisplayStatus _resolveStatus(SessionSummary s) {
    switch (s.status) {
      case 'pending':
        return _SessionDisplayStatus.pending;
      case 'in_progress':
        return _SessionDisplayStatus.inProgress;
      case 'failed':
      case 'expired':
        return _SessionDisplayStatus.failed;
      case 'completed':
        return s.overallScore != null ? _SessionDisplayStatus.completed : _SessionDisplayStatus.processing;
      default:
        return _SessionDisplayStatus.pending;
    }
  }

  (String, Color) _statusPresentation(_SessionDisplayStatus status) {
    switch (status) {
      case _SessionDisplayStatus.pending:
        return ('PENDING', Colors.white54);
      case _SessionDisplayStatus.inProgress:
        return ('IN PROGRESS', Colors.amber);
      case _SessionDisplayStatus.processing:
        return ('PROCESSING', Colors.lightBlueAccent);
      case _SessionDisplayStatus.completed:
        return ('COMPLETED', Colors.greenAccent);
      case _SessionDisplayStatus.failed:
        return ('FAILED', Colors.redAccent);
    }
  }

  Color _scoreColor(double score) {
    if (score >= 75) return Colors.greenAccent;
    if (score >= 50) return Colors.amber;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isRecruiter = authState.role == UserRole.recruiter;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Dashboard',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Row(
                      children: [
                        if (isRecruiter)
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.white70),
                            onPressed: _refreshSessions,
                          ),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white70),
                          onPressed: () => ref.read(authProvider.notifier).logout(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                GlassContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signed in as',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white60,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        authState.role.name.toUpperCase(),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isRecruiter ? _buildRecruiterView(context) : _buildCandidateView(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateView(BuildContext context) {
    return GlassContainer(
      child: Center(
        child: ElevatedButton.icon(
          onPressed: _isStartingSession ? null : _startAssessment,
          icon: _isStartingSession
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : const Icon(Icons.play_circle_outline),
          label: Text(_isStartingSession ? 'Starting…' : 'Start Assessment'),
        ),
      ),
    );
  }

  Widget _buildRecruiterView(BuildContext context) {
    return FutureBuilder<List<SessionSummary>>(
      future: _sessionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return GlassContainer(
            child: Center(
              child: Text(
                'Failed to load sessions: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          );
        }

        final sessions = snapshot.data ?? [];

        if (sessions.isEmpty) {
          return GlassContainer(
            child: Center(
              child: Text(
                'No sessions yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60),
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: sessions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final session = sessions[index];
            final displayStatus = _resolveStatus(session);
            final (statusLabel, statusColor) = _statusPresentation(displayStatus);
            final isTappable = displayStatus == _SessionDisplayStatus.completed;

            return Opacity(
              opacity: isTappable ? 1.0 : 0.85,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                // Route blocking: in-progress/processing sessions have no
                // tap handler at all, not just a visual disabled state.
                onTap: isTappable ? () => context.go('/results/${session.sessionId}') : null,
                child: GlassContainer(
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: statusColor.withOpacity(0.4)),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatDate(session.createdAt),
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (session.overallScore != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _scoreColor(session.overallScore!).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _scoreColor(session.overallScore!).withOpacity(0.4)),
                          ),
                          child: Text(
                            '${session.overallScore!.toStringAsFixed(0)}/100',
                            style: TextStyle(
                              color: _scoreColor(session.overallScore!),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (session.hasMedia)
                        const Icon(Icons.videocam_outlined, color: Colors.white38, size: 18),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: isTappable ? Colors.white38 : Colors.white12),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}