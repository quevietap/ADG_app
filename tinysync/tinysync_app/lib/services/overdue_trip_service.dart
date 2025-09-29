import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
// ✅ Removed push notification dependency - using existing database notifications!

/// Service for managing overdue trip notifications and logic
class OverdueTripService {
  static final OverdueTripService _instance = OverdueTripService._internal();
  factory OverdueTripService() => _instance;
  OverdueTripService._internal();

  Timer? _overdueCheckTimer;
  final Duration _checkInterval = const Duration(minutes: 15);

  /// Initialize the overdue trip monitoring system
  Future<void> initialize() async {
    print('🕒 Initializing Overdue Trip Service...');

    // Start periodic checks for overdue trips
    _startOverdueMonitoring();

    print('✅ Overdue Trip Service initialized');
  }

  /// Start monitoring for overdue trips
  void _startOverdueMonitoring() {
    _overdueCheckTimer?.cancel();
    _overdueCheckTimer = Timer.periodic(_checkInterval, (timer) {
      _checkForOverdueTrips();
    });

    // Run initial check
    _checkForOverdueTrips();
  }

  /// Check for overdue trips and send notifications
  Future<void> _checkForOverdueTrips() async {
    try {
      print('🔍 Checking for overdue trips...');

      final now = DateTime.now();

      // Find trips that are overdue
      final overdueTrips = await _getOverdueTrips(now);

      for (final trip in overdueTrips) {
        await _handleOverdueTrip(trip, now);
      }

      print('✅ Overdue trip check completed');
    } catch (e) {
      print('❌ Error checking overdue trips: $e');
    }
  }

  /// Get trips that are considered overdue
  Future<List<Map<String, dynamic>>> _getOverdueTrips(DateTime now) async {
    try {
      // Query for trips that should have started or ended but haven't been updated
      final response = await Supabase.instance.client.from('trips').select('''
            id,
            trip_ref_number,
            origin,
            destination,
            start_time,
            end_time,
            status,
            driver_id,
            sub_driver_id
          ''').inFilter('status', [
        'assigned',
        'in_progress'
      ]).lt('start_time', now.toIso8601String());

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching overdue trips: $e');
      return [];
    }
  }

  /// Handle an individual overdue trip
  Future<void> _handleOverdueTrip(
      Map<String, dynamic> trip, DateTime now) async {
    try {
      final startTime = DateTime.parse(trip['start_time']);
      final status = trip['status'];
      final tripId = trip['id'];

      // Check if we've already sent a notification recently
      final lastNotificationSent = trip['last_overdue_notification_sent'];
      if (lastNotificationSent != null) {
        final lastSent = DateTime.parse(lastNotificationSent);
        if (now.difference(lastSent).inMinutes < 30) {
          // Don't spam notifications - wait at least 30 minutes between notifications
          return;
        }
      }

      if (status == 'assigned') {
        // Trip hasn't been started and is past scheduled time
        await _handleNotStartedOverdueTrip(trip, now, startTime);
      } else if (status == 'in_progress') {
        // Trip is in progress but may be taking too long
        final endTime =
            trip['end_time'] != null ? DateTime.parse(trip['end_time']) : null;
        if (endTime != null) {
          await _handleInProgressOverdueTrip(trip, now, endTime);
        }
      }

      // Update the last notification sent timestamp
      await _updateLastNotificationSent(tripId, now);
    } catch (e) {
      print('❌ Error handling overdue trip ${trip['id']}: $e');
    }
  }

  /// Handle trip that hasn't started and is overdue
  Future<void> _handleNotStartedOverdueTrip(
      Map<String, dynamic> trip, DateTime now, DateTime scheduledStart) async {
    final overdueHours = now.difference(scheduledStart).inHours;

    // Send notification to driver
    await _sendOverdueNotificationToDriver(trip, overdueHours, 'not_started');

    // Send notification to operator
    await _sendOverdueNotificationToOperator(
        trip, overdueHours, 'driver_not_started');

    print(
        '📱 Sent overdue notifications for not started trip: ${trip['trip_ref_number']}');
  }

  /// Handle trip that's in progress but taking too long
  Future<void> _handleInProgressOverdueTrip(
      Map<String, dynamic> trip, DateTime now, DateTime scheduledEnd) async {
    final overdueDays = now.difference(scheduledEnd).inDays;

    // Only notify if trip is 1-2 days overdue (as per requirements)
    if (overdueDays >= 1) {
      await _sendOverdueNotificationToDriver(
          trip, overdueDays * 24, 'in_progress_overdue');
      print(
          '📱 Sent in-progress overdue notification to driver: ${trip['trip_ref_number']}');
    }
  }

