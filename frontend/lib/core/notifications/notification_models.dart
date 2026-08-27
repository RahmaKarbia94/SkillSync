enum AppNotificationType { evaluationCompleted, unknown }

class AppNotification {
  const AppNotification({
    required this.type,
    this.sessionId,
    this.message,
    required this.timestamp,
  });

  final AppNotificationType type;
  final String? sessionId;
  final String? message;
  final DateTime timestamp;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      type: _typeFromString(json['type'] as String?),
      sessionId: json['session_id'] as String?,
      message: json['message'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  static AppNotificationType _typeFromString(String? value) {
    switch (value) {
      case 'evaluation_completed':
        return AppNotificationType.evaluationCompleted;
      default:
        return AppNotificationType.unknown;
    }
  }
}
