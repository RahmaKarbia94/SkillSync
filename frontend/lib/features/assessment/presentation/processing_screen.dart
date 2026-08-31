import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_models.dart';
import '../../../core/providers/notification_provider.dart';
import '../../../core/theme/glass_theme.dart';
import '../providers/webrtc_provider.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  Timer? _timeoutTimer;
  bool _timedOut = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && !_handled) {
        setState(() => _timedOut = true);
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _handleNotification(AppNotification notification) {
    if (_handled) return;
    if (notification.type == AppNotificationType.evaluationCompleted &&
        notification.sessionId == widget.sessionId) {
      _handled = true;
      _timeoutTimer?.cancel();
      ref.read(webRTCProvider.notifier).reset();
      if (mounted) {
        context.go('/results/${widget.sessionId}');
      }
    }
  }

  void _returnToDashboard() {
    ref.read(webRTCProvider.notifier).reset();
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    // Strictly event-driven: reacts only to a genuine push from the
    // notification WebSocket hub (Sprint 12) — no polling of the backend.
    ref.listen<NotificationState>(notificationProvider, (previous, next) {
      final previousCount = previous?.notifications.length ?? 0;
      if (next.notifications.length > previousCount) {
        _handleNotification(next.notifications.first);
      }
    });

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassContainer(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _timedOut ? _buildTimeoutContent(context) : _buildWaitingContent(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildWaitingContent(BuildContext context) {
    return [
      const SizedBox(
        height: 48,
        width: 48,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
      const SizedBox(height: 24),
      Text(
        'Processing your assessment…',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        'We are transcribing and evaluating your responses. This usually takes less than a minute.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60),
      ),
    ];
  }

  List<Widget> _buildTimeoutContent(BuildContext context) {
    return [
      const Icon(Icons.hourglass_bottom, color: Colors.amber, size: 48),
      const SizedBox(height: 24),
      Text(
        'This is taking longer than expected',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        'Your results will appear on your dashboard as soon as they are ready.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60),
      ),
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: _returnToDashboard,
        child: const Text('Return to Dashboard'),
      ),
    ];
  }
}