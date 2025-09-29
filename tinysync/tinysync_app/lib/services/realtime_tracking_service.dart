import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';

class RealtimeTrackingService {
  static final RealtimeTrackingService _instance =
      RealtimeTrackingService._internal();
  factory RealtimeTrackingService() => _instance;
  RealtimeTrackingService._internal();

  // Tracking state
  final Map<String, bool> _activeTrips = {};
  final Map<String, RealtimeChannel> _tripChannels = {};
  final Map<String, List<LatLng>> _tripPaths = {};
  final Map<String, LatLng?> _currentLocations = {};
  final Map<String, StreamController<Map<String, dynamic>>>
      _locationControllers = {};

  // Performance settings - Optimized for real-time tracking
  static const double _minDistanceForUpdate =
      5.0; // meters (reduced for better tracking)
  static const int _maxPathPoints = 1000; // Limit path points for performance

  // Getters
  bool isTripActive(String tripId) => _activeTrips[tripId] ?? false;
  LatLng? getCurrentLocation(String tripId) => _currentLocations[tripId];
  List<LatLng> getTripPath(String tripId) => _tripPaths[tripId] ?? [];

  /// Start tracking a specific trip
  Future<bool> startTrackingTrip(String tripId, String driverId) async {
    try {
      if (_activeTrips[tripId] == true) {
        print('⚠️ Trip $tripId is already being tracked');
        return true;
      }

      print('🚀 Starting real-time tracking for trip: $tripId');

      // Initialize tracking state
      _activeTrips[tripId] = true;
      _tripPaths[tripId] = [];
      _currentLocations[tripId] = null;
      _locationControllers[tripId] =
          StreamController<Map<String, dynamic>>.broadcast();

      // Load existing trip path
      await _loadTripPath(tripId);

      // Subscribe to real-time location updates
      await _subscribeToTripUpdates(tripId, driverId);

      print('✅ Real-time tracking started for trip: $tripId');
      return true;
    } catch (e) {
      print('❌ Error starting tracking for trip $tripId: $e');
      _cleanupTrip(tripId);
      return false;
    }
  }

  /// Stop tracking a specific trip
  Future<void> stopTrackingTrip(String tripId) async {
    try {
      print('🛑 Stopping real-time tracking for trip: $tripId');

      _activeTrips[tripId] = false;
      _tripChannels[tripId]?.unsubscribe();
      _tripChannels.remove(tripId);
      _locationControllers[tripId]?.close();
      _locationControllers.remove(tripId);

      print('✅ Real-time tracking stopped for trip: $tripId');
    } catch (e) {
      print('❌ Error stopping tracking for trip $tripId: $e');
    }
  }

