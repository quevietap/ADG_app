import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class GoogleMapsService {
  static final GoogleMapsService _instance = GoogleMapsService._internal();
  factory GoogleMapsService() => _instance;
  GoogleMapsService._internal();

  // Google Maps API Configuration
  static const String _apiKey =
      'YOUR_GOOGLE_MAPS_API_KEY'; // Replace with your API key
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api';

  // Performance optimization
  static const Duration _locationUpdateInterval = Duration(seconds: 5);
  static const Duration _geocodingCacheTimeout = Duration(hours: 24);

  // Cache for geocoding results
  final Map<String, _CachedGeocode> _geocodingCache = {};
  final Map<String, List<LatLng>> _routeCache = {};

  /// Get current location with high accuracy
  Future<LatLng?> getCurrentLocation() async {
    try {
      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      // Get current position with high accuracy
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('❌ Error getting current location: $e');
      return null;
    }
  }

  /// Geocode address to coordinates (like Google Maps)
  Future<LatLng?> geocodeAddress(String address) async {
    try {
      // Check cache first
      if (_geocodingCache.containsKey(address)) {
        final cached = _geocodingCache[address]!;
        if (DateTime.now().difference(cached.timestamp) <
            _geocodingCacheTimeout) {
          return cached.coordinates;
        } else {
          _geocodingCache.remove(address);
        }
      }

      // Use Google Geocoding API for high accuracy
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/geocode/json?address=${Uri.encodeComponent(address)}&key=$_apiKey'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          final coordinates = LatLng(location['lat'], location['lng']);

          // Cache the result
          _geocodingCache[address] = _CachedGeocode(
            coordinates: coordinates,
            timestamp: DateTime.now(),
          );

          return coordinates;
        }
      }

      // Fallback to local geocoding
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final coordinates =
            LatLng(locations.first.latitude, locations.first.longitude);

        // Cache the result
        _geocodingCache[address] = _CachedGeocode(
          coordinates: coordinates,
          timestamp: DateTime.now(),
        );

        return coordinates;
      }

      return null;
    } catch (e) {
      print('❌ Error geocoding address: $e');
      return null;
    }
  }

  /// Reverse geocode coordinates to address
  Future<String?> reverseGeocode(LatLng coordinates) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        coordinates.latitude,
        coordinates.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        return '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
      }

      return null;
    } catch (e) {
      print('❌ Error reverse geocoding: $e');
      return null;
    }
  }

  /// Get optimized route between two points (like Google Maps)
  Future<List<LatLng>> getRoute(
    LatLng origin,
    LatLng destination, {
    List<LatLng>? waypoints,
    String mode = 'driving',
  }) async {
    try {
      final routeKey =
          '${origin.latitude},${origin.longitude}_${destination.latitude},${destination.longitude}_$mode';

      // Check cache first
      if (_routeCache.containsKey(routeKey)) {
        return _routeCache[routeKey]!;
      }

      // Build waypoints string
      String waypointsStr = '';
      if (waypoints != null && waypoints.isNotEmpty) {
        waypointsStr =
            '&waypoints=${waypoints.map((wp) => '${wp.latitude},${wp.longitude}').join('|')}';
      }

      // Use Google Directions API for accurate routing
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&mode=$mode$waypointsStr&key=$_apiKey'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polyline = route['overview_polyline']['points'];
          final points = _decodePolyline(polyline);

          // Cache the route
          _routeCache[routeKey] = points;

          return points;
        }
      }

      // Fallback to direct line
      final fallbackRoute = [origin, destination];
      _routeCache[routeKey] = fallbackRoute;
      return fallbackRoute;
    } catch (e) {
      print('❌ Error getting route: $e');
      return [origin, destination];
    }
  }

  /// Calculate distance between two points
  double calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  /// Calculate bearing between two points
  double calculateBearing(LatLng point1, LatLng point2) {
    return Geolocator.bearingBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  /// Get estimated travel time
  Future<Duration?> getEstimatedTravelTime(
      LatLng origin, LatLng destination, String mode) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/distancematrix/json?origins=${origin.latitude},${origin.longitude}&destinations=${destination.latitude},${destination.longitude}&mode=$mode&key=$_apiKey'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['rows'].isNotEmpty) {
          final element = data['rows'][0]['elements'][0];
          if (element['status'] == 'OK') {
            final durationText = element['duration']['text'];
            return _parseDuration(durationText);
          }
        }
      }

      return null;
    } catch (e) {
      print('❌ Error getting travel time: $e');
      return null;
    }
  }

  /// Optimize route for multiple waypoints
  Future<List<LatLng>> optimizeRoute(List<LatLng> waypoints) async {
    try {
      if (waypoints.length < 3) return waypoints;

      // Use Google Directions API with optimize:true
      final waypointsStr =
          waypoints.map((wp) => '${wp.latitude},${wp.longitude}').join('|');

      final response = await http.get(
        Uri.parse(
            '$_baseUrl/directions/json?origin=${waypoints.first.latitude},${waypoints.first.longitude}&destination=${waypoints.last.latitude},${waypoints.last.longitude}&waypoints=optimize:true|$waypointsStr&key=$_apiKey'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polyline = route['overview_polyline']['points'];
          return _decodePolyline(polyline);
        }
      }

      return waypoints;
    } catch (e) {
      print('❌ Error optimizing route: $e');
      return waypoints;
    }
  }

  /// Clear cache to free memory
  void clearCache() {
    _geocodingCache.clear();
    _routeCache.clear();
  }

  /// Get cache statistics
  Map<String, int> getCacheStats() {
    return {
      'geocoding_cache_size': _geocodingCache.length,
      'route_cache_size': _routeCache.length,
    };
  }

  // Helper methods
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      final p = LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble());
      poly.add(p);
    }
    return poly;
  }

  Duration? _parseDuration(String durationText) {
    try {
      // Parse "1 hour 30 mins" or "45 mins" format
      int hours = 0;
      int minutes = 0;

      if (durationText.contains('hour')) {
        final hourMatch = RegExp(r'(\d+)\s*hour').firstMatch(durationText);
        if (hourMatch != null) {
          hours = int.parse(hourMatch.group(1)!);
        }
      }

      if (durationText.contains('min')) {
        final minMatch = RegExp(r'(\d+)\s*min').firstMatch(durationText);
        if (minMatch != null) {
          minutes = int.parse(minMatch.group(1)!);
        }
      }

      return Duration(hours: hours, minutes: minutes);
    } catch (e) {
      return null;
    }
  }
}

