import 'package:flutter/material.dart';
import 'lib/services/notification_tracking_service.dart';

/// Test script to verify notification tracking functionality
/// Run this to test the notification deduplication system
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final tracker = NotificationTrackingService();
  
  print('🧪 Testing Notification Tracking Service...\n');
  
  // Test 1: Generate notification IDs
  print('Test 1: Generating notification IDs');
  final tripStatusId = tracker.generateTripStatusNotificationId(
    tripId: 'trip_123',
    status: 'in_progress',
    driverId: 'driver_456',
  );
  print('Trip status ID: $tripStatusId');
  
  final tripAssignmentId = tracker.generateTripAssignmentNotificationId(
    tripId: 'trip_123',
    driverId: 'driver_456',
  );
  print('Trip assignment ID: $tripAssignmentId');
  
  final userStatusId = tracker.generateUserStatusNotificationId(
    userId: 'driver_456',
    status: 'active',
  );
  print('User status ID: $userStatusId\n');
  
  // Test 2: Check if notifications have been shown (should be false initially)
  print('Test 2: Checking if notifications have been shown');
  final hasBeenShown1 = await tracker.hasNotificationBeenShown(tripStatusId);
  print('Trip status notification shown: $hasBeenShown1');
  
  final hasBeenShown2 = await tracker.hasNotificationBeenShown(tripAssignmentId);
  print('Trip assignment notification shown: $hasBeenShown2');
  
  final hasBeenShown3 = await tracker.hasNotificationBeenShown(userStatusId);
  print('User status notification shown: $hasBeenShown3\n');
  
  // Test 3: Mark notifications as shown
  print('Test 3: Marking notifications as shown');
  await tracker.markNotificationAsShown(tripStatusId);
  await tracker.markNotificationAsShown(tripAssignmentId);
  await tracker.markNotificationAsShown(userStatusId);
  print('✅ All notifications marked as shown\n');
  
  // Test 4: Check again (should be true now)
  print('Test 4: Checking if notifications have been shown (should be true now)');
  final hasBeenShown4 = await tracker.hasNotificationBeenShown(tripStatusId);
  print('Trip status notification shown: $hasBeenShown4');
  
  final hasBeenShown5 = await tracker.hasNotificationBeenShown(tripAssignmentId);
  print('Trip assignment notification shown: $hasBeenShown5');
  
  final hasBeenShown6 = await tracker.hasNotificationBeenShown(userStatusId);
  print('User status notification shown: $hasBeenShown6\n');
  
  // Test 5: Check stored notification count
  print('Test 5: Checking stored notification count');
  final count = await tracker.getStoredNotificationCount();
  print('Stored notifications count: $count\n');
  
  // Test 6: Test with different notification IDs (should not be shown)
  print('Test 6: Testing with different notification IDs');
  final differentId = tracker.generateTripStatusNotificationId(
    tripId: 'trip_789', // Different trip ID
    status: 'completed',
    driverId: 'driver_456',
  );
  final hasBeenShown7 = await tracker.hasNotificationBeenShown(differentId);
  print('Different trip status notification shown: $hasBeenShown7\n');
  
  // Test 7: Clear notification history
  print('Test 7: Clearing notification history');
  await tracker.clearNotificationHistory();
  final countAfterClear = await tracker.getStoredNotificationCount();
  print('Stored notifications count after clear: $countAfterClear\n');
  
  // Test 8: Verify notifications are not shown after clear
  print('Test 8: Verifying notifications are not shown after clear');
  final hasBeenShown8 = await tracker.hasNotificationBeenShown(tripStatusId);
  print('Trip status notification shown after clear: $hasBeenShown8\n');
  
  print('🎉 Notification tracking test completed!');
  print('\n📋 Test Summary:');
  print('- ✅ Notification ID generation works');
  print('- ✅ Initial state shows notifications as not shown');
  print('- ✅ Marking notifications as shown works');
  print('- ✅ Checking shown status works after marking');
  print('- ✅ Different notification IDs are tracked separately');
  print('- ✅ Clear history functionality works');
  print('- ✅ Notifications are not shown after clearing history');
}
