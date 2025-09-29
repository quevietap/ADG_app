class SupabaseConfig {
  // Replace these with your actual Supabase credentials
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
  
  // Storage bucket names
  static const String videoBucket = 'video-clips';
  static const String imageBucket = 'profile-images';
  static const String snapshotsBucket = 'snapshots';  // New: For AI snapshots
  
  // Table names (unified structure)
  static const String behaviorLogsTable = 'snapshots'; // Now using unified snapshots table
  // static const String systemLogsTable = 'system_logs'; // DISREGARDED
  static const String snapshotsTable = 'snapshots';
  
  // Real-time channel names
  static const String behaviorChannel = 'behavior_logs';
  // static const String systemChannel = 'system_logs'; // DISREGARDED
  static const String snapshotsChannel = 'snapshots';
  
  // Default device ID
  static const String defaultDeviceId = 'tinysync-pi-001';
  
  // Behavior types
  static const List<String> behaviorTypes = [
    'drowsiness',
    'looking_away',
    'phone_usage',
    'distracted',
    'no_face',
    'eyes_closed',
    'head_down',
    'yawning',
    'face_turned',
    'gaze_restored',
    'drowsiness_cleared',
  ];
  
  // Log levels
  static const List<String> logLevels = [
    'DEBUG',
    'INFO',
    'WARNING',
    'ERROR',
    'CRITICAL',
  ];
}
