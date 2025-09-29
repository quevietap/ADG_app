import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://hhsaglfvhdlgsbqmcwbw.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
  );

  try {
    // Query all users to see current state
    final response = await Supabase.instance.client
        .from('users')
        .select('id, first_name, last_name, username, role')
        .order('created_at');

    print('=== CURRENT DATABASE STATE ===');
    print('Total users found: ${response.length}');

    for (var user in response) {
      print('User: ${user['first_name']} ${user['last_name']}');
      print('  ID: ${user['id']}');
      print('  Username: ${user['username']}');
      print('  Role: ${user['role']}');
      print('  ---');
    }

    // Specifically look for the user ID that was supposedly deleted
    final specificUser = await Supabase.instance.client
        .from('users')
        .select('*')
        .eq('id', '557940e3-124e-4b4b-8508-8024489595fc')
        .maybeSingle();

    print('\n=== SPECIFIC USER CHECK ===');
    if (specificUser != null) {
      print(
          '❌ User 557940e3-124e-4b4b-8508-8024489595fc STILL EXISTS in database!');
      print('User data: $specificUser');
    } else {
      print(
          '✅ User 557940e3-124e-4b4b-8508-8024489595fc not found in database');
    }
  } catch (e) {
    print('Error querying database: $e');
  }
}
