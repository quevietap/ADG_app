import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_tracking_service.dart';

/// Widget that shows in-app notifications to drivers
/// Displays reminders from operators and overdue trip alerts
class DriverNotificationAlert extends StatefulWidget {
  final String driverId;
  const DriverNotificationAlert({super.key, required this.driverId});

  @override
  State<DriverNotificationAlert> createState() =>
      _DriverNotificationAlertState();
}

class _DriverNotificationAlertState extends State<DriverNotificationAlert> {
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _filteredNotifications = [];
  bool _hasUnread = false;
  bool _isLoading = false;
  Timer? _refreshTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSubscription;
  final NotificationTrackingService _notificationTracker = NotificationTrackingService();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _setupRealTimeListener();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _notificationSubscription?.cancel();
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  void _setupRealTimeListener() {
    print(
        '🔔 Setting up real-time notification listener for driver: ${widget.driverId}');

    try {
      // Subscribe to real-time changes for driver notifications
      _realtimeSubscription = Supabase.instance.client
          .from('driver_notifications')
          .stream(primaryKey: ['id'])
          .eq('driver_id', widget.driverId)
          .listen((List<Map<String, dynamic>> data) {
            print(
                '🔔 Real-time notification update received for driver ${widget.driverId}: ${data.length} notifications');

            // Debug: Print each notification's driver_id to verify filtering
            for (var notification in data) {
              print(
                  '  - Notification for driver: ${notification['driver_id']}, title: ${notification['title']}');
            }

            if (mounted) {
              setState(() {
                _notifications = data
                  ..sort((a, b) => DateTime.parse(b['created_at'])
                      .compareTo(DateTime.parse(a['created_at'])));
                _hasUnread = _notifications.any((n) => !n['is_read']);
              });
            }
          });
    } catch (e) {
      print('❌ Error setting up real-time listener: $e');
      // Fallback to periodic refresh if real-time fails
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        _loadNotifications();
      });
    }
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Load all recent notifications (both read and unread) for the modal
      final allResponse = await Supabase.instance.client
          .from('driver_notifications')
          .select('*')
          .eq('driver_id', widget.driverId)
          .order('created_at', ascending: false)
          .limit(50); // Load more to filter

      print(
          '🔔 Loaded ${allResponse.length} notifications for driver ${widget.driverId}');

      if (mounted) {
        final allNotifications = List<Map<String, dynamic>>.from(allResponse);
        
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
          _hasUnread = _filteredNotifications.any((n) => !n['is_read']);
          _isLoading = false;
        });
        
        // Perform maintenance cleanup periodically
        await _notificationTracker.performMaintenanceCleanup();
      }
    } catch (e) {
      print('❌ Error loading driver notifications: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAllAsRead() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoading = true;
      });

      // Mark all unread notifications as read
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

      // Refresh notifications (real-time will also update)
      await _loadNotifications();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error marking all notifications as read: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to mark notifications as read'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

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

  void _showNotificationDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.notifications, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'Your Notifications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  // Cleanup button
                  GestureDetector(
                    onTap: () async {
                      await _cleanupOldNotifications();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cleaning_services,
                            size: 14,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Cleanup',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_notifications.isNotEmpty) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${_notifications.where((n) => !n['is_read']).length} unread of ${_notifications.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_hasUnread) ...[
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _isLoading ? null : _markAllAsRead,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.blue),
                                    ),
                                  )
                                : const Text(
                                    'Mark all as read',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue,
                                    ),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),

            Divider(height: 1),

            // Notifications list
            Expanded(
              child: _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No new notifications',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      itemBuilder: (context, index) {
                        final notification = _notifications[index];
                        return _buildNotificationCard(notification);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final title = notification['title'] ?? 'Notification';
    final message = notification['message'] ?? '';
    final priority = notification['priority'] ?? 'normal';
    final createdAt = DateTime.tryParse(notification['created_at'] ?? '');
    final isRead = notification['is_read'] ?? false;

    Color priorityColor = Colors.blue;
    IconData priorityIcon = Icons.info;

    if (priority == 'high') {
      priorityColor = Colors.red;
      priorityIcon = Icons.warning;
    } else if (priority == 'medium') {
      priorityColor = Colors.orange;
      priorityIcon = Icons.schedule;
    }

    // Adjust opacity for read notifications
    if (isRead) {
      priorityColor = priorityColor.withOpacity(0.6);
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      color: isRead ? Colors.grey[50] : null,
      child: InkWell(
        onTap: isRead ? null : () => _markAsRead(notification['id']),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(priorityIcon, color: priorityColor, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                        color: priorityColor,
                      ),
                    ),
                  ),
                  if (priority == 'high' && !isRead)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red, width: 1),
                      ),
                      child: Text(
                        'URGENT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: isRead ? Colors.grey[500] : Colors.grey[700],
                ),
              ),
              if (createdAt != null) ...[
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    SizedBox(width: 4),
                    Text(
                      _formatTime(createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    Spacer(),
                    if (isRead)
                      Text(
                        'Read',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[400],
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      Text(
                        'Tap to dismiss',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
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
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showNotificationDetails,
      child: Container(
        // Remove margin since padding is now handled in main.dart
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Notification icon - black background to blend with dashboard
            Container(
              width:
                  42, // Match closer to settings button size (settings has padding 10, so total ~42)
              height: 42, // Match closer to settings button size
              decoration: BoxDecoration(
                color: Colors
                    .black, // Always black background to blend with dashboard
                borderRadius: BorderRadius.circular(8),
                // Removed border completely
              ),
              child: Icon(
                _hasUnread
                    ? Icons.notifications_active
                    : Icons.notifications_outlined,
                color: _hasUnread
                    ? Colors.red
                    : Colors
                        .white70, // White icon when no notifications, red when unread
                size: 22, // Match settings button icon size
              ),
            ),

            // Badge with count (only show unread count) - smaller
            if (_hasUnread)
              Positioned(
                top: -2, // Adjusted position
                right: -2, // Adjusted position
                child: Container(
                  padding: const EdgeInsets.all(3), // Reduced padding
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8), // Smaller radius
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16, // Reduced from 20 to 16
                    minHeight: 16, // Reduced from 20 to 16
                  ),
                  child: Text(
                    '${_notifications.where((n) => !n['is_read']).length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10, // Reduced from 12 to 10
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
