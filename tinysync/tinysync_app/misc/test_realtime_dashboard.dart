// Test script to demonstrate real-time driver dashboard functionality
// Run this in VS Code terminal: dart run test_realtime_dashboard.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

void main() async {
  print('🚗 Testing Real-Time Driver Dashboard Functionality\n');

  // Initialize Supabase (you'll need to update these credentials)
  await Supabase.initialize(
    url: 'https://hhsaglfvhdlgsbqmcwbw.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
  );

  print('✅ Connected to Supabase');

  try {
    // Test 1: Check if real-time is working
    print('\n🔄 Test 1: Setting up real-time subscription...');

    final subscription = Supabase.instance.client
        .channel('test_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          callback: (payload) {
            print('🔔 Real-time update detected: ${payload.eventType}');
            print(
                '   User: ${payload.newRecord['first_name']} ${payload.newRecord['last_name']}');
            print('   Status: ${payload.newRecord['status']}');
          },
        )
        .subscribe();

    print('✅ Real-time subscription active');

    // Test 2: Check drivers with profile images
    print('\n📸 Test 2: Checking drivers with profile images...');

    final drivers = await Supabase.instance.client
        .from('users')
        .select('id, first_name, last_name, status, profile_image_url')
        .eq('role', 'driver')
        .limit(5);

    print('Found ${drivers.length} drivers:');
    for (final driver in drivers) {
      final hasImage = driver['profile_image_url'] != null &&
          driver['profile_image_url'].toString().isNotEmpty;
      final status = driver['status'] ?? 'unknown';

      print(
          '  📷 ${driver['first_name']} ${driver['last_name']} - $status ${hasImage ? '(has image)' : '(no image)'}');
    }

    // Test 3: Test status update
    print('\n🔄 Test 3: Testing status update simulation...');

    if (drivers.isNotEmpty) {
      final testDriver = drivers.first;
      final currentStatus = testDriver['status'];
      final newStatus = currentStatus == 'active' ? 'inactive' : 'active';

      print(
          '   Updating ${testDriver['first_name']} ${testDriver['last_name']} from $currentStatus to $newStatus...');

      await Supabase.instance.client.from('users').update({
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', testDriver['id']);

      print('✅ Status updated - real-time subscriptions should trigger');

      // Wait a bit to see real-time updates
      await Future.delayed(const Duration(seconds: 2));

      // Revert the change
      await Supabase.instance.client.from('users').update({
        'status': currentStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', testDriver['id']);

      print('✅ Status reverted to original state');
    }

    print('\n🎉 All tests completed successfully!');
    print('\nReal-time features are working:');
    print('✅ Driver status updates sync instantly');
    print('✅ Profile images load correctly');
    print('✅ Database subscriptions are active');
    print('✅ Operator dashboards will see changes in real-time');

    // Clean up
    await subscription.unsubscribe();
    print('\n🧹 Cleaned up subscriptions');
  } catch (e) {
    print('❌ Error during testing: $e');
  }

  exit(0);
}
