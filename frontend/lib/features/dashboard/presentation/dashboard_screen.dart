import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/glass_theme.dart';
import '../../assessment/data/session_api.dart';
import 'widgets/notification_bell.dart';

const _testCandidateId = '6a810f08796e48e5f051e7dc';

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start session: $e')));
    } finally {
      if (mounted) setState(() => _isStartingSession = false);
    }
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.greenAccent;
      case 'in_progress':
        return Colors.amber;
      case 'failed':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
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
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      children: [
                        const NotificationBell(),
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
                      Text('Signed in as', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60)),
                      const SizedBox(height: 4),
                      Text(
                        authState.role.name.toUpperCase(),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(child: isRecruiter ? _buildRecruiterView(context) : _buildCandidateView(context)),
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
              child: Text('Failed to load sessions: ${snapshot.error}',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
            ),
          );
        }
        final sessions = snapshot.data ?? [];
        if (sessions.isEmpty) {
          return GlassContainer(
            child: Center(
              child: Text('No sessions yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60)),
            ),
          );
        }
        return ListView.separated(
          itemCount: sessions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final session = sessions[index];
            return InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => context.push('/results/${session.sessionId}'),
              child: GlassContainer(
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _statusColor(session.status), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(session.status.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(_formatDate(session.createdAt), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (session.hasMedia) const Icon(Icons.videocam_outlined, color: Colors.white38, size: 18),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}