  /// Subscribe to real-time location updates for a trip
  Future<void> _subscribeToTripUpdates(String tripId, String driverId) async {
    try {
      // Subscribe to trip_locations table updates
      final channel = Supabase.instance.client
          .channel('trip_tracking_$tripId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'trip_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'trip_id',
              value: tripId,
            ),
            callback: (payload) {
              _handleLocationUpdate(tripId, payload);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'trips',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: tripId,
            ),
            callback: (payload) {
              _handleTripStatusUpdate(tripId, payload);
            },
          )
          .subscribe();

      _tripChannels[tripId] = channel;
      print('✅ Subscribed to real-time updates for trip: $tripId');
    } catch (e) {
      print('❌ Error subscribing to trip updates: $e');
    }
  }

  /// Handle incoming location updates
  void _handleLocationUpdate(String tripId, PostgresChangePayload payload) {
    try {
      if (!_activeTrips[tripId]!) return;

      final newRecord = payload.newRecord;

      final latitude = newRecord['latitude'] as double?;
      final longitude = newRecord['longitude'] as double?;
      final locationType = newRecord['location_type'] as String?;
      final timestamp = newRecord['timestamp'] as String?;

      if (latitude != null && longitude != null) {
        final newLocation = LatLng(latitude, longitude);

        // Update current location
        _currentLocations[tripId] = newLocation;

        // Add to trip path (with performance optimization)
        _addToTripPath(tripId, newLocation, locationType);

        // Notify listeners
        _locationControllers[tripId]?.add({
          'type': 'location_update',
          'tripId': tripId,
          'location': newLocation,
          'locationType': locationType,
          'timestamp': timestamp,
        });

        print(
            '📍 Location update for trip $tripId: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}');
      }
    } catch (e) {
      print('❌ Error handling location update: $e');
    }
  }

  /// Handle trip status updates
  void _handleTripStatusUpdate(String tripId, PostgresChangePayload payload) {
    try {
      if (!_activeTrips[tripId]!) return;

      final newRecord = payload.newRecord;

      final status = newRecord['status'] as String?;
      final currentLat = newRecord['current_latitude'] as double?;
      final currentLng = newRecord['current_longitude'] as double?;

      if (currentLat != null && currentLng != null) {
        _currentLocations[tripId] = LatLng(currentLat, currentLng);
      }

      // Notify listeners of status change
      _locationControllers[tripId]?.add({
        'type': 'status_update',
        'tripId': tripId,
        'status': status,
        'currentLocation': _currentLocations[tripId],
      });

      print('🔄 Status update for trip $tripId: $status');
    } catch (e) {
      print('❌ Error handling status update: $e');
    }
  }

  /// Add location to trip path with performance optimization
  void _addToTripPath(String tripId, LatLng location, String? locationType) {
    final path = _tripPaths[tripId] ?? [];

    // Always add start and end points
    if (locationType == 'start' || locationType == 'end') {
      path.add(location);
    } else {
      // For tracking points, check distance from last point
      if (path.isEmpty) {
        path.add(location);
      } else {
        final lastLocation = path.last;
        final distance = _calculateDistance(lastLocation, location);

        // Only add if distance is significant enough
        if (distance >= _minDistanceForUpdate) {
          path.add(location);

          // Limit path points for performance
          if (path.length > _maxPathPoints) {
            path.removeAt(0);
          }
        }
      }
    }

    _tripPaths[tripId] = path;
  }

  /// Load existing trip path from database
  Future<void> _loadTripPath(String tripId) async {
    try {
      // Try to use the get_trip_path function first
      final response = await Supabase.instance.client
          .rpc('get_trip_path', params: {'trip_uuid': tripId});

      final path = <LatLng>[];
      for (final record in response) {
        final lat = record['latitude'] as double?;
        final lng = record['longitude'] as double?;
        if (lat != null && lng != null) {
          path.add(LatLng(lat, lng));
        }
      }

      _tripPaths[tripId] = path;
      print(
          '📊 Loaded ${path.length} path points for trip: $tripId using get_trip_path function');
    } catch (e) {
      print('❌ Error loading trip path with function: $e');

      // Fallback to direct table query
      try {
        final response = await Supabase.instance.client
            .from('trip_locations')
            .select('latitude, longitude, timestamp')
            .eq('trip_id', tripId)
            .order('timestamp');

        final path = <LatLng>[];
        for (final record in response) {
          final lat = record['latitude'] as double?;
          final lng = record['longitude'] as double?;
          if (lat != null && lng != null) {
            path.add(LatLng(lat, lng));
          }
        }

        _tripPaths[tripId] = path;
        print(
            '📊 Loaded ${path.length} path points for trip: $tripId using direct table query');
      } catch (e2) {
        print('❌ Error loading trip path with direct query: $e2');
        // Initialize empty path - will be populated when real GPS data arrives
        _tripPaths[tripId] = [];
        print(
            '⚠️ No trip path data available yet for trip: $tripId - waiting for real GPS data');
      }
    }
  }

  /// Get location stream for a trip
  Stream<Map<String, dynamic>> getLocationStream(String tripId) {
    return _locationControllers[tripId]?.stream ?? const Stream.empty();
  }

  /// Calculate distance between two points in meters
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    final lat1Rad = point1.latitude * (pi / 180);
    final lat2Rad = point2.latitude * (pi / 180);
    final deltaLat = (point2.latitude - point1.latitude) * (pi / 180);
    final deltaLng = (point2.longitude - point1.longitude) * (pi / 180);

    final a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(deltaLng / 2) * sin(deltaLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Clean up resources for a trip
  void _cleanupTrip(String tripId) {
    _activeTrips.remove(tripId);
    _tripChannels.remove(tripId);
    _tripPaths.remove(tripId);
    _currentLocations.remove(tripId);
    _locationControllers[tripId]?.close();
    _locationControllers.remove(tripId);
  }

  /// Stop all tracking
  Future<void> stopAllTracking() async {
    print('🛑 Stopping all real-time tracking');

    for (final tripId in _activeTrips.keys.toList()) {
      await stopTrackingTrip(tripId);
    }

    _activeTrips.clear();
    _tripChannels.clear();
    _tripPaths.clear();
    _currentLocations.clear();
    _locationControllers.clear();

    print('✅ All real-time tracking stopped');
  }

  /// Get trip statistics
  Future<Map<String, dynamic>?> getTripStatistics(String tripId) async {
    try {
      final response = await Supabase.instance.client
          .rpc('get_trip_statistics', params: {'trip_uuid': tripId});

      if (response.isNotEmpty) {
        return response.first;
      }
      return null;
    } catch (e) {
      print('❌ Error getting trip statistics: $e');
      return null;
    }
  }

  /// Dispose of all resources
  void dispose() {
    stopAllTracking();
  }
}
