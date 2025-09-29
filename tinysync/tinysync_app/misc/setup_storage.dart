import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://hhsaglfvhdlgsbqmcwbw.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
  );

  try {
    print('🚀 Setting up Supabase Storage...');

    // Create the user-profiles storage bucket
    print('📁 Creating storage bucket...');
    final bucketResponse = await Supabase.instance.client.storage.createBucket(
      'user-profiles',
      const BucketOptions(public: true),
    );
    print('✅ Bucket created: $bucketResponse');

    // Check if bucket exists
    final buckets = await Supabase.instance.client.storage.listBuckets();
    print('📋 Available buckets: ${buckets.map((b) => b.name).toList()}');

    // Test upload permissions by trying to create the bucket policies
    print('🔐 Storage bucket setup completed!');
    print('ℹ️  Note: RLS policies need to be configured in Supabase Dashboard');
    print('   Go to: Storage > Policies > user-profiles bucket');
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('✅ Bucket already exists, which is good!');

      // Check if bucket exists
      final buckets = await Supabase.instance.client.storage.listBuckets();
      print('📋 Available buckets: ${buckets.map((b) => b.name).toList()}');
    } else {
      print('❌ Error setting up storage: $e');
    }
  }

  // Test basic storage access
  try {
    print('🧪 Testing storage access...');
    final files =
        await Supabase.instance.client.storage.from('user-profiles').list();
    print('✅ Storage access test successful: ${files.length} files found');
  } catch (e) {
    print('⚠️  Storage access test failed: $e');
    print('   This might be due to missing RLS policies');
  }
}
