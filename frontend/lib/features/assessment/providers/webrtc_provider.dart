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
    this.videoDevices = const [],
    this.audioDevices = const [],
    this.selectedVideoDeviceId,
    this.selectedAudioDeviceId,
  });

  final WebRTCSessionStatus status;
  final MediaStream? localStream;
  final String? errorMessage;
  final List<MediaDeviceOption> videoDevices;
  final List<MediaDeviceOption> audioDevices;
  final String? selectedVideoDeviceId;
  final String? selectedAudioDeviceId;

  WebRTCState copyWith({
    WebRTCSessionStatus? status,
    MediaStream? localStream,
    String? errorMessage,
    bool clearError = false,
    List<MediaDeviceOption>? videoDevices,
    List<MediaDeviceOption>? audioDevices,
    String? selectedVideoDeviceId,
    String? selectedAudioDeviceId,
  }) {
    return WebRTCState(
      status: status ?? this.status,
      localStream: localStream ?? this.localStream,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      videoDevices: videoDevices ?? this.videoDevices,
      audioDevices: audioDevices ?? this.audioDevices,
      selectedVideoDeviceId: selectedVideoDeviceId ?? this.selectedVideoDeviceId,
      selectedAudioDeviceId: selectedAudioDeviceId ?? this.selectedAudioDeviceId,
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
        selectedVideoDeviceId: state.selectedVideoDeviceId ??
            (videoDevices.isNotEmpty ? videoDevices.first.deviceId : null),
        selectedAudioDeviceId: state.selectedAudioDeviceId ??
            (audioDevices.isNotEmpty ? audioDevices.first.deviceId : null),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load devices: $e');
    }
  }

  void selectVideoDevice(String deviceId) {
    state = state.copyWith(selectedVideoDeviceId: deviceId);
  }

  void selectAudioDevice(String deviceId) {
    state = state.copyWith(selectedAudioDeviceId: deviceId);
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
      await _service.startLocalMedia(
        videoDeviceId: state.selectedVideoDeviceId,
        audioDeviceId: state.selectedAudioDeviceId,
      );
      await _service.startSession(baseWsUrl: baseWsUrl, token: token, roomId: roomId);
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