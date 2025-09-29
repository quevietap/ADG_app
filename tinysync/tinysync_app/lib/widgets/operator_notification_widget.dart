import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import 'beautiful_live_tracking_map.dart';

class OperatorNotificationWidget extends StatefulWidget {
  const OperatorNotificationWidget({super.key});

  @override
  State<OperatorNotificationWidget> createState() =>
      _OperatorNotificationWidgetState();
}

class _OperatorNotificationWidgetState
    extends State<OperatorNotificationWidget> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _setupNotificationListener();

    // Refresh notifications every 10 seconds for faster updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _loadNotifications();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    NotificationService().removeNotificationListener(_handleNotification);
    super.dispose();
  }

  void _setupNotificationListener() {
    NotificationService().addNotificationListener(_handleNotification);
  }

  void _handleNotification(Map<String, dynamic> tripData) {
    // Refresh notifications when new trip starts
    _loadNotifications();

    // Show in-app notification
    _showInAppNotification(tripData);

    // Force refresh after a short delay to ensure we get the latest data
    Future.delayed(const Duration(seconds: 2), () {
      _loadNotifications();
    });
  }

  void _showInAppNotification(Map<String, dynamic> tripData) {
    final driverName = _getDriverName(tripData);
    final tripRefNumber =
        tripData['trip_ref_number'] ?? 'TRIP-${tripData['id']}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.local_shipping, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Driver $driverName has started their trip',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Trip: $tripRefNumber',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'View Map',
          textColor: Colors.white,
          onPressed: () => _viewDriverMap(tripData),
        ),
      ),
    );
  }

  Future<void> _loadNotifications() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final notifications =
          await NotificationService().getUnreadNotifications();
      setState(() {
        _notifications = notifications;
      });
    } catch (e) {
      print('❌ Error loading notifications: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _viewDriverMap(Map<String, dynamic> tripData) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BeautifulLiveTrackingMap(
          trip: tripData,
          driverId: tripData['driver_id'] ?? '',
          height: 400,
          isOperatorView:
              true, // IMPORTANT: This is operator view, use database subscription
        ),
      ),
    );
  }

  String _getDriverName(Map<String, dynamic> tripData) {
    final users = tripData['users'];
    if (users != null) {
      return '${users['first_name'] ?? ''} ${users['last_name'] ?? ''}'.trim();
    }
    return 'Unknown Driver';
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return 'Unknown time';

    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown time';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notifications.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Recent Trip Notifications',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _loadNotifications,
                child: const Text(
                  'Refresh',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._notifications
              .take(3)
              .map((notification) => _buildNotificationCard(notification)),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final tripId = notification['trip_id'];
    final driverName = notification['driver_name'] ?? 'Unknown Driver';
    final tripRefNumber = notification['trip_ref_number'] ?? 'Unknown Trip';
    final message = notification['message'] ?? '';
    final timestamp = notification['created_at'];
    final notificationId = notification['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_shipping,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trip Started',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatTime(timestamp),
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _viewDriverMap(
                      {'id': tripId, 'driver_id': notification['driver_id']}),
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('View Driver Map'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _markAsRead(notificationId),
                child: const Text(
                  'Mark Read',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await NotificationService().markNotificationAsRead(notificationId);
      _loadNotifications(); // Refresh the list
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }
}
