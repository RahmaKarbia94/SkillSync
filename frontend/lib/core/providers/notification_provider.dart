import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/notification_client.dart';
import '../notifications/notification_models.dart';
import 'auth_provider.dart';

class NotificationState {
  const NotificationState({
    this.isConnected = false,
    this.notifications = const [],
    this.unreadCount = 0,
  });

  final bool isConnected;
  final List<AppNotification> notifications;
  final int unreadCount;

  NotificationState copyWith({
    bool? isConnected,
    List<AppNotification>? notifications,
    int? unreadCount,
  }) {
    return NotificationState(
      isConnected: isConnected ?? this.isConnected,
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class NotificationNotifier extends Notifier<NotificationState> {
  final NotificationClient _client = NotificationClient();
  StreamSubscription<AppNotification>? _sub;
  Timer? _reconnectTimer;

  @override
  NotificationState build() {
    _client.onDisconnected = _handleDisconnected;

    ref.listen<AuthState>(authProvider, (previous, next) {
      final wasAuthed = previous?.isAuthenticated ?? false;
      if (next.isAuthenticated && !wasAuthed && next.token != null) {
        _connect(next.token!);
      } else if (!next.isAuthenticated && wasAuthed) {
        _disconnect();
      }
    });

    final authState = ref.read(authProvider);
    if (authState.isAuthenticated && authState.token != null) {
      Future.microtask(() => _connect(authState.token!));
    }

    ref.onDispose(() {
      _reconnectTimer?.cancel();
      _sub?.cancel();
      _client.dispose();
    });

    return const NotificationState();
  }

  Future<void> _connect(String token) async {
    try {
      await _client.connect(baseUrl: 'ws://localhost:8080', token: token);
      state = state.copyWith(isConnected: true);
      _sub?.cancel();
      _sub = _client.notifications.listen(_handleIncoming);
    } catch (_) {
      state = state.copyWith(isConnected: false);
      _scheduleReconnect();
    }
  }

  void _handleDisconnected() {
    state = state.copyWith(isConnected: false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      final authState = ref.read(authProvider);
      if (authState.isAuthenticated && authState.token != null && !state.isConnected) {
        _connect(authState.token!);
      }
    });
  }

  void _handleIncoming(AppNotification notification) {
    final updated = [notification, ...state.notifications];
    if (updated.length > 20) updated.removeRange(20, updated.length);
    state = state.copyWith(notifications: updated, unreadCount: state.unreadCount + 1);
  }

  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _client.disconnect();
    state = state.copyWith(isConnected: false);
  }

  void markAllRead() {
    state = state.copyWith(unreadCount: 0);
  }
}

final notificationProvider = NotifierProvider<NotificationNotifier, NotificationState>(NotificationNotifier.new);
