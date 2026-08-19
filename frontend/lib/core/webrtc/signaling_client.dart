import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum SignalMessageType { offer, answer, iceCandidate, error, unknown }

class SignalIceCandidate {
  const SignalIceCandidate({required this.candidate, this.sdpMid, this.sdpMLineIndex});

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  factory SignalIceCandidate.fromJson(Map<String, dynamic> json) {
    return SignalIceCandidate(
      candidate: json['candidate'] as String? ?? '',
      sdpMid: json['sdpMid'] as String?,
      sdpMLineIndex: json['sdpMLineIndex'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
      };
}

class SignalMessage {
  const SignalMessage({
    required this.type,
    this.roomId,
    this.senderId,
    this.sdp,
    this.candidate,
  });

  final SignalMessageType type;
  final String? roomId;
  final String? senderId;
  final String? sdp;
  final SignalIceCandidate? candidate;

  factory SignalMessage.fromJson(Map<String, dynamic> json) {
    return SignalMessage(
      type: _typeFromString(json['type'] as String?),
      roomId: json['room_id'] as String?,
      senderId: json['sender_id'] as String?,
      sdp: json['sdp'] as String?,
      candidate: json['candidate'] != null
          ? SignalIceCandidate.fromJson(json['candidate'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': _typeToString(type),
        if (sdp != null) 'sdp': sdp,
        if (candidate != null) 'candidate': candidate!.toJson(),
      };

  static SignalMessageType _typeFromString(String? value) {
    switch (value) {
      case 'offer':
        return SignalMessageType.offer;
      case 'answer':
        return SignalMessageType.answer;
      case 'ice-candidate':
        return SignalMessageType.iceCandidate;
      case 'error':
        return SignalMessageType.error;
      default:
        return SignalMessageType.unknown;
    }
  }

  static String _typeToString(SignalMessageType type) {
    switch (type) {
      case SignalMessageType.offer:
        return 'offer';
      case SignalMessageType.answer:
        return 'answer';
      case SignalMessageType.iceCandidate:
        return 'ice-candidate';
      case SignalMessageType.error:
        return 'error';
      case SignalMessageType.unknown:
        return 'unknown';
    }
  }
}

class SignalingException implements Exception {
  const SignalingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Matches a real MongoDB ObjectID (24-character hex string) — guards
/// against ever again connecting with a static placeholder like the old
/// hardcoded "assessment-room" value instead of a real, dynamic session id.
final RegExp _objectIdPattern = RegExp(r'^[a-fA-F0-9]{24}$');

class SignalingClient {
  WebSocket? _socket;
  final StreamController<SignalMessage> _messageController = StreamController<SignalMessage>.broadcast();

  Stream<SignalMessage> get messages => _messageController.stream;
  bool get isConnected => _socket != null;

  /// [roomId] must be a real, dynamic session id (a MongoDB ObjectID hex
  /// string) obtained from `POST /api/v1/sessions/start` — never a static
  /// placeholder.
  Future<void> connect({
    required String baseUrl,
    required String token,
    required String roomId,
  }) async {
    if (!_objectIdPattern.hasMatch(roomId)) {
      throw SignalingException(
        'Invalid session id "$roomId" — expected a real session id from '
        'the backend, not a placeholder value.',
      );
    }

    final uri = Uri.parse('$baseUrl/ws/signaling?token=$token&room_id=$roomId');
    _socket = await WebSocket.connect(uri.toString());

    _socket!.listen(
      _handleRawMessage,
      onDone: () {
        _socket = null;
      },
      onError: (Object error) {
        _socket = null;
      },
      cancelOnError: true,
    );
  }

  void _handleRawMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _messageController.add(SignalMessage.fromJson(decoded));
    } catch (_) {
      // ignore malformed frames
    }
  }

  void sendOffer(String sdp) {
    _send(SignalMessage(type: SignalMessageType.offer, sdp: sdp));
  }

  void sendAnswer(String sdp) {
    _send(SignalMessage(type: SignalMessageType.answer, sdp: sdp));
  }

  void sendIceCandidate({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) {
    _send(
      SignalMessage(
        type: SignalMessageType.iceCandidate,
        candidate: SignalIceCandidate(
          candidate: candidate,
          sdpMid: sdpMid,
          sdpMLineIndex: sdpMLineIndex,
        ),
      ),
    );
  }

  void _send(SignalMessage message) {
    _socket?.add(jsonEncode(message.toJson()));
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }

  void dispose() {
    _socket?.close();
    _messageController.close();
  }
}