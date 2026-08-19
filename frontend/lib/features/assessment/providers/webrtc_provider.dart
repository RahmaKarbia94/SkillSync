import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/webrtc/signaling_client.dart';
import '../../../core/webrtc/webrtc_service.dart';

enum WebRTCSessionStatus {
  idle,
  requestingPermissions,
  permissionDenied,
  connecting,
  connected,
  failed,
  ended,
}

class WebRTCState {
  const WebRTCState({
    this.status = WebRTCSessionStatus.idle,
    this.localStream,
    this.errorMessage,
  });

  final WebRTCSessionStatus status;
  final MediaStream? localStream;
  final String? errorMessage;

  WebRTCState copyWith({
    WebRTCSessionStatus? status,
    MediaStream? localStream,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WebRTCState(
      status: status ?? this.status,
      localStream: localStream ?? this.localStream,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final signalingClientProvider = Provider<SignalingClient>((ref) {
  final client = SignalingClient();
  ref.onDispose(client.dispose);
  return client;
});

final webRTCServiceProvider = Provider<WebRTCService>((ref) {
  final signalingClient = ref.watch(signalingClientProvider);
  final service = WebRTCService(signalingClient: signalingClient);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

class WebRTCNotifier extends Notifier<WebRTCState> {
  late final WebRTCService _service;
  StreamSubscription<MediaStream?>? _streamSub;
  StreamSubscription<RTCPeerConnectionState>? _connectionSub;
  StreamSubscription<RTCIceConnectionState>? _iceConnectionSub;

  @override
  WebRTCState build() {
    _service = ref.watch(webRTCServiceProvider);

    _streamSub = _service.onLocalStream.listen((stream) {
      state = state.copyWith(localStream: stream);
    });

    _connectionSub = _service.onConnectionStateChange.listen(_handlePeerConnectionState);
    _iceConnectionSub = _service.onIceConnectionStateChange.listen(_handleIceConnectionState);

    ref.onDispose(() {
      _streamSub?.cancel();
      _connectionSub?.cancel();
      _iceConnectionSub?.cancel();
    });

    return const WebRTCState();
  }

  void _handlePeerConnectionState(RTCPeerConnectionState connState) {
    switch (connState) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _markConnected();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        state = state.copyWith(status: WebRTCSessionStatus.failed, errorMessage: 'Connection failed');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        state = state.copyWith(status: WebRTCSessionStatus.ended);
        break;
      default:
        break;
    }
  }

  void _handleIceConnectionState(RTCIceConnectionState iceState) {
    switch (iceState) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _markConnected();
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        state = state.copyWith(status: WebRTCSessionStatus.failed, errorMessage: 'ICE connection failed');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        state = state.copyWith(status: WebRTCSessionStatus.ended);
        break;
      default:
        break;
    }
  }

  void _markConnected() {
    if (state.status != WebRTCSessionStatus.connected) {
      state = state.copyWith(status: WebRTCSessionStatus.connected, clearError: true);
    }
  }

  Future<bool> _ensurePermissions() async {
    try {
      final statuses = await [Permission.camera, Permission.microphone].request();
      final granted = statuses.values.every((status) => status.isGranted);
      if (!granted) {
        state = state.copyWith(
          status: WebRTCSessionStatus.permissionDenied,
          errorMessage: 'Camera and microphone access are required to start the assessment.',
        );
      }
      return granted;
    } catch (_) {
      return true;
    }
  }

  Future<void> startAssessment({
    required String baseWsUrl,
    required String token,
    required String roomId,
  }) async {
    state = state.copyWith(status: WebRTCSessionStatus.requestingPermissions, clearError: true);

    final permitted = await _ensurePermissions();
    if (!permitted) return;

    state = state.copyWith(status: WebRTCSessionStatus.connecting);

    try {
      await _service.startLocalMedia();
      await _service.startSession(baseWsUrl: baseWsUrl, token: token, roomId: roomId);
    } catch (e) {
      state = state.copyWith(status: WebRTCSessionStatus.failed, errorMessage: e.toString());
    }
  }

  Future<void> stopAssessment() async {
    await _service.stopSession();
    await _service.stopLocalMedia();
    state = const WebRTCState(status: WebRTCSessionStatus.ended);
  }
}

final webRTCProvider = NotifierProvider<WebRTCNotifier, WebRTCState>(WebRTCNotifier.new);