import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notification service providing consistent, auto-dismissing toast notifications
/// with visual cues for different action types
class NotificationService {
  static const Duration _defaultDuration = Duration(seconds: 3);

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  RealtimeChannel? _tripStatusChannel;
  final List<Function(Map<String, dynamic>)> _notificationListeners = [];

  /// Initialize notification service
  Future<void> initialize() async {
    print('🔔 Initializing Notification Service...');

    // Set up real-time subscription for trip status changes
    _setupTripStatusSubscription();

    print('✅ Notification Service initialized');
  }

  /// Set up real-time subscription for trip status changes
  void _setupTripStatusSubscription() {
    _tripStatusChannel = Supabase.instance.client
        .channel('trip_status_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'trips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'status',
            value: 'in_progress',
          ),
          callback: (payload) {
            print('🔔 Trip status change detected: ${payload.eventType}');
            _handleTripStatusChange(payload);
          },
        )
        .subscribe();

    print('📡 Trip status subscription set up');
  }

  /// Handle trip status changes
  void _handleTripStatusChange(PostgresChangePayload payload) {
    try {
      final newRecord = payload.newRecord;
      if (newRecord['status'] == 'in_progress') {
        // Trip has started - notify all listeners
        final tripData = Map<String, dynamic>.from(newRecord);
        _notifyTripStarted(tripData);
      }
    } catch (e) {
      print('❌ Error handling trip status change: $e');
    }
  }

  /// Add notification listener
  void addNotificationListener(Function(Map<String, dynamic>) listener) {
    _notificationListeners.add(listener);
  }

  /// Remove notification listener
  void removeNotificationListener(Function(Map<String, dynamic>) listener) {
    _notificationListeners.remove(listener);
  }

  /// Notify all listeners about trip start
  void _notifyTripStarted(Map<String, dynamic> tripData) {
    print('🔔 Notifying trip start: ${tripData['id']}');

    for (final listener in _notificationListeners) {
      try {
        listener(tripData);
      } catch (e) {
        print('❌ Error in notification listener: $e');
      }
    }
  }

  /// Send trip start notification to operator
  Future<void> sendTripStartNotification({
    required String tripId,
    required String driverName,
    required String tripRefNumber,
  }) async {
    try {
      // Save notification to database
      await Supabase.instance.client.from('operator_notifications').insert({
        'trip_id': tripId,
        'notification_type': 'trip_started',
        'title': 'Trip Started',
        'message': 'Driver $driverName has started trip $tripRefNumber',
        'is_read': false,
        'priority': 'normal',
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Trip start notification saved to database');
    } catch (e) {
      if (e.toString().contains(
          'relation "public.operator_notifications" does not exist')) {
        print(
            '⚠️ operator_notifications table does not exist - skipping notification');
        // Don't throw error, just log it and continue
        return;
      } else {
        print('❌ Error saving notification: $e');
        // Continue even if database save fails
      }
    }
  }

  /// Send trip completion notification to operator
  Future<void> sendTripCompletionNotification({
    required String tripId,
    required String driverName,
    required String tripRefNumber,
  }) async {
    try {
      // Save notification to database
      await Supabase.instance.client.from('operator_notifications').insert({
        'trip_id': tripId,
        'notification_type': 'trip_completed',
        'title': 'Trip Completion Request',
        'message':
            'Driver $driverName claims to have completed trip $tripRefNumber. Please verify on the map and mark as complete.',
        'is_read': false,
        'priority': 'high',
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Trip completion notification saved to database');
    } catch (e) {
      if (e.toString().contains(
          'relation "public.operator_notifications" does not exist')) {
        print(
            '⚠️ operator_notifications table does not exist - skipping notification');
        return;
      } else {
        print('❌ Error saving completion notification: $e');
      }
    }
  }

  /// Send trip assignment notification to driver
  Future<void> sendTripAssignmentNotification({
    required String driverId,
    required String tripId,
    required String tripRefNumber,
    required String origin,
    required String destination,
    required DateTime startTime,
  }) async {
    try {
      // Save notification to database
      await Supabase.instance.client.from('driver_notifications').insert({
        'driver_id': driverId,
        'trip_id': tripId,
        'notification_type': 'trip_assigned',
        'title': 'New Trip Assignment',
        'message':
            'You have been assigned trip $tripRefNumber from $origin to $destination. Start time: ${_formatDateTime(startTime)}',
        'is_read': false,
        'priority': 'high',
        'created_at': DateTime.now().toIso8601String(),
        'scheduled_time': startTime.toIso8601String(),
      });

      print('✅ Trip assignment notification saved to database');

      // Schedule reminder notification 15 minutes before start time
      await _scheduleStartReminder(
        driverId: driverId,
        tripId: tripId,
        tripRefNumber: tripRefNumber,
        startTime: startTime,
      );
    } catch (e) {
      if (e
          .toString()
          .contains('relation "public.driver_notifications" does not exist')) {
        print(
            '⚠️ driver_notifications table does not exist - skipping notification');
        return;
      } else {
        print('❌ Error saving assignment notification: $e');
      }
    }
  }

  /// Send overdue trip alert to operators
  Future<void> sendOverdueTripAlert({
    required String tripId,
    required String tripRefNumber,
    required String driverName,
    required String overdueType, // 'not_started' or 'not_completed'
    required int minutesOverdue,
  }) async {
    try {
      final title = overdueType == 'not_started'
          ? 'Trip Start Overdue'
          : 'Trip Completion Overdue';

      final message = overdueType == 'not_started'
          ? 'Trip $tripRefNumber assigned to $driverName is $minutesOverdue minutes overdue to start'
          : 'Trip $tripRefNumber by $driverName is $minutesOverdue minutes overdue for completion';

      // Save notification to database
      await Supabase.instance.client.from('operator_notifications').insert({
        'trip_id': tripId,
        'notification_type': 'trip_overdue',
        'title': title,
        'message': message,
        'is_read': false,
        'priority': 'urgent',
        'metadata': jsonEncode({
          'overdue_type': overdueType,
          'minutes_overdue': minutesOverdue,
          'driver_name': driverName,
        }),
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Overdue trip alert saved to database');
    } catch (e) {
      if (e.toString().contains(
          'relation "public.operator_notifications" does not exist')) {
        print(
            '⚠️ operator_notifications table does not exist - skipping notification');
        return;
      } else {
        print('❌ Error saving overdue alert: $e');
      }
    }
  }

  /// Schedule start reminder notification
  Future<void> _scheduleStartReminder({
    required String driverId,
    required String tripId,
    required String tripRefNumber,
    required DateTime startTime,
  }) async {
    try {
      final reminderTime = startTime.subtract(Duration(minutes: 15));

      // Only schedule if reminder time is in the future
      if (reminderTime.isAfter(DateTime.now())) {
        try {
          await Supabase.instance.client
              .from('scheduled_notifications')
              .insert({
            'driver_id': driverId,
            'trip_id': tripId,
            'notification_type': 'trip_start_reminder',
            'title': 'Trip Starting Soon',
            'message':
                'Your trip $tripRefNumber starts in 15 minutes. Please get ready.',
            'scheduled_time': reminderTime.toIso8601String(),
            'is_sent': false,
            'priority': 'normal',
            'created_at': DateTime.now().toIso8601String(),
          });

          print(
              '✅ Start reminder scheduled for ${_formatDateTime(reminderTime)}');
        } catch (dbError) {
          if (dbError.toString().contains('does not exist')) {
            print(
                '⚠️ scheduled_notifications table does not exist - skipping scheduled notification');
          } else {
            throw dbError;
          }
        }
      }
    } catch (e) {
      print('⚠️ Error scheduling start reminder: $e');
      // Don't throw - this is a nice-to-have feature
    }
  }

  /// Send urgent reminder to driver
  Future<void> sendDriverReminder({
    required String driverId,
    required String tripId,
    required String title,
    required String message,
    required String urgency,
  }) async {
    try {
      // Save notification to database
      await Supabase.instance.client.from('driver_notifications').insert({
        'driver_id': driverId,
        'trip_id': tripId,
        'notification_type': 'urgent_reminder',
        'title': title,
        'message': message,
        'is_read': false,
        'priority': urgency,
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Driver reminder sent');
    } catch (e) {
      print('❌ Error sending driver reminder: $e');
      throw e;
    }
  }

  /// Send trip reassignment notification to old driver
  Future<void> sendTripReassignmentNotification({
    required String driverId,
    required String tripId,
    required String tripRefNumber,
    required String reason,
    required String newDriverName,
  }) async {
    try {
      await Supabase.instance.client.from('driver_notifications').insert({
        'driver_id': driverId,
        'trip_id': tripId,
        'notification_type': 'trip_reassigned',
        'title': 'Trip Reassigned',
        'message':
            'Trip $tripRefNumber has been reassigned to $newDriverName. Reason: $reason',
        'is_read': false,
        'priority': 'normal',
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Trip reassignment notification sent');
    } catch (e) {
      print('❌ Error sending reassignment notification: $e');
      throw e;
    }
  }

  /// Send trip cancellation notification to driver
  Future<void> sendTripCancellationNotification({
    required String driverId,
    required String tripId,
    required String tripRefNumber,
    required String reason,
  }) async {
    try {
      await Supabase.instance.client.from('driver_notifications').insert({
        'driver_id': driverId,
        'trip_id': tripId,
        'notification_type': 'trip_cancelled',
        'title': 'Trip Cancelled',
        'message': 'Trip $tripRefNumber has been cancelled. Reason: $reason',
        'is_read': false,
        'priority': 'high',
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Trip cancellation notification sent');
    } catch (e) {
      print('❌ Error sending cancellation notification: $e');
      throw e;
    }
  }

  /// Format DateTime for display
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await Supabase.instance.client
          .from('operator_notifications')
          .update({'is_read': true}).eq('id', notificationId);

      print('✅ Notification marked as read');
    } catch (e) {
      if (e.toString().contains(
          'relation "public.operator_notifications" does not exist')) {
        print(
            '⚠️ operator_notifications table does not exist - skipping mark as read');
        return;
      } else {
        print('❌ Error marking notification as read: $e');
      }
    }
  }

  /// Get unread notifications
  Future<List<Map<String, dynamic>>> getUnreadNotifications() async {
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

  /// Start overdue tracking system
  void startOverdueTracking() {
    print('🕒 Starting overdue trip tracking...');

    // Check for overdue trips every 5 minutes
    Timer.periodic(Duration(minutes: 5), (timer) {
      _checkOverdueTrips();
    });

    // Also check immediately
    _checkOverdueTrips();
  }

  /// Check for overdue trips
  Future<void> _checkOverdueTrips() async {
    try {
      print('🔍 Checking for overdue trips...');

      final now = DateTime.now();

      // Check for trips that should have started but haven't
      await _checkOverdueStarts(now);

      // Check for trips that should have completed but haven't
      await _checkOverdueCompletions(now);
    } catch (e) {
      print('❌ Error checking overdue trips: $e');
    }
  }

  /// Check for trips overdue to start
  Future<void> _checkOverdueStarts(DateTime now) async {
    try {
      final overdueTrips =
          await Supabase.instance.client.from('trips').select('''
            id,
            trip_ref_number,
            start_time,
            driver_id,
            driver:users!trips_driver_id_fkey(first_name, last_name)
          ''').eq('status', 'assigned').lt('start_time', now.toIso8601String());

      for (final trip in overdueTrips) {
        final startTime = DateTime.parse(trip['start_time']);
        final minutesOverdue = now.difference(startTime).inMinutes;

        // Only alert if overdue by at least 10 minutes to avoid false alarms
        if (minutesOverdue >= 10) {
          final driver = trip['driver'];
          final driverName = '${driver['first_name']} ${driver['last_name']}';

          // Check if we've already sent an alert for this trip recently
          final recentAlert =
              await _hasRecentOverdueAlert(trip['id'], 'not_started');

          if (!recentAlert) {
            await sendOverdueTripAlert(
              tripId: trip['id'],
              tripRefNumber: trip['trip_ref_number'],
              driverName: driverName,
              overdueType: 'not_started',
              minutesOverdue: minutesOverdue,
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error checking overdue starts: $e');
    }
  }

  /// Check for trips overdue to complete
  Future<void> _checkOverdueCompletions(DateTime now) async {
    try {
      final overdueTrips = await Supabase.instance.client
          .from('trips')
          .select('''
            id,
            trip_ref_number,
            end_time,
            driver_id,
            driver:users!trips_driver_id_fkey(first_name, last_name)
          ''')
          .eq('status', 'in_progress')
          .lt('end_time', now.toIso8601String());

      for (final trip in overdueTrips) {
        final endTime = DateTime.parse(trip['end_time']);
        final minutesOverdue = now.difference(endTime).inMinutes;

        // Only alert if overdue by at least 15 minutes
        if (minutesOverdue >= 15) {
          final driver = trip['driver'];
          final driverName = '${driver['first_name']} ${driver['last_name']}';

          // Check if we've already sent an alert for this trip recently
          final recentAlert =
              await _hasRecentOverdueAlert(trip['id'], 'not_completed');

          if (!recentAlert) {
            await sendOverdueTripAlert(
              tripId: trip['id'],
              tripRefNumber: trip['trip_ref_number'],
              driverName: driverName,
              overdueType: 'not_completed',
              minutesOverdue: minutesOverdue,
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error checking overdue completions: $e');
    }
  }

  /// Check if we've sent a recent overdue alert for this trip
  Future<bool> _hasRecentOverdueAlert(String tripId, String overdueType) async {
    try {
      final oneHourAgo = DateTime.now().subtract(Duration(hours: 1));

      final recentAlerts = await Supabase.instance.client
          .from('operator_notifications')
          .select('id')
          .eq('trip_id', tripId)
          .eq('notification_type', 'trip_overdue')
          .gte('created_at', oneHourAgo.toIso8601String())
          .limit(1);

      return recentAlerts.isNotEmpty;
    } catch (e) {
      print('❌ Error checking recent alerts: $e');
      return false; // If we can't check, allow the alert
    }
  }

  /// Process scheduled notifications (should be called periodically)
  Future<void> processScheduledNotifications() async {
    try {
      final now = DateTime.now();

      final dueNotifications = await Supabase.instance.client
          .from('scheduled_notifications')
          .select('*')
          .eq('is_sent', false)
          .lte('scheduled_time', now.toIso8601String());

      for (final notification in dueNotifications) {
        await _sendScheduledNotification(notification);

        // Mark as sent
        await Supabase.instance.client
            .from('scheduled_notifications')
            .update({'is_sent': true}).eq('id', notification['id']);
      }
    } catch (e) {
      if (e.toString().contains('does not exist')) {
        print(
            '⚠️ scheduled_notifications table does not exist - skipping scheduled notification processing');
      } else {
        print('❌ Error processing scheduled notifications: $e');
      }
    }
  }

  /// Send a scheduled notification
  Future<void> _sendScheduledNotification(
      Map<String, dynamic> notification) async {
    try {
      // Save to driver notifications
      await Supabase.instance.client.from('driver_notifications').insert({
        'driver_id': notification['driver_id'],
        'trip_id': notification['trip_id'],
        'notification_type': notification['notification_type'],
        'title': notification['title'],
        'message': notification['message'],
        'is_read': false,
        'priority': notification['priority'],
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Scheduled notification sent: ${notification['title']}');
    } catch (e) {
      print('❌ Error sending scheduled notification: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _tripStatusChannel?.unsubscribe();
    _notificationListeners.clear();
  }

  /// Show a success notification (green theme)
  /// Used for: successful driver/truck additions, successful updates
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
    IconData icon = Icons.check_circle,
  }) {
    _showNotification(
      context,
      message,
      backgroundColor: Colors.green,
      textColor: Colors.white,
      icon: icon,
      duration: duration,
    );
  }

  /// Show a warning/cancel notification (orange/yellow theme)
  /// Used for: trip cancellations, warnings
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
    IconData icon = Icons.warning,
  }) {
    _showNotification(
      context,
      message,
      backgroundColor: Colors.orange,
      textColor: Colors.white,
      icon: icon,
      duration: duration,
    );
  }

  /// Show an error/delete notification (red theme)
  /// Used for: trip deletions, errors, failures
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
    IconData icon = Icons.error,
  }) {
    _showNotification(
      context,
      message,
      backgroundColor: Colors.red,
      textColor: Colors.white,
      icon: icon,
      duration: duration,
    );
  }

  /// Show an info notification (blue theme)
  /// Used for: general information, assignments
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
    IconData icon = Icons.info,
  }) {
    _showNotification(
      context,
      message,
      backgroundColor: Colors.blue,
      textColor: Colors.white,
      icon: icon,
      duration: duration,
    );
  }

  /// Private method to show the actual SnackBar with consistent styling
  static void _showNotification(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    required Color textColor,
    required IconData icon,
    required Duration duration,
  }) {
    // Clear any existing snackbars to prevent stacking
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              icon,
              color: textColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 6,
        // Auto-dismiss without close button for cleaner UI
        showCloseIcon: false,
      ),
    );
  }

  /// Utility method to show notifications based on operation type
  /// This provides a consistent interface for common CRUD operations
  static void showOperationResult(
    BuildContext context, {
    required String
        operation, // 'added', 'updated', 'deleted', 'cancelled', 'assigned'
    required String itemType, // 'driver', 'truck', 'trip', 'vehicle', etc.
    required bool success,
    String? customMessage,
    String? errorDetails,
  }) {
    String message;

    if (customMessage != null) {
      message = customMessage;
    } else if (success) {
      switch (operation.toLowerCase()) {
        case 'added':
        case 'created':
          message = '${_capitalize(itemType)} added successfully!';
          break;
        case 'updated':
        case 'modified':
          message = '${_capitalize(itemType)} updated successfully!';
          break;
        case 'assigned':
          message = '${_capitalize(itemType)} assigned successfully!';
          break;
        case 'restored':
          message = '${_capitalize(itemType)} restored successfully!';
          break;
        case 'cancelled':
          message = '${_capitalize(itemType)} has been cancelled';
          break;
        case 'deleted':
          message = '${_capitalize(itemType)} has been deleted';
          break;
        default:
          message = 'Operation completed successfully';
      }
    } else {
      message =
          'Failed to ${operation.toLowerCase()} ${itemType.toLowerCase()}';
      if (errorDetails != null) {
        message += ': $errorDetails';
      }
    }

    if (success) {
      switch (operation.toLowerCase()) {
        case 'added':
        case 'created':
        case 'updated':
        case 'modified':
        case 'assigned':
        case 'restored':
          showSuccess(context, message);
          break;
        case 'cancelled':
          showWarning(context, message);
          break;
        case 'deleted':
          showError(context, message, icon: Icons.delete_outline);
          break;
        default:
          showInfo(context, message);
      }
    } else {
      showError(context, message);
    }
  }

  /// Send enhanced driver reminder with multi-channel delivery
  Future<void> sendEnhancedDriverReminder({
    required String tripId,
    required String driverId,
    required String tripRef,
    required String origin,
    required String destination,
  }) async {
    try {
      print('🚀 ENHANCED NOTIFICATION: Sending immediate driver reminder...');

      const title = '🔔 Urgent Trip Reminder';
      final message =
          'REMINDER: Please update status for trip $origin → $destination ($tripRef). Operator is waiting for your response.';
      final timestamp = DateTime.now().toIso8601String();

      // 1. Save to database with high priority
      try {
        await Supabase.instance.client.from('driver_notifications').insert({
          'driver_id': driverId,
          'trip_id': tripId,
          'notification_type': 'urgent_reminder',
          'title': title,
          'message': message,
          'is_read': false,
          'priority': 'high',
          'created_at': timestamp,
        });
        print('✅ Enhanced reminder saved to database');
      } catch (dbError) {
        if (!dbError.toString().contains('does not exist')) {
          print('⚠️ Database reminder failed: $dbError');
        }
      }

      // 2. Broadcast real-time notification
      try {
        final channel =
            Supabase.instance.client.channel('driver_urgent_reminders');
        await channel.subscribe();

        channel.sendBroadcastMessage(
          event: 'urgent_trip_reminder',
          payload: {
            'driver_id': driverId,
            'trip_id': tripId,
            'trip_ref': tripRef,
            'title': title,
            'message': message,
            'priority': 'high',
            'timestamp': timestamp,
            'origin': origin,
            'destination': destination,
            'action_required': true,
          },
        );

        // Brief delay then unsubscribe
        await Future.delayed(const Duration(milliseconds: 300));
        await channel.unsubscribe();

        print('✅ Real-time reminder broadcast sent');
      } catch (e) {
        print('⚠️ Real-time broadcast failed: $e');
      }

      // 3. Update trip metadata for driver app detection
      try {
        await Supabase.instance.client.from('trips').update({
          'last_reminder_sent': timestamp,
          'reminder_count': 1, // Simple increment - can be improved
        }).eq('id', tripId);
        print('✅ Trip reminder metadata updated');
      } catch (e) {
        print('⚠️ Trip metadata update failed: $e');
      }

      print('🎯 ENHANCED DRIVER REMINDER: Multi-channel delivery completed');
    } catch (e) {
      print('❌ Error in enhanced driver reminder: $e');
      throw e;
    }
  }

  /// Helper method to capitalize first letter
  static String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}