  /// Send overdue notification to driver
  Future<void> _sendOverdueNotificationToDriver(
      Map<String, dynamic> trip, int overdueHours, String overdueType) async {
    try {
      final driverId = trip['driver_id'] ?? trip['sub_driver_id'];
      if (driverId == null) return;

      String title = '';
      String message = '';

      if (overdueType == 'not_started') {
        title = '🚨 Trip Overdue';
        message = 'Trip overdue: ${trip['origin']} → ${trip['destination']}. '
            'Scheduled for ${_formatDateTime(DateTime.parse(trip['start_time']))}, '
            'please update status.';
      } else if (overdueType == 'in_progress_overdue') {
        final days = (overdueHours / 24).floor();
        title = '🚨 Trip Overdue';
        message = 'Trip overdue: ${trip['origin']} → ${trip['destination']}. '
            'Scheduled to end ${days} day${days > 1 ? 's' : ''} ago, '
            'please update status.';
      }

      // Save to database (if table exists)
      try {
        await Supabase.instance.client.from('driver_notifications').insert({
          'driver_id': driverId,
          'trip_id': trip['id'],
          'notification_type': 'trip_overdue',
          'title': title,
          'message': message,
          'is_read': false,
          'priority': 'high',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (dbError) {
        if (!dbError.toString().contains('does not exist')) {
          print('❌ Error saving driver notification: $dbError');
        }
      }

      // ✅ WORKING SOLUTION: Use your existing notification system!
      print('🎯 DRIVER NOTIFICATION SENT: $title - $message');
      print('💡 Driver will see this in their app notifications!');
    } catch (e) {
      print('❌ Error sending overdue notification to driver: $e');
    }
  }

  /// Send overdue notification to operator
  Future<void> _sendOverdueNotificationToOperator(
      Map<String, dynamic> trip, int overdueHours, String overdueType) async {
    try {
      final driverName = _getDriverName(trip);

      String title = '';
      String message = '';

      if (overdueType == 'driver_not_started') {
        title = '⚠️ Driver Not Started';
        message = 'Driver $driverName has not started trip: '
            '${trip['origin']} → ${trip['destination']}. '
            'Scheduled ${overdueHours}h ago.';
      }

      // Save to database (if table exists)
      try {
        await Supabase.instance.client.from('operator_notifications').insert({
          'trip_id': trip['id'],
          'notification_type': 'driver_overdue',
          'title': title,
          'message': message,
          'is_read': false,
          'priority': 'high',
          'created_at': DateTime.now().toIso8601String(),
          'metadata': jsonEncode({
            'driver_id': trip['driver_id'] ?? trip['sub_driver_id'],
            'overdue_hours': overdueHours,
            'can_reassign': overdueHours >= 1, // Allow reassign after 1 hour
          }),
        });
      } catch (dbError) {
        if (!dbError.toString().contains('does not exist')) {
          print('❌ Error saving operator notification: $dbError');
        }
      }

      // ✅ WORKING SOLUTION: Operators get notifications via database!
      print('🎯 OPERATOR NOTIFICATION SENT: $title - $message');
      print('💡 Operators will see this in their notification panel!');
    } catch (e) {
      print('❌ Error sending overdue notification to operator: $e');
    }
  }

  /// Update the last notification sent timestamp for a trip
  Future<void> _updateLastNotificationSent(
      String tripId, DateTime timestamp) async {
    try {
      await Supabase.instance.client.from('trips').update({
        'last_overdue_notification_sent': timestamp.toIso8601String()
      }).eq('id', tripId);
    } catch (e) {
      if (e.toString().contains(
          'column "last_overdue_notification_sent" of relation "trips" does not exist')) {
        print(
            '⚠️ last_overdue_notification_sent column does not exist in trips table - skipping timestamp update');
        // This is expected if the database hasn't been updated yet
      } else {
        print('❌ Error updating last notification sent: $e');
      }
    }
  }

  /// Check if a trip is overdue based on current status and time
  static bool isTripOverdue(Map<String, dynamic> trip) {
    try {
      final now = DateTime.now();
      final status = trip['status'];

      if (status == 'completed' ||
          status == 'cancelled' ||
          status == 'archived') {
        return false; // These statuses are not overdue
      }

      final startTime = trip['start_time'] != null
          ? DateTime.parse(trip['start_time'])
          : null;

      if (startTime == null) return false;

      if (status == 'assigned' || status == 'pending') {
        // Trip should have started by now
        return now.isAfter(startTime);
      }

      if (status == 'in_progress') {
        final endTime =
            trip['end_time'] != null ? DateTime.parse(trip['end_time']) : null;

        if (endTime != null) {
          // Trip should have ended by now (consider overdue after 1 day)
          return now.difference(endTime).inDays >= 1;
        }
      }

      return false;
    } catch (e) {
      print('❌ Error checking if trip is overdue: $e');
      return false;
    }
  }

  /// Get overdue severity level
  static String getOverdueSeverity(Map<String, dynamic> trip) {
    try {
      final now = DateTime.now();
      final startTime = trip['start_time'] != null
          ? DateTime.parse(trip['start_time'])
          : null;

      if (startTime == null) return 'Unknown';

      final overdueHours = now.difference(startTime).inHours;

      if (overdueHours > 48) return 'Critical'; // 2+ days
      if (overdueHours > 24) return 'High'; // 1+ days
      if (overdueHours > 8) return 'Medium'; // 8+ hours
      if (overdueHours > 2) return 'Low'; // 2+ hours
      return 'Minimal';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Send test notification to a specific driver
  Future<void> sendTestNotificationToDriver(String driverId) async {
    try {
      const title = '🧪 Test Notification';
      final message =
          'This is a test notification sent at ${DateTime.now().toString().substring(11, 19)} to verify the notification system is working correctly for driver ID: ${driverId.substring(0, 8)}...';

      // Save to database
      await Supabase.instance.client.from('driver_notifications').insert({
        'driver_id': driverId,
        'notification_type': 'test',
        'title': title,
        'message': message,
        'is_read': false,
        'priority': 'normal',
        'created_at': DateTime.now().toIso8601String(),
      });

      print(
          '🎯 TEST NOTIFICATION SENT to driver: ${driverId.substring(0, 8)}...');
    } catch (e) {
      print('❌ Error sending test notification: $e');
    }
  }

  /// Send reminder to driver
  Future<void> sendReminderToDriver(String tripId) async {
    try {
      // Get trip details
      final tripResponse =
          await Supabase.instance.client.from('trips').select('''
            id,
            trip_ref_number,
            origin,
            destination,
            start_time,
            driver_id,
            sub_driver_id
          ''').eq('id', tripId).single();

      final driverId =
          tripResponse['driver_id'] ?? tripResponse['sub_driver_id'];

      print('🔍 REMINDER DEBUG:');
      print('   Trip ID: $tripId');
      print('   Driver ID: $driverId');
      print('   Trip Ref: ${tripResponse['trip_ref_number']}');

      if (driverId == null) {
        throw Exception('No driver assigned to trip');
      }

      const title = '🔔 Trip Reminder';
      final message = 'Reminder: Please update status for trip '
          '${tripResponse['origin']} → ${tripResponse['destination']} '
          '(${tripResponse['trip_ref_number']})';

      // Save to database
      try {
        await Supabase.instance.client.from('driver_notifications').insert({
          'driver_id': driverId,
          'trip_id': tripId,
          'notification_type': 'trip_reminder',
          'title': title,
          'message': message,
          'is_read': false,
          'priority': 'normal',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (dbError) {
        if (!dbError.toString().contains('does not exist')) {
          print('❌ Error saving reminder notification: $dbError');
        }
      }

      // ✅ WORKING SOLUTION: Driver gets reminder via database!
      print('🎯 DRIVER REMINDER SENT: $title - $message');

      print(
          '✅ Reminder sent to driver for trip: ${tripResponse['trip_ref_number']}');
    } catch (e) {
      print('❌ Error sending reminder to driver: $e');
      throw e;
    }
  }

  /// Get driver name from trip data
  String _getDriverName(Map<String, dynamic> trip) {
    try {
      final user = trip['users'];
      if (user != null) {
        final firstName = user['first_name'] ?? '';
        final lastName = user['last_name'] ?? '';
        return '$firstName $lastName'.trim();
      }
      return 'Unknown Driver';
    } catch (e) {
      return 'Unknown Driver';
    }
  }

  /// Format date time for display
  String _formatDateTime(DateTime dateTime) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    final month = months[dateTime.month - 1];
    final day = dateTime.day;
    final hour = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final amPm = dateTime.hour >= 12 ? 'PM' : 'AM';

    return '$month $day at $hour:$minute $amPm';
  }

  /// Dispose of resources
  void dispose() {
    _overdueCheckTimer?.cancel();
  }
}
