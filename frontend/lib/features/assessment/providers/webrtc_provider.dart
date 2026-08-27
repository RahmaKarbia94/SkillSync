import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/webrtc/signaling_client.dart';
import '../../../core/webrtc/webrtc_service.dart';
import '../data/session_api.dart';

enum WebRTCSessionStatus {
  idle,
  preparingSession,
  requestingPermissions,
  permissionDenied,
  acquiringMedia,
  connecting,
  live,
  failed,
  ended,
}

class WebRTCState {
  const WebRTCState({
    this.status = WebRTCSessionStatus.idle,
    this.sessionId,
    this.localStream,
    this.errorMessage,
    this.videoDevices = const [],
    this.audioDevices = const [],
    this.selectedCameraId,
    this.selectedMicId,
  });

  final WebRTCSessionStatus status;
  final String? sessionId;
  final MediaStream? localStream;
  final String? errorMessage;
  final List<MediaDeviceOption> videoDevices;
  final List<MediaDeviceOption> audioDevices;
  final String? selectedCameraId;
  final String? selectedMicId;

  WebRTCState copyWith({
    WebRTCSessionStatus? status,
    String? sessionId,
    MediaStream? localStream,
    String? errorMessage,
    bool clearError = false,
    List<MediaDeviceOption>? videoDevices,
    List<MediaDeviceOption>? audioDevices,
    String? selectedCameraId,
    String? selectedMicId,
  }) {
    return WebRTCState(
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      localStream: localStream ?? this.localStream,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      videoDevices: videoDevices ?? this.videoDevices,
      audioDevices: audioDevices ?? this.audioDevices,
      selectedCameraId: selectedCameraId ?? this.selectedCameraId,
      selectedMicId: selectedMicId ?? this.selectedMicId,
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

  Future<void> loadDevices() async {
    try {
      final devices = await _service.getAvailableDevices();
      final videoDevices = devices.where((d) => d.kind == 'videoinput').toList();
      final audioDevices = devices.where((d) => d.kind == 'audioinput').toList();

      state = state.copyWith(
        videoDevices: videoDevices,
        audioDevices: audioDevices,
        selectedCameraId: state.selectedCameraId ?? (videoDevices.isNotEmpty ? videoDevices.first.deviceId : null),
        selectedMicId: state.selectedMicId ?? (audioDevices.isNotEmpty ? audioDevices.first.deviceId : null),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load devices: $e');
    }
  }

  void selectCamera(String deviceId) {
    state = state.copyWith(selectedCameraId: deviceId);
  }

  void selectMic(String deviceId) {
    state = state.copyWith(selectedMicId: deviceId);
  }

  void _handlePeerConnectionState(RTCPeerConnectionState connState) {
    switch (connState) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _markLive();
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
        _markLive();
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

  void _markLive() {
    if (state.status != WebRTCSessionStatus.live) {
      state = state.copyWith(status: WebRTCSessionStatus.live, clearError: true);
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

  /// Orchestrates the full pre-flight sequence: create (or reuse) a real
  /// session id -> acquire the local media stream using the user's exact
  /// selected devices -> connect the signaling WebSocket with that id.
  ///
  /// [existingSessionId], if provided (e.g. a session already created by the
  /// calling screen's navigation flow), is reused as-is rather than creating
  /// a redundant duplicate session record.
  Future<void> startAssessment({
    required String baseWsUrl,
    required String apiBaseUrl,
    required String token,
    String? existingSessionId,
  }) async {
    state = state.copyWith(status: WebRTCSessionStatus.preparingSession, clearError: true);

    String sessionId;
    if (existingSessionId != null && existingSessionId.isNotEmpty) {
      sessionId = existingSessionId;
    } else {
      try {
        final sessionApi = SessionApi(baseUrl: apiBaseUrl, token: token);
        sessionId = await sessionApi.startSession();
      } catch (e) {
        state = state.copyWith(
          status: WebRTCSessionStatus.idle,
          errorMessage: 'Failed to start session: $e',
        );
        return;
      }
    }

    state = state.copyWith(sessionId: sessionId, status: WebRTCSessionStatus.requestingPermissions);

    final permitted = await _ensurePermissions();
    if (!permitted) return;

    state = state.copyWith(status: WebRTCSessionStatus.acquiringMedia);

    try {
      await _service.startLocalMedia(
        videoDeviceId: state.selectedCameraId,
        audioDeviceId: state.selectedMicId,
      );
    } catch (e) {
      state = state.copyWith(
        status: WebRTCSessionStatus.idle,
        errorMessage: 'Unable to access camera/microphone — check system permissions and device availability. ($e)',
      );
      return;
    }

    state = state.copyWith(status: WebRTCSessionStatus.connecting);

    try {
      await _service.startSession(baseWsUrl: baseWsUrl, token: token, roomId: sessionId);
    } catch (e) {
      state = state.copyWith(status: WebRTCSessionStatus.failed, errorMessage: e.toString());
    }
  }

  Future<void> stopAssessment() async {
    await _service.stopSession();
    await _service.stopLocalMedia();
    state = state.copyWith(status: WebRTCSessionStatus.ended);
  }
}

final webRTCProvider = NotifierProvider<WebRTCNotifier, WebRTCState>(WebRTCNotifier.new);