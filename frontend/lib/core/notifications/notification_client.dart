import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'notification_models.dart';

class NotificationClient {
  WebSocket? _socket;
  final StreamController<AppNotification> _controller = StreamController<AppNotification>.broadcast();

  void Function()? onDisconnected;

  Stream<AppNotification> get notifications => _controller.stream;
  bool get isConnected => _socket != null;

  Future<void> connect({required String baseUrl, required String token}) async {
    final uri = Uri.parse('$baseUrl/ws/notifications?token=$token');
    _socket = await WebSocket.connect(uri.toString());

    _socket!.listen(
      _handleRaw,
      onDone: () {
        _socket = null;
        onDisconnected?.call();
      },
      onError: (Object _) {
        _socket = null;
        onDisconnected?.call();
      },
      cancelOnError: true,
    );
  }

  void _handleRaw(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _controller.add(AppNotification.fromJson(decoded));
    } catch (_) {}
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }

  void dispose() {
    _socket?.close();
    _controller.close();
  }
}
