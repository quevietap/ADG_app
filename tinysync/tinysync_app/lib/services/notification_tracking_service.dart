import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to track shown notifications and prevent duplicates
class NotificationTrackingService {
  static const String _shownNotificationsKey = 'shown_notifications';
  static const String _notificationTimestampsKey = 'notification_timestamps';
  static const int _maxStoredNotifications = 100; // Keep last 100 notifications
  static const Duration _notificationExpiration = Duration(hours: 24); // Notifications expire after 24 hours
  static const Duration _readNotificationExpiration = Duration(hours: 2); // Read notifications expire after 2 hours
  
  static final NotificationTrackingService _instance = NotificationTrackingService._internal();
  factory NotificationTrackingService() => _instance;
  NotificationTrackingService._internal();

  /// Check if a notification has already been shown
  Future<bool> hasNotificationBeenShown(String notificationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shownNotificationsJson = prefs.getString(_shownNotificationsKey);
      
      if (shownNotificationsJson == null) {
        return false;
      }
      
      final shownNotifications = List<String>.from(json.decode(shownNotificationsJson));
      return shownNotifications.contains(notificationId);
    } catch (e) {
      print('❌ Error checking notification history: $e');
      return false; // If error, allow notification to show
    }
  }

  /// Mark a notification as shown
  Future<void> markNotificationAsShown(String notificationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shownNotificationsJson = prefs.getString(_shownNotificationsKey);
      final timestampsJson = prefs.getString(_notificationTimestampsKey);
      
      List<String> shownNotifications = [];
      Map<String, int> timestamps = {};
      
      if (shownNotificationsJson != null) {
        shownNotifications = List<String>.from(json.decode(shownNotificationsJson));
      }
      
      if (timestampsJson != null) {
        final decoded = json.decode(timestampsJson);
        timestamps = Map<String, int>.from(decoded.map((key, value) => MapEntry(key.toString(), value as int)));
      }
      
      // Add new notification ID if not already present
      if (!shownNotifications.contains(notificationId)) {
        shownNotifications.add(notificationId);
        timestamps[notificationId] = DateTime.now().millisecondsSinceEpoch;
        
        // Clean up expired notifications
        await _cleanupExpiredNotifications(shownNotifications, timestamps);
        
        // Keep only the most recent notifications to prevent storage bloat
        if (shownNotifications.length > _maxStoredNotifications) {
          shownNotifications = shownNotifications.sublist(
            shownNotifications.length - _maxStoredNotifications
          );
        }
        
        // Save back to preferences
        await prefs.setString(_shownNotificationsKey, json.encode(shownNotifications));
        await prefs.setString(_notificationTimestampsKey, json.encode(timestamps));
        print('✅ Notification marked as shown: $notificationId');
      }
    } catch (e) {
      print('❌ Error marking notification as shown: $e');
    }
  }

  /// Generate a unique notification ID based on content and context
  String generateNotificationId({
    required String type,
    required String tripId,
    required String driverId,
    String? additionalContext,
  }) {
    final context = additionalContext ?? '';
    return '${type}_${tripId}_${driverId}_$context';
  }

  /// Generate notification ID for trip status changes
  String generateTripStatusNotificationId({
    required String tripId,
    required String status,
    required String driverId,
  }) {
    return generateNotificationId(
      type: 'trip_status_$status',
      tripId: tripId,
      driverId: driverId,
    );
  }

  /// Generate notification ID for trip assignments
  String generateTripAssignmentNotificationId({
    required String tripId,
    required String driverId,
  }) {
    return generateNotificationId(
      type: 'trip_assigned',
      tripId: tripId,
      driverId: driverId,
    );
  }

  /// Generate notification ID for user status changes
  String generateUserStatusNotificationId({
    required String userId,
    required String status,
  }) {
    return generateNotificationId(
      type: 'user_status_$status',
      tripId: userId, // Using userId as tripId for user status notifications
      driverId: userId,
    );
  }

  /// Clean up expired notifications automatically
  Future<void> _cleanupExpiredNotifications(List<String> shownNotifications, Map<String, int> timestamps) async {
    try {
      final now = DateTime.now();
      final expirationTime = now.subtract(_notificationExpiration);
      
      // Remove expired notifications
      final validNotifications = <String>[];
      final validTimestamps = <String, int>{};
      
      for (final notificationId in shownNotifications) {
        final timestamp = timestamps[notificationId];
        if (timestamp != null) {
          final notificationTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          if (notificationTime.isAfter(expirationTime)) {
            validNotifications.add(notificationId);
            validTimestamps[notificationId] = timestamp;
          }
        }
      }
      
      // Update the lists
      shownNotifications.clear();
      shownNotifications.addAll(validNotifications);
      timestamps.clear();
      timestamps.addAll(validTimestamps);
      
      print('🧹 Cleaned up expired notifications. Remaining: ${shownNotifications.length}');
    } catch (e) {
      print('❌ Error cleaning up expired notifications: $e');
    }
  }

  /// Check if a notification should be hidden based on age and read status
  Future<bool> shouldHideNotification(String notificationId, bool isRead, DateTime createdAt) async {
    try {
      final now = DateTime.now();
      
      // Hide read notifications older than 2 hours
      if (isRead && createdAt.isBefore(now.subtract(_readNotificationExpiration))) {
        return true;
      }
      
      // Hide all notifications older than 24 hours
      if (createdAt.isBefore(now.subtract(_notificationExpiration))) {
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking if notification should be hidden: $e');
      return false;
    }
  }

  /// Perform maintenance cleanup (call this periodically)
  Future<void> performMaintenanceCleanup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shownNotificationsJson = prefs.getString(_shownNotificationsKey);
      final timestampsJson = prefs.getString(_notificationTimestampsKey);
      
      List<String> shownNotifications = [];
      Map<String, int> timestamps = {};
      
      if (shownNotificationsJson != null) {
        shownNotifications = List<String>.from(json.decode(shownNotificationsJson));
      }
      
      if (timestampsJson != null) {
        final decoded = json.decode(timestampsJson);
        timestamps = Map<String, int>.from(decoded.map((key, value) => MapEntry(key.toString(), value as int)));
      }
      
      // Clean up expired notifications
      await _cleanupExpiredNotifications(shownNotifications, timestamps);
      
      // Save back to preferences
      await prefs.setString(_shownNotificationsKey, json.encode(shownNotifications));
      await prefs.setString(_notificationTimestampsKey, json.encode(timestamps));
      
      print('🧹 Maintenance cleanup completed. ${shownNotifications.length} notifications remaining');
    } catch (e) {
      print('❌ Error during maintenance cleanup: $e');
    }
  }

  /// Clear all notification history (useful for testing or reset)
  Future<void> clearNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_shownNotificationsKey);
      await prefs.remove(_notificationTimestampsKey);
      print('✅ Notification history cleared');
    } catch (e) {
      print('❌ Error clearing notification history: $e');
    }
  }

  /// Get count of stored notifications (for debugging)
  Future<int> getStoredNotificationCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shownNotificationsJson = prefs.getString(_shownNotificationsKey);
      
      if (shownNotificationsJson == null) {
        return 0;
      }
      
      final shownNotifications = List<String>.from(json.decode(shownNotificationsJson));
      return shownNotifications.length;
    } catch (e) {
      print('❌ Error getting notification count: $e');
      return 0;
    }
  }
}
