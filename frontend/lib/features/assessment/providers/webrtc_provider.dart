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
  processing,
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
    bool clearLocalStream = false,
    List<MediaDeviceOption>? videoDevices,
    List<MediaDeviceOption>? audioDevices,
    String? selectedCameraId,
    String? selectedMicId,
  }) {
    return WebRTCState(
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      localStream: clearLocalStream ? null : (localStream ?? this.localStream),
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
      state = state.copyWith(localStream: stream, clearLocalStream: stream == null);
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
    if (state.status == WebRTCSessionStatus.processing || state.status == WebRTCSessionStatus.ended) {
      // Teardown already initiated deliberately via endSession(); ignore
      // late-arriving connection callbacks so we don't clobber that state.
      return;
    }
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
    if (state.status == WebRTCSessionStatus.processing || state.status == WebRTCSessionStatus.ended) {
      return;
    }
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

  /// Cleanly tears down an active assessment session:
  /// 1. Stops local media tracks first, releasing the camera/mic hardware
  ///    immediately (turns off the OS-level camera/mic indicator lights).
  /// 2. Closes the peer connection and signaling socket.
  /// 3. Transitions to `processing`, signaling the UI to move to the screen
  ///    that waits for the backend's AI pipeline notification.
  Future<void> endSession() async {
    await _service.stopLocalMedia();
    await _service.stopSession();
    state = state.copyWith(status: WebRTCSessionStatus.processing, clearError: true, clearLocalStream: true);
  }

  /// Resets to a fresh idle state — used once the processing screen has
  /// handed off to Results/Dashboard, so a future assessment starts clean.
  void reset() {
    state = const WebRTCState();
  }
}

final webRTCProvider = NotifierProvider<WebRTCNotifier, WebRTCState>(WebRTCNotifier.new);