import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:location/location.dart' as location_pkg;
import 'package:geocoding/geocoding.dart' hide Location;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Location tracking state
  bool _isLocationEnabled = false;
  bool _isTracking = false;
  Timer? _locationTimer;
  location_pkg.LocationData? _currentLocationData;
  StreamSubscription<location_pkg.LocationData>? _locationStream;

  // Real-time location updates
  RealtimeChannel? _locationChannel;

  // Location tracking settings - Optimized for driver safety and high accuracy
  static const Duration _locationUpdateInterval =
      Duration(seconds: 3); // Balanced updates for driver safety
  static const double _minDistanceForUpdate =
      2.0; // 2 meters - Balanced sensitivity for driver safety

  // Location instance
  final location_pkg.Location _location = location_pkg.Location();

  // Getters
  bool get isLocationEnabled => _isLocationEnabled;
  bool get isTracking => _isTracking;
  location_pkg.LocationData? get currentLocationData => _currentLocationData;

  /// Initialize location service and check permissions
  Future<bool> initialize() async {
    try {
      print('📍 Initializing Location Service...');

      // Add a small delay to ensure Android plugin is ready
      await Future.delayed(const Duration(milliseconds: 100));

      // Check if location services are enabled with timeout
      bool serviceEnabled =
          await _location.serviceEnabled().timeout(const Duration(seconds: 5));
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        serviceEnabled = await _location
            .requestService()
            .timeout(const Duration(seconds: 10));
        if (!serviceEnabled) {
          print('❌ Could not enable location services');
          return false;
        }
      }

      // Check location permissions
      location_pkg.PermissionStatus permission =
          await _location.hasPermission();
      if (permission == location_pkg.PermissionStatus.denied) {
        permission = await _location.requestPermission();
        if (permission == location_pkg.PermissionStatus.denied) {
          print('❌ Location permissions denied');
          return false;
        }
      }

      if (permission == location_pkg.PermissionStatus.deniedForever) {
        print('❌ Location permissions permanently denied');
        return false;
      }

      // Request additional permissions for background location
      await _requestLocationPermissions();

      // Test location access to detect Huawei/Google Play Services issues
      try {
        await _location.getLocation().timeout(const Duration(seconds: 5));
        print('✅ Google Play Services location access confirmed');
      } catch (e) {
        if (e.toString().contains('SERVICE_INVALID') ||
            e.toString().contains('Google Play Store')) {
          print(
              '📱 Huawei device detected - Google Play Services not available');
          print('📍 Will use fallback location methods');
        } else if (e.toString().contains('API_KEY')) {
          print(
              '🚨 GOOGLE MAPS API KEY ISSUE: Please add a valid API key to AndroidManifest.xml');
          print('📍 Maps will not work properly without a valid API key');
        } else {
          print('⚠️ Location access test failed: $e');
        }
      }

      _isLocationEnabled = true;
      print('✅ Location Service initialized successfully');
      return true;
    } catch (e) {
      print('❌ Error initializing Location Service: $e');

      // Even if initialization fails, we can still provide fallback location
      if (e.toString().contains('SERVICE_INVALID') ||
          e.toString().contains('Google Play Store')) {
        print('📱 Huawei device - Enabling fallback location mode');
        _isLocationEnabled = true;
        return true;
      }

      return false;
    }
  }

  /// Request all necessary location permissions
  Future<void> _requestLocationPermissions() async {
    try {
      // Request location permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.locationWhenInUse,
        Permission.locationAlways,
      ].request();

      print('📱 Location permission statuses: $statuses');
    } catch (e) {
      print('❌ Error requesting location permissions: $e');
    }
  }

  /// Get current location with enhanced accuracy
  Future<location_pkg.LocationData?> getCurrentLocation({
    int maxAttempts = 1,
    double requiredAccuracy = 50.0,
  }) async {
    try {
      if (!_isLocationEnabled) {
        print('❌ Location service not enabled');
        return null;
      }

      location_pkg.LocationData? bestLocation;
      double bestAccuracy = double.infinity;

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          print(
              '📍 Getting current location (attempt $attempt/$maxAttempts)...');

          // Try to get location with progressively longer timeouts
          final timeoutSeconds = 5 + (attempt * 2);
          location_pkg.LocationData locationData =
              await _location.getLocation().timeout(
            Duration(seconds: timeoutSeconds),
            onTimeout: () {
              throw TimeoutException('Location request timed out',
                  Duration(seconds: timeoutSeconds));
            },
          );

          final accuracy = locationData.accuracy ?? double.infinity;
          print(
              '📍 Attempt $attempt: Location ${locationData.latitude}, ${locationData.longitude} (accuracy: ${accuracy.toStringAsFixed(1)}m)');

          // Keep track of the best location
          if (accuracy < bestAccuracy) {
            bestLocation = locationData;
            bestAccuracy = accuracy;
          }

          // If we have good enough accuracy, return it
          if (accuracy <= requiredAccuracy) {
            _currentLocationData = locationData;
            print(
                '✅ Good GPS accuracy achieved: ${accuracy.toStringAsFixed(1)}m');
            return locationData;
          }

          // Wait between attempts (except for the last one)
          if (attempt < maxAttempts) {
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (attemptError) {
          print('⚠️ Attempt $attempt failed: $attemptError');
          if (attempt == maxAttempts) {
            // This was the last attempt, re-throw the error
            rethrow;
          }
        }
      }

      // Return the best location we got, even if it doesn't meet the accuracy requirement
      if (bestLocation != null) {
        _currentLocationData = bestLocation;
        print(
            '📍 Returning best available location: accuracy ${bestAccuracy.toStringAsFixed(1)}m');
        return bestLocation;
      }

      throw Exception('No location data obtained after $maxAttempts attempts');
    } catch (e) {
      print('❌ Error getting current location: $e');

      // For Huawei devices without Google Play Services, try fallback
      if (e.toString().contains('SERVICE_INVALID') ||
          e.toString().contains('Google Play Store')) {
        print('📱 Huawei device detected - Google Play Services not available');
        print('📍 Trying fallback location method...');

        final fallbackLocation = await _getFallbackLocation();
        if (fallbackLocation != null) {
          return fallbackLocation;
        }
        print('❌ Fallback location also failed');
      }

      // If timeout occurs, try to get last known location
      if (e.toString().contains('TimeoutException')) {
        print('⏰ Location timeout - trying last known location...');
        final lastKnownLocation = await _getLastKnownLocation();
        if (lastKnownLocation != null) {
          return lastKnownLocation;
        }
        print('❌ Last known location not available');
      }

      print(
          '❌ All location methods failed - returning null to require proper GPS');
      return null;
    }
  }

  /// Fallback location method for devices without Google Play Services
  Future<location_pkg.LocationData?> _getFallbackLocation() async {
    print('📍 Using fallback location method...');

    // Try to get last known location from storage first
    final lastKnownLocation = await _getLastKnownLocation();
    if (lastKnownLocation != null) {
      print('📍 Using last known location from storage');
      return lastKnownLocation;
    }

    // Try alternative location providers
    try {
      // Try network-based location as fallback
      final networkLocation = await _location.getLocation().timeout(
            const Duration(seconds: 3),
          );

      if (networkLocation.latitude != null &&
          networkLocation.longitude != null) {
        print('📍 Got network-based location as fallback');
        return networkLocation;
      }
    } catch (e) {
      print('⚠️ Network-based location also failed: $e');
    }

    // No fallback coordinates - return null to force proper GPS handling
    print(
        '❌ No valid location available - returning null to require proper GPS');
    return null;
  }

  /// Save last known location to local storage
  Future<void> _saveLastKnownLocation(
      location_pkg.LocationData locationData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationMap = {
        'latitude': locationData.latitude,
        'longitude': locationData.longitude,
        'accuracy': locationData.accuracy,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('last_known_location', json.encode(locationMap));
      print('💾 Last known location saved to storage');
    } catch (e) {
      print('❌ Error saving last known location: $e');
    }
  }

  /// Get last known location from local storage
  Future<location_pkg.LocationData?> _getLastKnownLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationString = prefs.getString('last_known_location');
      if (locationString != null) {
        final locationMap = json.decode(locationString);
        
        // Safe conversion helper for numeric values
        double? _safeToDouble(dynamic value) {
          if (value == null) return null;
          if (value is double) return value;
          if (value is int) return value.toDouble();
          if (value is String) return double.tryParse(value);
          return null;
        }
        
        // Validate that we have valid coordinates
        final latitude = _safeToDouble(locationMap['latitude']);
        final longitude = _safeToDouble(locationMap['longitude']);
        
        if (latitude == null || longitude == null) {
          print('❌ Invalid cached location data - clearing cache');
          await prefs.remove('last_known_location');
          return null;
        }
        
        return location_pkg.LocationData.fromMap({
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': _safeToDouble(locationMap['accuracy']),
          'time': locationMap['timestamp'],
          'altitude': 0.0,
          'speed': 0.0,
          'speed_accuracy': 0.0,
          'heading': 0.0,
          'isMock': true,
          'verticalAccuracy': 0.0,
          'headingAccuracy': 0.0,
          'elapsedRealtimeNanos': 0,
          'elapsedRealtimeUncertaintyNanos': 0,
          'satelliteNumber': 0,
          'provider': 'storage',
        });
      }
    } catch (e) {
      print('❌ Error getting last known location: $e');
      // Clear potentially corrupted cache data
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_known_location');
        print('🧹 Cleared corrupted location cache');
      } catch (clearError) {
        print('❌ Error clearing location cache: $clearError');
      }
    }
    return null;
  }

  /// Start continuous location tracking for a trip
  Future<bool> startTripTracking({
    required String tripId,
    required String driverId,
    required String tripRefNumber,
  }) async {
    try {
      if (!_isLocationEnabled) {
        print('❌ Location service not enabled');
        return false;
      }

      if (_isTracking) {
        print('⚠️ Location tracking already active');
        return true;
      }

      print('🚀 Starting trip location tracking for trip: $tripRefNumber');

      // Get initial location
      location_pkg.LocationData? initialLocation = await getCurrentLocation();
      if (initialLocation == null) {
        print('❌ Could not get initial location');
        return false;
      }

      // Save trip start location to database
      await _saveTripStartLocation(
        tripId: tripId,
        driverId: driverId,
        latitude: initialLocation.latitude ?? 0.0,
        longitude: initialLocation.longitude ?? 0.0,
      );

      // Start continuous tracking
      _isTracking = true;

      // Start location stream for real-time updates
      try {
        // Configure location settings first
        await _location.changeSettings(
          accuracy: location_pkg.LocationAccuracy.high,
          interval: _locationUpdateInterval.inMilliseconds,
          distanceFilter: _minDistanceForUpdate,
        );

        _locationStream = _location.onLocationChanged.listen(
          (location_pkg.LocationData locationData) {
            _onLocationUpdate(locationData, tripId, driverId);
          },
          onError: (error) {
            print('❌ Location stream error: $error');
            // If location stream fails, fall back to timer-based updates
            print('🔄 Falling back to timer-based location updates');
          },
        );
      } catch (e) {
        print('❌ Error setting up location stream: $e');
        print('🔄 Falling back to timer-based location updates only');
        // Don't set up the stream, just use the timer
      }

      // Also use timer as backup for regular updates
      _locationTimer = Timer.periodic(_locationUpdateInterval, (timer) async {
        if (_isTracking) {
          location_pkg.LocationData? locationData = await getCurrentLocation();
          if (locationData != null) {
            await _onLocationUpdate(locationData, tripId, driverId);
          }
        }
      });

      print('✅ Trip location tracking started successfully');
      return true;
    } catch (e) {
      print('❌ Error starting trip tracking: $e');
      return false;
    }
  }

  /// Stop location tracking
  Future<void> stopTripTracking({
    required String tripId,
    required String driverId,
  }) async {
    try {
      if (!_isTracking) {
        print('⚠️ Location tracking not active');
        return;
      }

      print('🛑 Stopping trip location tracking');

      // Get final location
      location_pkg.LocationData? finalLocation = await getCurrentLocation();
      if (finalLocation != null) {
        await _saveTripEndLocation(
          tripId: tripId,
          driverId: driverId,
          latitude: finalLocation.latitude ?? 0.0,
          longitude: finalLocation.longitude ?? 0.0,
        );
      }

      // Stop tracking
      _isTracking = false;
      _locationStream?.cancel();
      _locationTimer?.cancel();
      _locationStream = null;
      _locationTimer = null;

      print('✅ Trip location tracking stopped');
    } catch (e) {
      print('❌ Error stopping trip tracking: $e');
    }
  }

  /// Handle location updates
  Future<void> _onLocationUpdate(location_pkg.LocationData locationData,
      String tripId, String driverId) async {
    try {
      _currentLocationData = locationData;

      // Save location to local storage for fallback use
      await _saveLastKnownLocation(locationData);

      // Save location update to database
      await _saveLocationUpdate(
        tripId: tripId,
        driverId: driverId,
        latitude: locationData.latitude ?? 0.0,
        longitude: locationData.longitude ?? 0.0,
        accuracy: locationData.accuracy ?? 0.0,
        speed: locationData.speed ?? 0.0,
        heading: locationData.heading ?? 0.0,
        timestamp: DateTime.now(),
      );

      // Send real-time update
      await _sendRealtimeLocationUpdate(
        tripId: tripId,
        driverId: driverId,
        latitude: locationData.latitude ?? 0.0,
        longitude: locationData.longitude ?? 0.0,
      );

      print(
          '📍 Location update: ${locationData.latitude}, ${locationData.longitude}');
    } catch (e) {
      print('❌ Error handling location update: $e');
    }
  }

  /// Save trip start location to database
  Future<void> _saveTripStartLocation({
    required String tripId,
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final address = await _getAddressFromCoordinates(latitude, longitude);

      await Supabase.instance.client.from('trip_locations').insert({
        'trip_id': tripId,
        'driver_id': driverId,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'location_type': 'start',
        'timestamp': DateTime.now().toIso8601String(),
        'accuracy': 0.0,
        'speed': 0.0,
        'heading': 0.0,
      });

      print('✅ Trip start location saved to database');
    } catch (e) {
      print('❌ Error saving trip start location: $e');
    }
  }

  /// Save trip end location to database
  Future<void> _saveTripEndLocation({
    required String tripId,
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final address = await _getAddressFromCoordinates(latitude, longitude);

      await Supabase.instance.client.from('trip_locations').insert({
        'trip_id': tripId,
        'driver_id': driverId,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'location_type': 'end',
        'timestamp': DateTime.now().toIso8601String(),
        'accuracy': 0.0,
        'speed': 0.0,
        'heading': 0.0,
      });

      print('✅ Trip end location saved to database');
    } catch (e) {
      print('❌ Error saving trip end location: $e');
    }
  }

  /// Save location update to database
  Future<void> _saveLocationUpdate({
    required String tripId,
    required String driverId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required double heading,
    required DateTime timestamp,
  }) async {
    try {
      final address = await _getAddressFromCoordinates(latitude, longitude);

      await Supabase.instance.client.from('trip_locations').insert({
        'trip_id': tripId,
        'driver_id': driverId,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'location_type': 'tracking',
        'timestamp': timestamp.toIso8601String(),
        'accuracy': accuracy,
        'speed': speed,
        'heading': heading,
      });

      // Also update the trips table with current location (if columns exist)
      try {
        await Supabase.instance.client.from('trips').update({
          'current_latitude': latitude,
          'current_longitude': longitude,
          'last_location_update': DateTime.now().toIso8601String(),
        }).eq('id', tripId);
      } catch (e) {
        // If columns don't exist, just log it and continue
        print(
            '⚠️ Could not update trips table with location (columns may not exist): $e');
      }
    } catch (e) {
      print('❌ Error saving location update: $e');
    }
  }

  /// Send real-time location update via Supabase
  Future<void> _sendRealtimeLocationUpdate({
    required String tripId,
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      // For now, we'll just log the location update
      // TODO: Implement proper Supabase real-time broadcasting
      print('📍 Location update for trip $tripId: $latitude, $longitude');
    } catch (e) {
      print('❌ Error sending real-time location update: $e');
    }
  }

  /// Get address from coordinates
  Future<String> _getAddressFromCoordinates(
      double latitude, double longitude) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        return '${place.street}, ${place.locality}, ${place.administrativeArea}';
      }
      return 'Unknown Location';
    } catch (e) {
      print('❌ Error getting address: $e');
      return 'Unknown Location';
    }
  }

  /// Get distance between two points in meters
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // Simple distance calculation using Haversine formula
    const double earthRadius = 6371000; // meters

    double lat1Rad = lat1 * (pi / 180);
    double lat2Rad = lat2 * (pi / 180);
    double deltaLat = (lat2 - lat1) * (pi / 180);
    double deltaLon = (lon2 - lon1) * (pi / 180);

    double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(deltaLon / 2) * sin(deltaLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Check if location services are enabled
  Future<bool> checkLocationServices() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      print('❌ Location services are disabled');
      return false;
    }
    return true;
  }

  /// Request location permissions
  Future<bool> requestLocationPermissions() async {
    try {
      location_pkg.PermissionStatus permission =
          await _location.requestPermission();
      return permission == location_pkg.PermissionStatus.granted ||
          permission == location_pkg.PermissionStatus.grantedLimited;
    } catch (e) {
      print('❌ Error requesting location permissions: $e');
      return false;
    }
  }

  /// Dispose resources safely
  void dispose() {
    try {
      _locationStream?.cancel();
      _locationStream = null;
    } catch (e) {
      print('⚠️ Error cancelling location stream: $e');
    }

    try {
      _locationTimer?.cancel();
      _locationTimer = null;
    } catch (e) {
      print('⚠️ Error cancelling location timer: $e');
    }

    try {
      _locationChannel?.unsubscribe();
      _locationChannel = null;
    } catch (e) {
      print('⚠️ Error unsubscribing location channel: $e');
    }

    _isTracking = false;
    print('🧹 Location service disposed safely');
  }

  /// Safe location getter with null checks
  Future<location_pkg.LocationData?> getCurrentLocationSafely() async {
    try {
      if (!_isLocationEnabled) {
        print('⚠️ Location service not enabled, attempting to initialize...');
        final initialized = await initialize();
        if (!initialized) {
          print('❌ Could not initialize location service');
          return null;
        }
      }

      return await _location.getLocation().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⏰ Location request timed out');
          throw TimeoutException(
              'Location request timed out', const Duration(seconds: 10));
        },
      );
    } catch (e) {
      print('❌ Error getting current location safely: $e');
      return null;
    }
  }

  /// Clear location cache to resolve type casting issues
  Future<void> clearLocationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_known_location');
      print('🧹 Location cache cleared successfully');
    } catch (e) {
      print('❌ Error clearing location cache: $e');
    }
  }
}
