import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to fetch and track driver locations for operator view
class DriverLocationService {
  static final DriverLocationService _instance = DriverLocationService._internal();
  factory DriverLocationService() => _instance;
  DriverLocationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Cache for driver locations to avoid repeated database calls
  // Use user-specific caching to prevent cross-account data leakage
  final Map<String, Map<String, dynamic>> _driverLocationCache = {};
  final Map<String, RealtimeChannel> _driverLocationChannels = {};
  
  // Stream controllers for real-time updates
  final Map<String, StreamController<Map<String, dynamic>>> _locationControllers = {};
  
  // Current user context to prevent cross-account caching
  String? _currentUserId;

  /// Safe conversion helper for numeric values from Supabase
  double? _safeToDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed;
    }
    return null;
  }

  /// Get the latest location for a specific driver
  Future<Map<String, dynamic>?> getDriverLocation(String driverId) async {
    try {
      // Check if user context has changed (account switch)
      final currentUser = _supabase.auth.currentUser;
      if (currentUser?.id != _currentUserId) {
        print('🔄 USER CONTEXT CHANGED: Clearing cache for new user');
        _clearAllCaches();
        _currentUserId = currentUser?.id;
      }

      // Check cache first
      if (_driverLocationCache.containsKey(driverId)) {
        final cached = _driverLocationCache[driverId]!;
        final timestamp = DateTime.tryParse(cached['timestamp'] ?? '');
        if (timestamp != null && DateTime.now().difference(timestamp).inMinutes < 5) {
          print('📱 Using cached driver location for driver: $driverId');
          return cached;
        }
      }

      print('🔍 OPERATOR REQUESTING DRIVER LOCATION for driver ID: $driverId');
      print('👤 Current user ID: ${currentUser?.id}');
      print('📧 Current user email: ${currentUser?.email}');

      // Query the most recent location from trip_locations table (where drivers actually save location)
      final response = await _supabase
          .from('trip_locations')
          .select('latitude, longitude, accuracy, speed, heading, timestamp')
          .eq('driver_id', driverId)
          .order('timestamp', ascending: false)
          .limit(1)
          .maybeSingle(); // Use maybeSingle() instead of single() to handle no results gracefully

      if (response != null) {
        final locationData = {
          'latitude': _safeToDouble(response['latitude']) ?? 0.0,
          'longitude': _safeToDouble(response['longitude']) ?? 0.0,
          'accuracy': _safeToDouble(response['accuracy']),
          'speed': _safeToDouble(response['speed']),
          'heading': _safeToDouble(response['heading']),
          'timestamp': response['timestamp'] as String,
          'is_active': true, // trip_locations are always active
        };

        // Update cache
        _driverLocationCache[driverId] = locationData;
        
        print('✅ FRESH DRIVER LOCATION RETRIEVED:');
        print('   📍 Coordinates: ${locationData['latitude']}, ${locationData['longitude']}');
        print('   🕒 Timestamp: ${locationData['timestamp']}');
        print('   🎯 Driver ID: $driverId');
        print('   📱 This is NOT the operator\'s location!');
        return locationData;
      }

      print('⚠️ No location data found for driver: $driverId');
      print('   📱 This is normal if the driver hasn\'t started sharing location yet');
      return null;

    } catch (e) {
      print('❌ Error fetching driver location: $e');
      print('   📱 This is normal if the driver hasn\'t started sharing location yet');
      return null;
    }
  }

  /// Get driver location for a specific trip
  Future<Map<String, dynamic>?> getDriverLocationForTrip(String tripId) async {
    try {
      print('📍 Fetching driver location for trip: $tripId');

      // First get the trip to find the assigned driver
      final tripResponse = await _supabase
          .from('trips')
          .select('driver_id, sub_driver_id')
          .eq('id', tripId)
          .single();

      final driverId = tripResponse['driver_id'] ?? tripResponse['sub_driver_id'];
      print('🔍 Found driver ID: $driverId');
      
      if (driverId == null) {
        print('⚠️ No driver assigned to trip: $tripId');
        return null;
      }

      // Get the driver's location
      print('📍 Fetching location for driver ID: $driverId');
      final location = await getDriverLocation(driverId);
      
      if (location != null) {
        print('✅ DRIVER LOCATION FOUND: ${location['latitude']}, ${location['longitude']}');
        print('   📍 This is the DRIVER\'S location, NOT the operator\'s');
        print('   🚗 Driver ID: $driverId');
        print('   🎯 Trip ID: $tripId');
      } else {
        print('❌ No location found for driver ID: $driverId');
        print('   📱 Driver may not have shared location yet');
      }
      
      return location;

    } catch (e) {
      print('❌ Error fetching driver location for trip: $e');
      return null;
    }
  }

  /// Subscribe to real-time driver location updates
  Stream<Map<String, dynamic>> subscribeToDriverLocation(String driverId) {
    // Create stream controller if it doesn't exist
    if (!_locationControllers.containsKey(driverId)) {
      _locationControllers[driverId] = StreamController<Map<String, dynamic>>.broadcast();
      
      // Start real-time subscription
      _startDriverLocationSubscription(driverId);
    }
    
    return _locationControllers[driverId]!.stream;
  }

  /// Subscribe to real-time driver location updates for a specific trip
  Stream<Map<String, dynamic>> subscribeToTripDriverLocation(String tripId) {
    return Stream.fromFuture(_getTripDriverId(tripId)).asyncExpand((driverId) {
      if (driverId != null) {
        return subscribeToDriverLocation(driverId);
      }
      return const Stream.empty();
    });
  }

  /// Start real-time subscription for a driver's location
  void _startDriverLocationSubscription(String driverId) {
    try {
      if (_driverLocationChannels.containsKey(driverId)) {
        return; // Already subscribed
      }

      print('🔄 Starting real-time subscription for driver: $driverId');

      final channel = _supabase
          .channel('driver_location_$driverId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'trip_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'driver_id',
              value: driverId,
            ),
            callback: (payload) {
              _handleDriverLocationUpdate(driverId, payload);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'trip_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'driver_id',
              value: driverId,
            ),
            callback: (payload) {
              _handleDriverLocationUpdate(driverId, payload);
            },
          )
          .subscribe();

      _driverLocationChannels[driverId] = channel;
      print('✅ Real-time subscription started for driver: $driverId');

    } catch (e) {
      print('❌ Error starting driver location subscription: $e');
    }
  }

  /// Handle real-time driver location updates
  void _handleDriverLocationUpdate(String driverId, PostgresChangePayload payload) {
    try {
      final newRecord = payload.newRecord;
      final locationData = {
        'latitude': _safeToDouble(newRecord['latitude']) ?? 0.0,
        'longitude': _safeToDouble(newRecord['longitude']) ?? 0.0,
        'accuracy': _safeToDouble(newRecord['accuracy']),
        'speed': _safeToDouble(newRecord['speed']),
        'heading': _safeToDouble(newRecord['heading']),
        'timestamp': newRecord['timestamp'] as String,
        'is_active': true, // trip_locations are always active
      };

      // Update cache
      _driverLocationCache[driverId] = locationData;

      // Notify listeners
      _locationControllers[driverId]?.add(locationData);

      print('📍 Real-time driver location update: ${locationData['latitude']}, ${locationData['longitude']}');
        } catch (e) {
      print('❌ Error handling driver location update: $e');
    }
  }

  /// Get driver ID for a specific trip
  Future<String?> _getTripDriverId(String tripId) async {
    try {
      final response = await _supabase
          .from('trips')
          .select('driver_id, sub_driver_id')
          .eq('id', tripId)
          .single();

      return response['driver_id'] ?? response['sub_driver_id'];
    } catch (e) {
      print('❌ Error getting trip driver ID: $e');
      return null;
    }
  }

  /// Check if driver has started the trip
  Future<bool> hasDriverStartedTrip(String tripId) async {
    try {
      final response = await _supabase
          .from('trips')
          .select('status, start_time')
          .eq('id', tripId)
          .single();

      final status = response['status'] as String?;
      final startTime = response['start_time'] as String?;

      // Trip is considered started if status is 'in_progress' or has a start_time
      return status == 'in_progress' || startTime != null;
    } catch (e) {
      print('❌ Error checking if driver started trip: $e');
      return false;
    }
  }

  /// Get driver status for a trip
  Future<String> getDriverTripStatus(String tripId) async {
    try {
      // First check if driver has accepted the trip
      final hasAccepted = await hasDriverAcceptedTrip(tripId);
      if (!hasAccepted) {
        return 'Driver has not accepted trip';
      }

      final hasStarted = await hasDriverStartedTrip(tripId);
      if (!hasStarted) {
        return 'Driver not yet started';
      }

      final driverLocation = await getDriverLocationForTrip(tripId);
      if (driverLocation == null) {
        return 'Location unavailable';
      }

      return 'Driver en route';
    } catch (e) {
      print('❌ Error getting driver trip status: $e');
      return 'Status unavailable';
    }
  }

  /// Check if driver has accepted the trip assignment
  Future<bool> hasDriverAcceptedTrip(String tripId) async {
    try {
      final response = await _supabase
          .from('trips')
          .select('status, driver_id, sub_driver_id, start_time, accepted_at')
          .eq('id', tripId)
          .single();

      final status = response['status'] as String?;
      final driverId = response['driver_id'] ?? response['sub_driver_id'];
      final startTime = response['start_time'] as String?;
      final acceptedAt = response['accepted_at'] as String?;

      // If no driver assigned, they can't have accepted
      if (driverId == null) {
        print('❌ No driver assigned to trip: $tripId');
        return false;
      }

      // Driver has accepted if:
      // 1. Trip status is 'in_progress' (driver started the trip)
      // 2. Trip has a start_time (driver began the trip)
      // 3. Trip has accepted_at timestamp (explicit acceptance)
      // 4. Trip status is 'assigned' AND driver is actively sharing location (indicates acceptance)
      final hasStarted = status == 'in_progress' || startTime != null;
      final hasExplicitAcceptance = acceptedAt != null;
      final isAssigned = status == 'assigned';

      if (hasStarted) {
        print('✅ Driver has accepted and started trip: $tripId (status: $status)');
        return true;
      }

      if (hasExplicitAcceptance) {
        print('✅ Driver has explicitly accepted trip: $tripId (accepted_at: $acceptedAt)');
        return true;
      }

      if (isAssigned) {
        // For assigned trips, check if driver is actively sharing location (indicates acceptance)
        final driverLocation = await getDriverLocation(driverId);
        final isSharingLocation = driverLocation != null;
        
        if (isSharingLocation) {
          // Additional check: make sure the location is recent (within last 10 minutes)
          final timestamp = DateTime.tryParse(driverLocation['timestamp'] ?? '');
          if (timestamp != null) {
            final timeDiff = DateTime.now().difference(timestamp).inMinutes;
            if (timeDiff <= 10) {
              print('✅ Driver has accepted trip and is actively sharing location: $tripId (${timeDiff}min ago)');
              return true;
            } else {
              print('⏳ Trip is assigned but driver location is stale: $tripId (${timeDiff}min ago)');
              return false;
            }
          } else {
            print('⏳ Trip is assigned but driver location timestamp invalid: $tripId');
            return false;
          }
        } else {
          print('⏳ Trip is assigned but driver not yet sharing location: $tripId');
          return false;
        }
      }

      print('❌ Driver has not accepted trip: $tripId (status: $status)');
      return false;
    } catch (e) {
      print('❌ Error checking if driver accepted trip: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    for (final controller in _locationControllers.values) {
      controller.close();
    }
    _locationControllers.clear();

    for (final channel in _driverLocationChannels.values) {
      channel.unsubscribe();
    }
    _driverLocationChannels.clear();

    _driverLocationCache.clear();
  }

  /// Clear cache for a specific driver
  void clearDriverCache(String driverId) {
    _driverLocationCache.remove(driverId);
  }

  /// Clear all caches (private method)
  void _clearAllCaches() {
    _driverLocationCache.clear();
    
    // Close all stream controllers
    for (final controller in _locationControllers.values) {
      controller.close();
    }
    _locationControllers.clear();
    
    // Unsubscribe from all channels
    for (final channel in _driverLocationChannels.values) {
      channel.unsubscribe();
    }
    _driverLocationChannels.clear();
    
    print('🧹 All caches and subscriptions cleared');
  }

  /// Clear all caches (public method)
  void clearAllCaches() {
    _clearAllCaches();
  }

  /// Force refresh driver location (bypass cache)
  Future<Map<String, dynamic>?> forceRefreshDriverLocation(String driverId) async {
    print('🔄 FORCE REFRESH: Clearing cache for driver: $driverId');
    _driverLocationCache.remove(driverId);
    return await getDriverLocation(driverId);
  }

  /// Force refresh driver location for trip (bypass cache)
  Future<Map<String, dynamic>?> forceRefreshDriverLocationForTrip(String tripId) async {
    try {
      print('🔄 FORCE REFRESH: Getting fresh driver location for trip: $tripId');

      // First get the trip to find the assigned driver
      final tripResponse = await _supabase
          .from('trips')
          .select('driver_id, sub_driver_id')
          .eq('id', tripId)
          .single();

      final driverId = tripResponse['driver_id'] ?? tripResponse['sub_driver_id'];
      print('🔍 Found driver ID: $driverId');
      
      if (driverId == null) {
        print('⚠️ No driver assigned to trip: $tripId');
        return null;
      }

      // Force refresh the driver's location
      return await forceRefreshDriverLocation(driverId);
    } catch (e) {
      print('❌ Error force refreshing driver location for trip: $e');
      return null;
    }
  }
}
