import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/notification_provider.dart';
import '../../../../core/theme/glass_theme.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationProvider);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white70),
          onPressed: () => _showPanel(context, ref),
        ),
        if (state.unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(999)),
              child: Text(
                state.unreadCount > 9 ? '9+' : '${state.unreadCount}',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  void _showPanel(BuildContext context, WidgetRef ref) {
    ref.read(notificationProvider.notifier).markAllRead();
    final notifications = ref.read(notificationProvider).notifications;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (notifications.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No notifications yet.', style: TextStyle(color: Colors.white60)),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 16),
                      itemBuilder: (context, index) {
                        final n = notifications[index];
                        return InkWell(
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            if (n.sessionId != null) {
                              context.push('/results/${n.sessionId}');
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    n.message ?? 'Evaluation completed',
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
