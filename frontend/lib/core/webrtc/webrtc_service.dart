import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signaling_client.dart';

class MediaDeviceOption {
  const MediaDeviceOption({
    required this.deviceId,
    required this.label,
    required this.kind,
  });

  final String deviceId;
  final String label;
  final String kind; // 'videoinput' | 'audioinput'
}

class WebRTCService {
  WebRTCService({required this.signalingClient});

  final SignalingClient signalingClient;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  StreamSubscription<SignalMessage>? _signalSubscription;

  final StreamController<MediaStream?> _localStreamController = StreamController<MediaStream?>.broadcast();
  final StreamController<RTCPeerConnectionState> _connectionStateController =
      StreamController<RTCPeerConnectionState>.broadcast();
  final StreamController<RTCIceConnectionState> _iceConnectionStateController =
      StreamController<RTCIceConnectionState>.broadcast();

  Stream<MediaStream?> get onLocalStream => _localStreamController.stream;
  Stream<RTCPeerConnectionState> get onConnectionStateChange => _connectionStateController.stream;
  Stream<RTCIceConnectionState> get onIceConnectionStateChange => _iceConnectionStateController.stream;

  Future<List<MediaDeviceOption>> getAvailableDevices() async {
    final devices = await navigator.mediaDevices.getSources();
    final options = <MediaDeviceOption>[];
    var videoIndex = 0;
    var audioIndex = 0;

    for (final d in devices) {
      final kind = d.kind ?? '';
      if (kind != 'videoinput' && kind != 'audioinput') continue;

      var label = d.label ?? '';
      if (label.isEmpty) {
        if (kind == 'videoinput') {
          videoIndex++;
          label = 'Camera $videoIndex';
        } else {
          audioIndex++;
          label = 'Microphone $audioIndex';
        }
      }

      options.add(MediaDeviceOption(deviceId: d.deviceId ?? '', label: label, kind: kind));
    }

    return options;
  }

  Future<MediaStream> startLocalMedia({
    bool audio = true,
    bool video = true,
    String? videoDeviceId,
    String? audioDeviceId,
  }) async {
    final constraints = <String, dynamic>{
      'audio': audio
          ? (audioDeviceId != null ? {'deviceId': audioDeviceId} : true)
          : false,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              if (videoDeviceId != null) 'deviceId': videoDeviceId,
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    _localStreamController.add(_localStream);
    return _localStream!;
  }

  Future<void> startSession({
    required String baseWsUrl,
    required String token,
    required String roomId,
  }) async {
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(config);

    final localStream = _localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        await _peerConnection!.addTrack(track, localStream);
      }
    }

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      final candidateValue = candidate.candidate;
      if (candidateValue != null && candidateValue.isNotEmpty) {
        signalingClient.sendIceCandidate(
          candidate: candidateValue,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        );
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      _connectionStateController.add(state);
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      _iceConnectionStateController.add(state);
    };

    await signalingClient.connect(baseUrl: baseWsUrl, token: token, roomId: roomId);
    _signalSubscription = signalingClient.messages.listen(_handleSignalMessage);

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    signalingClient.sendOffer(offer.sdp ?? '');
  }

  Future<void> _handleSignalMessage(SignalMessage message) async {
    final pc = _peerConnection;
    if (pc == null) return;

    switch (message.type) {
      case SignalMessageType.answer:
        if (message.sdp != null) {
          await pc.setRemoteDescription(RTCSessionDescription(message.sdp, 'answer'));
        }
        break;
      case SignalMessageType.iceCandidate:
        final candidate = message.candidate;
        if (candidate != null) {
          await pc.addCandidate(
            RTCIceCandidate(candidate.candidate, candidate.sdpMid, candidate.sdpMLineIndex),
          );
        }
        break;
      case SignalMessageType.offer:
      case SignalMessageType.error:
      case SignalMessageType.unknown:
        break;
    }
  }

  Future<void> stopSession() async {
    await _signalSubscription?.cancel();
    _signalSubscription = null;

    await signalingClient.disconnect();

    await _peerConnection?.close();
    _peerConnection = null;
  }

  Future<void> stopLocalMedia() async {
    final stream = _localStream;
    if (stream == null) return;

    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
    _localStream = null;
    _localStreamController.add(null);
  }

  void toggleAudio(bool enabled) {
    _localStream?.getAudioTracks().forEach((track) => track.enabled = enabled);
  }

  void toggleVideo(bool enabled) {
    _localStream?.getVideoTracks().forEach((track) => track.enabled = enabled);
  }

  Future<void> dispose() async {
    await stopSession();
    await stopLocalMedia();
    await _localStreamController.close();
    await _connectionStateController.close();
    await _iceConnectionStateController.close();
  }
}