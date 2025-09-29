import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_tracking_service.dart';

/// Widget to display driver notifications in the app
class DriverNotificationWidget extends StatefulWidget {
  final String driverId;

  const DriverNotificationWidget({
    Key? key,
    required this.driverId,
  }) : super(key: key);

  @override
  State<DriverNotificationWidget> createState() =>
      _DriverNotificationWidgetState();
}

class _DriverNotificationWidgetState extends State<DriverNotificationWidget> {
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _filteredNotifications = [];
  bool _isLoading = true;
  int _unreadCount = 0;
  final NotificationTrackingService _notificationTracker = NotificationTrackingService();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _setupRealtimeSubscription();
  }

  /// Load driver notifications
  Future<void> _loadNotifications() async {
    try {
      final response = await Supabase.instance.client
          .from('driver_notifications')
          .select('*')
          .eq('driver_id', widget.driverId)
          .order('created_at', ascending: false)
          .limit(50); // Load more to filter

      if (mounted) {
        final allNotifications = List<Map<String, dynamic>>.from(response);
        
        // Filter out old notifications
        final filteredNotifications = <Map<String, dynamic>>[];
        
        for (final notification in allNotifications) {
          final createdAt = DateTime.parse(notification['created_at']);
          final isRead = notification['is_read'] ?? false;
          final notificationId = notification['id']?.toString() ?? '';
          
          // Check if notification should be hidden
          final shouldHide = await _notificationTracker.shouldHideNotification(
            notificationId, 
            isRead, 
            createdAt
          );
          
          if (!shouldHide) {
            filteredNotifications.add(notification);
          }
        }
        
        setState(() {
          _notifications = allNotifications;
          _filteredNotifications = filteredNotifications;
          _unreadCount = _filteredNotifications.where((n) => !n['is_read']).length;
          _isLoading = false;
        });
        
        // Perform maintenance cleanup periodically
        await _notificationTracker.performMaintenanceCleanup();
      }
    } catch (e) {
      print('❌ Error loading notifications: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Set up real-time subscription for new notifications
  void _setupRealtimeSubscription() {
    Supabase.instance.client
        .channel('driver_notifications_${widget.driverId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'driver_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: widget.driverId,
          ),
          callback: (payload) {
            print('🔔 New notification received');
            _loadNotifications(); // Reload notifications
          },
        )
        .subscribe();
  }

  /// Mark notification as read
  Future<void> _markAsRead(String notificationId) async {
    try {
      await Supabase.instance.client
          .from('driver_notifications')
          .update({'is_read': true}).eq('id', notificationId);

      // Mark in tracking service as well
      await _notificationTracker.markNotificationAsShown(notificationId);

      _loadNotifications(); // Refresh list
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  /// Mark all notifications as read
  Future<void> _markAllAsRead() async {
    try {
      await Supabase.instance.client
          .from('driver_notifications')
          .update({'is_read': true})
          .eq('driver_id', widget.driverId)
          .eq('is_read', false);

      // Mark all filtered notifications as shown in tracking service
      for (final notification in _filteredNotifications) {
        final notificationId = notification['id']?.toString() ?? '';
        if (notificationId.isNotEmpty) {
          await _notificationTracker.markNotificationAsShown(notificationId);
        }
      }

      _loadNotifications(); // Refresh list
    } catch (e) {
      print('❌ Error marking all notifications as read: $e');
    }
  }

  /// Clean up old notifications from database
  Future<void> _cleanupOldNotifications() async {
    try {
      print('🧹 Cleaning up old notifications...');
      
      // Get all notifications for this driver
      final allNotifications = await Supabase.instance.client
          .from('driver_notifications')
          .select('*')
          .eq('driver_id', widget.driverId)
          .order('created_at', ascending: false);
      
      print('📊 Found ${allNotifications.length} total notifications');
      
      // Clean up old notifications
      final now = DateTime.now();
      final cutoffTime = now.subtract(const Duration(hours: 24)); // 24 hours ago
      final readCutoffTime = now.subtract(const Duration(hours: 2)); // 2 hours ago for read notifications
      
      final notificationsToDelete = <String>[];
      
      for (final notification in allNotifications) {
        final createdAt = DateTime.parse(notification['created_at']);
        final isRead = notification['is_read'] ?? false;
        final notificationId = notification['id'];
        
        bool shouldDelete = false;
        
        if (isRead) {
          // Delete read notifications older than 2 hours
          if (createdAt.isBefore(readCutoffTime)) {
            shouldDelete = true;
          }
        } else {
          // Delete unread notifications older than 24 hours
          if (createdAt.isBefore(cutoffTime)) {
            shouldDelete = true;
          }
        }
        
        if (shouldDelete) {
          notificationsToDelete.add(notificationId);
        }
      }
      
      print('🗑️  Found ${notificationsToDelete.length} old notifications to delete');
      
      if (notificationsToDelete.isNotEmpty) {
        // Delete old notifications in batches
        const batchSize = 50;
        int deletedCount = 0;
        
        for (int i = 0; i < notificationsToDelete.length; i += batchSize) {
          final batch = notificationsToDelete.skip(i).take(batchSize).toList();
          
          await Supabase.instance.client
              .from('driver_notifications')
              .delete()
              .inFilter('id', batch);
          
          deletedCount += batch.length;
          print('✅ Deleted batch ${(i ~/ batchSize) + 1}: ${batch.length} notifications');
        }
        
        print('🎉 Cleanup completed! Deleted $deletedCount old notifications');
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cleaned up $deletedCount old notifications'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        print('✅ No old notifications found to delete');
        
        // Show info message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No old notifications to clean up'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      
      // Refresh notifications after cleanup
      _loadNotifications();
      
    } catch (e) {
      print('❌ Error cleaning up old notifications: $e');
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cleaning up notifications: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Get notification icon based on type
  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'trip_assigned':
        return Icons.assignment;
      case 'trip_start_reminder':
        return Icons.schedule;
      case 'trip_overdue':
        return Icons.warning;
      case 'trip_cancelled':
        return Icons.cancel;
      default:
        return Icons.notifications;
    }
  }

  /// Get notification color based on priority
  Color _getNotificationColor(String priority, bool isRead) {
    if (isRead) return Colors.grey;

    switch (priority) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'normal':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  /// Format notification time
  String _formatTime(String createdAt) {
    try {
      final dateTime = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        color: Colors.grey[800],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.notifications,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Notifications',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_unreadCount > 0)
                    TextButton(
                      onPressed: _markAllAsRead,
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_notifications.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: const Text(
                    'No notifications yet',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      final isRead = notification['is_read'] ?? false;
                      final priority = notification['priority'] ?? 'normal';
                      final type = notification['notification_type'] ?? '';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isRead ? Colors.grey[700] : Colors.grey[600],
                        child: ListTile(
                          leading: Icon(
                            _getNotificationIcon(type),
                            color: _getNotificationColor(priority, isRead),
                          ),
                          title: Text(
                            notification['title'] ?? 'Notification',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight:
                                  isRead ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                notification['message'] ?? '',
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTime(notification['created_at']),
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          trailing: !isRead
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.mark_email_read,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _markAsRead(notification['id']),
                                )
                              : null,
                          onTap: !isRead
                              ? () => _markAsRead(notification['id'])
                              : null,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
