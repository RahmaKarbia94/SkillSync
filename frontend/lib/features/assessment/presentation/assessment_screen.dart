import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/glass_theme.dart';
import '../providers/webrtc_provider.dart';

class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _rendererInitialized = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
    if (mounted) {
      setState(() => _rendererInitialized = true);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    super.dispose();
  }

  bool _canStart(WebRTCSessionStatus status) {
    return status == WebRTCSessionStatus.idle ||
        status == WebRTCSessionStatus.ended ||
        status == WebRTCSessionStatus.failed ||
        status == WebRTCSessionStatus.permissionDenied;
  }

  bool _canStop(WebRTCSessionStatus status) {
    return status == WebRTCSessionStatus.connecting || status == WebRTCSessionStatus.connected;
  }

  void _handleStart(String? token) {
    if (token == null) return;

    const baseWsUrl = 'ws://localhost:8080';

    ref.read(webRTCProvider.notifier).startAssessment(
          baseWsUrl: baseWsUrl,
          token: token,
          roomId: widget.sessionId,
        );
  }

  void _handleStop() {
    ref.read(webRTCProvider.notifier).stopAssessment();
  }

  @override
  Widget build(BuildContext context) {
    final webrtcState = ref.watch(webRTCProvider);
    final authState = ref.watch(authProvider);

    ref.listen(webRTCProvider, (previous, next) {
      if (_rendererInitialized) {
        _localRenderer.srcObject = next.localStream;
      }
    });

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Assessment Session',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    _StatusBadge(status: webrtcState.status),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: GlassContainer(
                    padding: const EdgeInsets.all(4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: _rendererInitialized
                          ? RTCVideoView(
                              _localRenderer,
                              mirror: true,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          : const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
                if (webrtcState.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    webrtcState.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _canStart(webrtcState.status) ? () => _handleStart(authState.token) : null,
                        icon: const Icon(Icons.videocam_outlined),
                        label: const Text('Start Session'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _canStop(webrtcState.status) ? _handleStop : null,
                        icon: const Icon(Icons.call_end_outlined),
                        label: const Text('End Session'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final WebRTCSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      WebRTCSessionStatus.idle => ('Idle', Colors.white54),
      WebRTCSessionStatus.requestingPermissions => ('Requesting Access', Colors.amber),
      WebRTCSessionStatus.permissionDenied => ('Permission Denied', Colors.redAccent),
      WebRTCSessionStatus.connecting => ('Connecting', Colors.amber),
      WebRTCSessionStatus.connected => ('Live', Colors.greenAccent),
      WebRTCSessionStatus.failed => ('Failed', Colors.redAccent),
      WebRTCSessionStatus.ended => ('Ended', Colors.white54),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}