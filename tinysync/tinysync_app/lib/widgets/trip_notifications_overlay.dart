import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripNotificationsOverlay extends StatefulWidget {
  final ScrollController? scrollController;

  const TripNotificationsOverlay({super.key, this.scrollController});

  @override
  State<TripNotificationsOverlay> createState() =>
      _TripNotificationsOverlayState();
}

class _TripNotificationsOverlayState extends State<TripNotificationsOverlay> {
  Future<List<Map<String, dynamic>>> _getUnreadNotifications() async {
    try {
      final response = await Supabase.instance.client
          .from('operator_notifications')
          .select('*')
          .eq('is_read', false)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (e.toString().contains(
          'relation "public.operator_notifications" does not exist')) {
        print(
            '⚠️ operator_notifications table does not exist - returning empty list');
        return [];
      } else {
        print('❌ Error fetching notifications: $e');
        return [];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildNotificationsContent();
  }

  Widget _buildNotificationsContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getUnreadNotifications(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF2196F3),
            ),
          );
        }

        final notifications = snapshot.data ?? [];

        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            // Mark all read button
            if (notifications.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${notifications.length} unread notifications',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _markAllAsRead(notifications),
                      child: const Text(
                        'Mark All Read',
                        style: TextStyle(
                          color: Color(0xFF2196F3),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Notifications list
            if (notifications.isEmpty)
              _buildEmptyState()
            else
              ...notifications.asMap().entries.map((entry) {
                final index = entry.key;
                final notification = entry.value;
                final isLast = index == notifications.length - 1;
                return _buildNotificationCard(notification, isLast);
              }),

            // Bottom padding
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none,
              size: 40,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No new notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Trip notifications will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
      Map<String, dynamic> notification, bool isLast) {
    final notificationType = notification['notification_type'] ?? '';
    final title = notification['title'] ?? 'Notification';
    final message = notification['message'] ?? '';
    final isRead = notification['is_read'] ?? false;
    final createdAt = notification['created_at'] != null
        ? DateTime.tryParse(notification['created_at'])
        : null;

    Color cardColor;
    IconData icon;
    Color iconColor;

    switch (notificationType) {
      case 'trip_started':
        cardColor = Colors.green.withValues(alpha: 0.15);
        iconColor = Colors.green;
        icon = Icons.local_shipping;
        break;
      case 'trip_completed':
        cardColor = Colors.orange.withValues(alpha: 0.15);
        iconColor = Colors.orange;
        icon = Icons.check_circle;
        break;
      case 'trip_cancelled':
        cardColor = Colors.red.withValues(alpha: 0.15);
        iconColor = Colors.red;
        icon = Icons.cancel;
        break;
      default:
        cardColor = const Color(0xFF2196F3).withValues(alpha: 0.15);
        iconColor = const Color(0xFF2196F3);
        icon = Icons.notifications;
    }

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 16 : 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () => _markNotificationAsRead(notification),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    if (createdAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatDateTime(createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    if (message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          message,
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 12,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isRead)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: iconColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Future<void> _markAllAsRead(List<Map<String, dynamic>> notifications) async {
    try {
      await Supabase.instance.client
          .from('operator_notifications')
          .update({'is_read': true}).eq('is_read', false);
      // Refresh the widget and close overlay
      if (mounted) {
        setState(() {});
        // Close after a brief delay to show the update
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  Future<void> _markNotificationAsRead(
      Map<String, dynamic> notification) async {
    try {
      await Supabase.instance.client
          .from('operator_notifications')
          .update({'is_read': true}).eq('id', notification['id']);
      // Refresh the widget to show the update
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }
}
