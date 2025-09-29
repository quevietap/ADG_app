import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:location/location.dart' as location_pkg;

class RealTimeLocationService {
  static final RealTimeLocationService _instance =
      RealTimeLocationService._internal();
  factory RealTimeLocationService() => _instance;
  RealTimeLocationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _locationTimer;
  Timer? _uploadTimer;
  RealtimeChannel? _locationChannel;

  // Location tracking state
  bool _isTracking = false;
  String? _currentTripId;
  String? _currentDriverId;

  // Callbacks for UI updates
  Function(Map<String, dynamic>)? _onLocationUpdate;
  Function(double)? _onProgressUpdate;
  Function(String)? _onError;

  // Location service
  final location_pkg.Location _location = location_pkg.Location();

  /// Start real-time location tracking for a driver
  Future<void> startTracking({
    required String driverId,
    required String tripId,
    Function(Map<String, dynamic>)? onLocationUpdate,
    Function(double)? onProgressUpdate,
    Function(String)? onError,
  }) async {
    try {
      _currentDriverId = driverId;
      _currentTripId = tripId;
      _onLocationUpdate = onLocationUpdate;
      _onProgressUpdate = onProgressUpdate;
      _onError = onError;

      print(
          '🚀 Starting real-time location tracking for driver: $driverId, trip: $tripId');

      // Check and request location permissions
      await _checkLocationPermissions();

      // Start location updates
      await _startLocationUpdates();

      // Start real-time subscription for operator view
      await _startRealtimeSubscription();

      _isTracking = true;
      print('✅ Real-time tracking started successfully');
    } catch (e) {
      print('❌ Error starting real-time tracking: $e');
      _onError?.call('Failed to start tracking: $e');
    }
  }

  /// Stop real-time location tracking
  Future<void> stopTracking() async {
    try {
      print('🛑 Stopping real-time location tracking');

      _isTracking = false;
      _locationTimer?.cancel();
      _uploadTimer?.cancel();
      _locationChannel?.unsubscribe();

      _currentDriverId = null;
      _currentTripId = null;
      _onLocationUpdate = null;
      _onProgressUpdate = null;
      _onError = null;

      print('✅ Real-time tracking stopped successfully');
    } catch (e) {
      print('❌ Error stopping real-time tracking: $e');
    }
  }

  /// Check and request location permissions
  Future<void> _checkLocationPermissions() async {
    try {
      // Check if location service is enabled
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          throw Exception('Location service is not enabled');
        }
      }

      // Check location permissions
      location_pkg.PermissionStatus permission =
          await _location.hasPermission();
      if (permission == location_pkg.PermissionStatus.denied) {
        permission = await _location.requestPermission();
        if (permission == location_pkg.PermissionStatus.denied) {
          throw Exception('Location permission denied');
        }
      }

