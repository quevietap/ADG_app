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

      // Immediately update the UI state to reflect the changes
      if (mounted) {
        setState(() {
          // Mark all notifications as read in the current state
          for (var notification in _notifications) {
            notification['is_read'] = true;
          }
          for (var notification in _filteredNotifications) {
            notification['is_read'] = true;
          }
          _hasUnread = false;
          _isLoading = false;
        });
      }

      // Refresh notifications in the background (real-time will also update)
      _loadNotifications();

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

      // Immediately update the UI state to reflect the change
      if (mounted) {
        setState(() {
          // Find and update the notification in both lists
          for (var notification in _notifications) {
            if (notification['id'] == notificationId) {
              notification['is_read'] = true;
              break;
            }
          }
          for (var notification in _filteredNotifications) {
            if (notification['id'] == notificationId) {
              notification['is_read'] = true;
              break;
            }
          }
          // Update the unread status
          _hasUnread = _filteredNotifications.any((n) => !n['is_read']);
        });
      }

      // Refresh list in the background
      _loadNotifications();
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  /// Clean up old notifications from database and local storage
  Future<void> _cleanupOldNotifications() async {
    try {
      print('🧹 Cleaning up old notifications...');
      
      // First, clear the local notification tracking service
      await _notificationTracker.clearNotificationHistory();
      print('🧹 Cleared local notification tracking history');
      
      // Get all notifications for this driver
      final allNotifications = await Supabase.instance.client
          .from('driver_notifications')
          .select('*')
          .eq('driver_id', widget.driverId)
          .order('created_at', ascending: false);
      
      print('📊 Found ${allNotifications.length} total notifications');
      
      // Clean up old notifications - more aggressive cleanup
      final now = DateTime.now();
      final cutoffTime = now.subtract(const Duration(hours: 1)); // 1 hour ago for unread
      
      final notificationsToDelete = <String>[];
      
      for (final notification in allNotifications) {
        final createdAt = DateTime.parse(notification['created_at']);
        final isRead = notification['is_read'] ?? false;
        final notificationId = notification['id'];
        
        bool shouldDelete = false;
        
        if (isRead) {
          // Delete ALL read notifications (more aggressive cleanup)
          shouldDelete = true;
        } else {
          // Delete unread notifications older than 1 hour
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
      
      // Immediately update the UI state to reflect the cleanup
      if (mounted) {
        setState(() {
          // Clear all notifications from the current state since they were deleted
          _notifications.clear();
          _filteredNotifications.clear();
          _hasUnread = false;
        });
      }

      // Refresh notifications in the background to get any remaining notifications
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.withOpacity(0.1),
                    Colors.blue.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_active,
                          color: Colors.blue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Notifications',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (_notifications.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${_notifications.where((n) => !n['is_read']).length} unread • ${_notifications.length} total',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_notifications.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        // Cleanup button
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await _cleanupOldNotifications();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.orange.withOpacity(0.2),
                                    Colors.orange.withOpacity(0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cleaning_services,
                                    size: 18,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Cleanup Old',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Mark all as read button
                        if (_hasUnread)
                          Expanded(
                            child: GestureDetector(
                              onTap: _isLoading ? null : _markAllAsRead,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue.withOpacity(0.2),
                                      Colors.blue.withOpacity(0.1),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isLoading)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.done_all,
                                        size: 18,
                                        color: Colors.blue,
                                      ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isLoading ? 'Processing...' : 'Mark All Read',
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
    Color bgColor = const Color(0xFF2C3E50);
    IconData priorityIcon = Icons.info_outline;
    String priorityText = 'INFO';

    if (priority == 'high') {
      priorityColor = Colors.red;
      bgColor = const Color(0xFF2C1818);
      priorityIcon = Icons.warning_amber_rounded;
      priorityText = 'URGENT';
    } else if (priority == 'medium') {
      priorityColor = Colors.orange;
      bgColor = const Color(0xFF2C2318);
      priorityIcon = Icons.schedule_rounded;
      priorityText = 'REMINDER';
    }

    // Adjust opacity for read notifications
    if (isRead) {
      priorityColor = priorityColor.withOpacity(0.5);
      bgColor = const Color(0xFF1A1A1A);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRead 
            ? Colors.grey.withOpacity(0.1)
            : priorityColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          if (!isRead)
            BoxShadow(
              color: priorityColor.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: isRead ? null : () => _markAsRead(notification['id']),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon, title, and priority badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: priorityColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        priorityIcon,
                        color: priorityColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                                    color: isRead ? Colors.grey[500] : Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (priority == 'high' && !isRead) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    priorityText,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (createdAt != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 13,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTime(createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Message content
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.05),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      color: isRead ? Colors.grey[600] : Colors.grey[300],
                      height: 1.5,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Footer with action
                Row(
                  children: [
                    if (!isRead) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 14,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Tap to dismiss',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Read',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Priority indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        priorityText,
                        style: TextStyle(
                          fontSize: 10,
                          color: priorityColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