class _CachedGeocode {
  final LatLng coordinates;
  final DateTime timestamp;

  _CachedGeocode({
    required this.coordinates,
    required this.timestamp,
  });
}

// High-performance location tracking service
class OptimizedLocationTracker {
  static final OptimizedLocationTracker _instance =
      OptimizedLocationTracker._internal();
  factory OptimizedLocationTracker() => _instance;
  OptimizedLocationTracker._internal();

  final GoogleMapsService _mapsService = GoogleMapsService();
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionSubscription;

  LatLng? _lastKnownLocation;
  final List<LatLng> _locationHistory = [];
  static const int _maxHistorySize = 1000;

  /// Start continuous location tracking with optimization
  Future<void> startTracking({
    Duration interval = const Duration(seconds: 5),
    LocationAccuracy accuracy = LocationAccuracy.high,
    Function(LatLng)? onLocationUpdate,
  }) async {
    try {
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      // Get initial location
      _lastKnownLocation = await _mapsService.getCurrentLocation();
      if (_lastKnownLocation != null) {
        _addToHistory(_lastKnownLocation!);
        onLocationUpdate?.call(_lastKnownLocation!);
      }

      // Start continuous tracking with optimized settings
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: 10, // Only update if moved 10+ meters
          timeLimit: const Duration(seconds: 10),
        ),
      ).listen((Position position) {
        final newLocation = LatLng(position.latitude, position.longitude);

        // Only update if location changed significantly
        if (_lastKnownLocation == null ||
            _mapsService.calculateDistance(_lastKnownLocation!, newLocation) >
                5) {
          _lastKnownLocation = newLocation;
          _addToHistory(newLocation);
          onLocationUpdate?.call(newLocation);
        }
      });
    } catch (e) {
      print('❌ Error starting location tracking: $e');
    }
  }

  /// Stop location tracking
  void stopTracking() {
    _positionSubscription?.cancel();
    _locationTimer?.cancel();
  }

  /// Get current location
  LatLng? getCurrentLocation() => _lastKnownLocation;

  /// Get location history
  List<LatLng> getLocationHistory() => List.unmodifiable(_locationHistory);

  /// Get optimized route from history
  List<LatLng> getOptimizedRoute() {
    if (_locationHistory.length < 3) return _locationHistory;

    // Remove duplicate points and smooth the route
    final optimized = <LatLng>[];
    for (int i = 0; i < _locationHistory.length; i++) {
      if (i == 0 ||
          i == _locationHistory.length - 1 ||
          _mapsService.calculateDistance(
                  _locationHistory[i], _locationHistory[i - 1]) >
              20) {
        optimized.add(_locationHistory[i]);
      }
    }

    return optimized;
  }

  /// Clear location history
  void clearHistory() {
    _locationHistory.clear();
  }

  void _addToHistory(LatLng location) {
    _locationHistory.add(location);
    if (_locationHistory.length > _maxHistorySize) {
      _locationHistory.removeAt(0);
    }
  }
}