      print('✅ Location permissions granted');
    } catch (e) {
      print('❌ Location permission error: $e');
      rethrow;
    }
  }

  /// Start periodic location updates
  Future<void> _startLocationUpdates() async {
    try {
      // Get initial location
      await _getAndUploadLocation();

      // Start high-frequency location updates (every 3 seconds for real-time tracking)
      _locationTimer =
          Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (_isTracking) {
          await _getAndUploadLocation();
        }
      });

      // Start periodic progress updates (every 15 seconds)
      _uploadTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
        if (_isTracking && _currentTripId != null) {
          await _updateTripProgress();
        }
      });
    } catch (e) {
      print('❌ Error starting location updates: $e');
      rethrow;
    }
  }

  /// Start real-time subscription for operator view
  Future<void> _startRealtimeSubscription() async {
    try {
      if (_currentDriverId == null) return;

      _locationChannel = _supabase
          .channel('real_time_driver_location_$_currentDriverId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'driver_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'driver_id',
              value: _currentDriverId!,
            ),
            callback: (payload) {
              print(
                  '📍 Real-time location update received: ${payload.newRecord}');
              // Broadcast to operator dashboards
              _onLocationUpdate?.call({
                'type': 'realtime_update',
                'data': payload.newRecord,
                'timestamp': DateTime.now().toIso8601String(),
              });
            },
          )
          .subscribe();

      print('✅ Real-time subscription started for driver: $_currentDriverId');
    } catch (e) {
      print('❌ Error starting real-time subscription: $e');
    }
  }

  /// Get current location and upload to database
  Future<void> _getAndUploadLocation() async {
    try {
      print('📍 Getting current location...');

      final locationData = await _location.getLocation().timeout(
            const Duration(seconds: 10),
          );

      if (locationData.latitude != null && locationData.longitude != null) {
        print(
            '✅ Location obtained: ${locationData.latitude}, ${locationData.longitude}');

        // Upload location to database
        await _uploadLocationToDatabase(locationData);

        // Notify UI about location update
        _onLocationUpdate?.call({
          'latitude': locationData.latitude,
          'longitude': locationData.longitude,
          'accuracy': locationData.accuracy,
          'speed': locationData.speed,
          'heading': locationData.heading,
          'timestamp': DateTime.now().toIso8601String(),
        });
      } else {
        print('⚠️ Location data is null');
        _onError?.call('Unable to get location data');
      }
    } catch (e) {
      print('❌ Error getting location: $e');
      _onError?.call('Location error: $e');
    }
  }

  /// Upload location data to Supabase
  Future<void> _uploadLocationToDatabase(
      location_pkg.LocationData locationData) async {
    try {
      if (_currentDriverId == null) {
        print('⚠️ No driver ID set for location upload');
        return;
      }

      final locationRecord = {
        'driver_id': _currentDriverId,
        'trip_id': _currentTripId,
        'latitude': locationData.latitude,
        'longitude': locationData.longitude,
        'accuracy': locationData.accuracy,
        'speed': locationData.speed,
        'heading': locationData.heading,
        'altitude': locationData.altitude,
        'timestamp': DateTime.now().toIso8601String(),
        'is_active': true,
      };

      await _supabase.from('driver_locations').insert(locationRecord);

      print('✅ Location uploaded to database');
    } catch (e) {
      print('❌ Error uploading location to database: $e');
      _onError?.call('Database upload error: $e');
    }
  }

  /// Update trip progress in database
  Future<void> _updateTripProgress() async {
    try {
      if (_currentTripId == null) return;

      // Get latest location
      final latestLocation = await _getLatestDriverLocation();
      if (latestLocation == null) return;

      // Calculate progress using database function
      final progressResult =
          await _supabase.rpc('calculate_trip_progress', params: {
        'trip_uuid': _currentTripId!.toString(),
        'current_lat': latestLocation['latitude'],
        'current_lon': latestLocation['longitude'],
      });

      if (progressResult != null && progressResult.isNotEmpty) {
        final progress = progressResult[0];
        final progressPercentage = progress['progress_percentage'] as double;

        // Update trip progress
        await _supabase.from('trips').update({
          'progress_percentage': progressPercentage,
          'last_location_update': DateTime.now().toIso8601String(),
        }).eq('id', _currentTripId!);

        // Notify UI about progress update
        _onProgressUpdate?.call(progressPercentage);

        print(
            '📊 Trip progress updated: ${progressPercentage.toStringAsFixed(1)}%');
      }
    } catch (e) {
      print('❌ Error updating trip progress: $e');
    }
  }

  /// Get latest driver location from database
  Future<Map<String, dynamic>?> _getLatestDriverLocation() async {
    try {
      if (_currentDriverId == null) return null;

      final result = await _supabase.rpc('get_latest_driver_location', params: {
        'driver_uuid': _currentDriverId,
      });

      if (result != null && result.isNotEmpty) {
        return result[0] as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('❌ Error getting latest driver location: $e');
      return null;
    }
  }

  /// Get driver location history
  Future<List<Map<String, dynamic>>> getDriverLocationHistory({
    required String driverId,
    int hoursBack = 24,
  }) async {
    try {
      final result =
          await _supabase.rpc('get_driver_location_history', params: {
        'driver_uuid': driverId,
        'hours_back': hoursBack,
      });

      if (result != null) {
        return List<Map<String, dynamic>>.from(result);
      }

      return [];
    } catch (e) {
      print('❌ Error getting driver location history: $e');
      return [];
    }
  }

  /// Get active driver locations for operator dashboard
  Future<List<Map<String, dynamic>>> getActiveDriverLocations() async {
    try {
      final result = await _supabase
          .from('active_driver_locations')
          .select('*')
          .order('timestamp', ascending: false);

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('❌ Error getting active driver locations: $e');
      return [];
    }
  }

  /// Subscribe to driver location updates (for operator view)
  RealtimeChannel subscribeToDriverLocation({
    required String driverId,
    required Function(Map<String, dynamic>) onLocationUpdate,
  }) {
    final channel =
        _supabase.channel('driver_location_$driverId').onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'driver_locations',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'driver_id',
                value: driverId,
              ),
              callback: (payload) {
                onLocationUpdate(payload.newRecord);
              },
            );

    return channel;
  }

  /// Check if tracking is active
  bool get isTracking => _isTracking;

  /// Get current driver ID
  String? get currentDriverId => _currentDriverId;

  /// Get current trip ID
  String? get currentTripId => _currentTripId;
}
