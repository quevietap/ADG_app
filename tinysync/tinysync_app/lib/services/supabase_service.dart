import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver_performance.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  late SupabaseClient _client;

  void initialize(SupabaseClient client) {
    _client = client;
  }

  // MARK: - Behavior Logs (from unified snapshots table)
  Future<List<Map<String, dynamic>>> getBehaviorLogs({
    String? driverId,
    String? behaviorType,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  }) async {
    try {
      final response = await _client
          .from('snapshots')
          .select()
          .eq('event_type', 'behavior')
          .order('timestamp', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching behavior logs: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> subscribeToBehaviorLogs({
    String? driverId,
    int limit = 20,
  }) {
    return _client
        .from('snapshots')
        .stream(primaryKey: ['id'])
        .eq('event_type', 'behavior')
        .order('timestamp', ascending: false)
        .limit(limit)
        .map((event) => List<Map<String, dynamic>>.from(event));
  }

  // MARK: - System Logs (DISREGARDED - Not needed per simplified IoT approach)
  // Future<List<Map<String, dynamic>>> getSystemLogs({
  //   String? deviceId,
  //   String? logLevel,
  //   DateTime? startDate,
  //   DateTime? endDate,
  //   int limit = 50,
  // }) async {
  //   try {
  //     final response = await _client
  //         .from('system_logs')
  //         .select()
  //         .order('timestamp', ascending: false)
  //         .limit(limit);
  //
  //     return List<Map<String, dynamic>>.from(response);
  //   } catch (e) {
  //     print('Error fetching system logs: $e');
  //     return [];
  //   }
  // }

  // Stream<List<Map<String, dynamic>>> subscribeToSystemLogs({
  //   String? deviceId,
  //   int limit = 20,
  // }) {
  //   return _client
  //       .from('system_logs')
  //       .stream(primaryKey: ['id'])
  //       .order('timestamp', ascending: false)
  //       .limit(limit)
  //       .map((event) => List<Map<String, dynamic>>.from(event));
  // }

  // MARK: - Video Clips
  Future<List<Map<String, dynamic>>> getVideoClips({
    String? driverId,
    String? behaviorType,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 20,
  }) async {
    try {
      final response = await _client
          .from('video_clips')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching video clips: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> subscribeToSnapshots({
    String? driverId,
    int limit = 10,
  }) {
    return _client
        .from('snapshots')
        .stream(primaryKey: ['id'])
        .order('timestamp', ascending: false)
        .limit(limit)
        .map((event) => List<Map<String, dynamic>>.from(event));
  }

  // MARK: - IoT Data Handling
  Future<bool> saveBehaviorLog(Map<String, dynamic> behaviorData) async {
    try {
      // Ensure event_type is set to 'behavior' for unified snapshots table
      behaviorData['event_type'] = 'behavior';
      await _client.from('snapshots').insert(behaviorData);
      return true;
    } catch (e) {
      print('Error saving behavior log: $e');
      return false;
    }
  }

  Future<bool> saveSnapshot(Map<String, dynamic> snapshotData) async {
    try {
      await _client.from('snapshots').insert(snapshotData);
      return true;
    } catch (e) {
      print('Error saving snapshot: $e');
      return false;
    }
  }

  // Future<bool> saveSystemLog(Map<String, dynamic> systemLogData) async {
  //   try {
  //     await _client
  //         .from('system_logs')
  //         .insert(systemLogData);
  //     return true;
  //   } catch (e) {
  //     print('Error saving system log: $e');
  //     return false;
  //   }
  // }

  // MARK: - Sessions
  Future<List<Map<String, dynamic>>> getDriverSessions({
    String? driverId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 20,
  }) async {
    try {
      final response = await _client
          .from('driver_monitoring_sessions')
          .select()
          .order('start_time', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching driver sessions: $e');
      return [];
    }
  }

  // MARK: - Analytics
  Future<Map<String, dynamic>> getBehaviorAnalytics({
    String? driverId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Get all behavior logs and calculate analytics
      final behaviorResponse = await _client
          .from('snapshots')
          .select('behavior_type')
          .eq('event_type', 'behavior')
          .order('timestamp', ascending: false);

      // Calculate analytics
      Map<String, int> behaviorCounts = {};
      for (var log in behaviorResponse) {
        String behaviorType = log['behavior_type'];
        behaviorCounts[behaviorType] = (behaviorCounts[behaviorType] ?? 0) + 1;
      }

      // Get total sessions
      final sessionResponse =
          await _client.from('driver_monitoring_sessions').select('id');

      int totalSessions = sessionResponse.length;

      return {
        'behavior_counts': behaviorCounts,
        'total_sessions': totalSessions,
        'total_behaviors':
            behaviorCounts.values.fold<int>(0, (sum, count) => sum + count),
        'most_common_behavior': behaviorCounts.isNotEmpty
            ? behaviorCounts.entries
                .reduce((a, b) => a.value > b.value ? a : b)
                .key
            : null,
      };
    } catch (e) {
      print('Error fetching analytics: $e');
      return {
        'behavior_counts': {},
        'total_sessions': 0,
        'total_behaviors': 0,
        'most_common_behavior': null,
      };
    }
  }

  // MARK: - Device Status
  Future<Map<String, dynamic>?> getDeviceStatus(String deviceId) async {
    try {
      final response = await _client
          .from('pi_devices')
          .select()
          .eq('device_id', deviceId)
          .single();

      return response;
    } catch (e) {
      print('Error fetching device status: $e');
      return null;
    }
  }

  // MARK: - Trip Management
  Future<Map<String, dynamic>?> getCurrentTrip({String? driverId}) async {
    try {
      if (driverId == null) {
        print('No driver ID provided for current trip query');
        return null;
      }

      // Join with users and vehicles to get proper names
      final response = await _client
          .from('trips')
          .select('''
            *,
            driver:users!trips_driver_id_fkey(first_name, last_name),
            sub_driver:users!trips_sub_driver_id_fkey(first_name, last_name),
            vehicle:vehicles!trips_vehicle_id_fkey(plate_number, make, model, type)
          ''')
          .eq('driver_id', driverId)
          .eq('status', 'in_progress')
          .order('start_time', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        // Try to find any active trip assigned to this driver
        final fallbackResponse = await _client
            .from('trips')
            .select('''
              *,
              driver:users!trips_driver_id_fkey(first_name, last_name),
              sub_driver:users!trips_sub_driver_id_fkey(first_name, last_name),
              vehicle:vehicles!trips_vehicle_id_fkey(plate_number, make, model, type)
            ''')
            .or('driver_id.eq.$driverId,sub_driver_id.eq.$driverId')
            .eq('status', 'in_progress')
            .order('start_time', ascending: false)
            .limit(1)
            .maybeSingle();

        return fallbackResponse;
      }

      // Process the response to create proper field names
      final driver = response['driver'] as Map<String, dynamic>?;
      final subDriver = response['sub_driver'] as Map<String, dynamic>?;
      final vehicle = response['vehicle'] as Map<String, dynamic>?;

      
      response['vehicle_info'] = vehicle != null
          ? '${vehicle['plate_number']} (${vehicle['make']} ${vehicle['model']})'
          : 'N/A';

      return response;
    } catch (e) {
      print('Error fetching current trip: $e');
      return null;
    }
  }

  // MARK: - Trip-specific Logs and Videos
  Future<List<Map<String, dynamic>>> getTripBehaviorLogs({
    String? tripId,
    String? driverId,
    int limit = 50,
  }) async {
    try {
      if (tripId == null) {
        print('No trip ID provided for behavior logs query');
        return [];
      }

      // Try to query with trip_id first, fallback to driver_id only if trip_id doesn't exist
      List<Map<String, dynamic>> response;
      try {
        response = await _client
            .from('snapshots')
            .select()
            .eq('trip_id', tripId)
            .eq('event_type', 'behavior')
            .order('timestamp', ascending: false)
            .limit(limit);
      } catch (e) {
        // If trip_id column doesn't exist, fallback to driver_id only
        print('trip_id column may not exist, falling back to driver_id query');
        if (driverId == null) {
          print('No driver ID provided for fallback query');
          return [];
        }
        response = await _client
            .from('snapshots')
            .select()
            .eq('driver_id', driverId)
            .eq('event_type', 'behavior')
            .order('timestamp', ascending: false)
            .limit(limit);
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching trip behavior logs: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTripVideoClips({
    String? tripId,
    String? driverId,
    int limit = 20,
  }) async {
    try {
      if (tripId == null) {
        print('No trip ID provided for video clips query');
        return [];
      }

      // Try to query with trip_id first, fallback to driver_id only if trip_id doesn't exist
      List<Map<String, dynamic>> response;
      try {
        response = await _client
            .from('video_clips')
            .select()
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(limit);
      } catch (e) {
        // If trip_id column doesn't exist, fallback to driver_id only
        print('trip_id column may not exist, falling back to driver_id query');
        if (driverId == null) {
          print('No driver ID provided for fallback query');
          return [];
        }
        response = await _client
            .from('video_clips')
            .select()
            .eq('driver_id', driverId)
            .order('created_at', ascending: false)
            .limit(limit);
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching trip video clips: $e');
      return [];
    }
  }

  // Future<List<Map<String, dynamic>>> getTripSystemLogs({
  //   String? tripId,
  //   String? deviceId,
  //   int limit = 50,
  // }) async {
  //   try {
  //     if (tripId == null) {
  //       print('No trip ID provided for system logs query');
  //       return [];
  //     }
  //
  //     // Try to query with trip_id first, fallback to device_id only if trip_id doesn't exist
  //     List<Map<String, dynamic>> response;
  //     try {
  //         response = await _client
  //             .from('system_logs')
  //             .select()
  //             .eq('trip_id', tripId)
  //             .order('timestamp', ascending: false)
  //             .limit(limit);
  //     } catch (e) {
  //         // If trip_id column doesn't exist, fallback to device_id only
  //         print('trip_id column may not exist, falling back to device_id query');
  //         if (deviceId == null) {
  //           print('No device ID provided for fallback query');
  //           return [];
  //         }
  //         response = await _client
  //             .from('system_logs')
  //             .select()
  //             .eq('device_id', deviceId)
  //             .order('timestamp', ascending: false)
  //             .limit(limit);
  //     }
  //
  //     return List<Map<String, dynamic>>.from(response);
  //   } catch (e) {
  //     print('Error fetching trip system logs: $e');
  //     return [];
  //   }
  // }

  // MARK: - Trip Analytics
  Future<Map<String, dynamic>> getTripAnalytics({
    String? tripId,
    String? driverId,
  }) async {
    try {
      if (tripId == null) {
        print('No trip ID provided for analytics query');
        return {
          'trip_id': null,
          'behavior_counts': {},
          'total_behaviors': 0,
          'total_videos': 0,
          // 'total_system_logs': 0, // DISREGARDED
          'most_common_behavior': null,
        };
      }

      // Get behavior logs for this trip
      final behaviorResponse = await _client
          .from('snapshots')
          .select('behavior_type')
          .eq('trip_id', tripId)
          .eq('event_type', 'behavior')
          .order('timestamp', ascending: false);

      // Calculate analytics
      Map<String, int> behaviorCounts = {};
      for (var log in behaviorResponse) {
        String behaviorType = log['behavior_type'];
        behaviorCounts[behaviorType] = (behaviorCounts[behaviorType] ?? 0) + 1;
      }

      // Get video clips for this trip
      final videoResponse =
          await _client.from('video_clips').select('id').eq('trip_id', tripId);

      int totalVideos = videoResponse.length;

      // Get system logs for this trip (DISREGARDED - system_logs table removed)
      // final systemResponse = await _client
      //     .from('system_logs')
      //     .select('id')
      //     .eq('trip_id', tripId!);

      // int totalSystemLogs = systemResponse.length;
      int totalSystemLogs = 0; // DISREGARDED

      return {
        'trip_id': tripId,
        'behavior_counts': behaviorCounts,
        'total_behaviors':
            behaviorCounts.values.fold<int>(0, (sum, count) => sum + count),
        'total_videos': totalVideos,
        // 'total_system_logs': totalSystemLogs, // DISREGARDED
        'most_common_behavior': behaviorCounts.isNotEmpty
            ? behaviorCounts.entries
                .reduce((a, b) => a.value > b.value ? a : b)
                .key
            : null,
      };
    } catch (e) {
      print('Error fetching trip analytics: $e');
      return {
        'trip_id': tripId,
        'behavior_counts': {},
        'total_behaviors': 0,
        'total_videos': 0,
        // 'total_system_logs': 0, // DISREGARDED
        'most_common_behavior': null,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getDriverTrips({
    String? driverId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 20,
  }) async {
    try {
      final response = await _client
          .from('trips')
          .select()
          .or('main_driver_id.eq.$driverId,sub_driver_id.eq.$driverId')
          .order('scheduled_date', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching driver trips: $e');
      return [];
    }
  }

  // MARK: - Driver Performance
  Future<List<DriverPerformance>> getDriverPerformance() async {
    try {
      // Get all drivers with their performance data
      final driversResponse =
          await _client.from('drivers').select().order('name', ascending: true);

      List<DriverPerformance> drivers = [];

      for (var driverData in driversResponse) {
        final driverId = driverData['id'];

        // Get behavior analytics for this driver
        final analytics = await getBehaviorAnalytics(driverId: driverId);

        // Get recent behaviors
        final recentBehaviors = await _client
            .from('snapshots')
            .select('behavior_type')
            .eq('driver_id', driverId)
            .eq('event_type', 'behavior')
            .order('timestamp', ascending: false)
            .limit(5);

        // Calculate scores
        final behaviorCounts =
            analytics['behavior_counts'] as Map<String, dynamic>? ?? {};
        final totalBehaviors = analytics['total_behaviors'] as int? ?? 0;
        final totalSessions = analytics['total_sessions'] as int? ?? 0;

        // Calculate safety score (based on dangerous behaviors)
        int safetyScore = 100;
        int dangerousBehaviors = 0;
        for (var entry in behaviorCounts.entries) {
          if (['drowsiness', 'phone_usage', 'distracted'].contains(entry.key)) {
            dangerousBehaviors += entry.value as int;
          }
        }
        if (totalBehaviors > 0) {
          safetyScore =
              ((totalBehaviors - dangerousBehaviors) / totalBehaviors * 100)
                  .round();
        }

        // Calculate behavior score (based on all behaviors)
        int behaviorScore = 100;
        if (totalSessions > 0) {
          behaviorScore =
              ((totalSessions - totalBehaviors) / totalSessions * 100).round();
        }

        // Get operator rating
        final operatorRating = driverData['operator_rating'] ?? 3;
        final operatorNotes = driverData['operator_notes'];

        // Calculate performance rating
        final performanceRating = DriverPerformance.calculatePerformanceRating(
          safetyScore: safetyScore,
          behaviorScore: behaviorScore,
          operatorRating: operatorRating,
          totalSessions: totalSessions,
          totalBehaviors: totalBehaviors,
        );

        drivers.add(DriverPerformance(
          id: driverId,
          name: driverData['name'],
          licenseNumber: driverData['license_number'],
          profileImage: driverData['profile_image'],
          performanceRating: performanceRating,
          safetyScore: safetyScore,
          behaviorScore: behaviorScore,
          totalSessions: totalSessions,
          totalBehaviors: totalBehaviors,
          recentBehaviors:
              recentBehaviors.map((b) => b['behavior_type'] as String).toList(),
          isAvailable: driverData['is_available'] ?? true,
          lastActive: DateTime.parse(
              driverData['last_active'] ?? DateTime.now().toIso8601String()),
          behaviorCounts: Map<String, int>.from(behaviorCounts),
          operatorRating: operatorRating,
          operatorNotes: operatorNotes,
        ));
      }

      // Sort by performance rating (best first)
      drivers
          .sort((a, b) => b.performanceRating.compareTo(a.performanceRating));

      return drivers;
    } catch (e) {
      print('Error fetching driver performance: $e');
      return [];
    }
  }

  // MARK: - Operator Rating
  Future<void> rateDriver(String driverId, int rating, String? notes) async {
    try {
      await _client.from('drivers').update({
        'operator_rating': rating,
        'operator_notes': notes,
        'rated_at': DateTime.now().toIso8601String(),
      }).eq('id', driverId);
    } catch (e) {
      print('Error rating driver: $e');
    }
  }

  // MARK: - Utility Methods
  String getVideoUrl(String videoPath) {
    // Use the Supabase URL from config
    return 'https://your-project.supabase.co/storage/v1/object/public/video-clips/$videoPath';
  }

  String getImageUrl(String imagePath) {
    // Use the Supabase URL from config
    return 'https://your-project.supabase.co/storage/v1/object/public/profile-images/$imagePath';
  }
}
