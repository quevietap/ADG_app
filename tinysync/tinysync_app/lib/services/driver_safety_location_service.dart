import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'philippine_geocoding_service.dart';

/// Driver Safety Location Service
/// Provides ultra-accurate destination validation and safety checks for drivers
class DriverSafetyLocationService {
  static final DriverSafetyLocationService _instance = DriverSafetyLocationService._internal();
  factory DriverSafetyLocationService() => _instance;
  DriverSafetyLocationService._internal();

  // Safety thresholds
  static const double _excellentAccuracy = 5.0;    // 5 meters or better
  static const double _goodAccuracy = 10.0;        // 10 meters or better
  static const double _acceptableAccuracy = 20.0;  // 20 meters or better
  static const double _minimumAccuracy = 50.0;     // 50 meters maximum for safety

  // Destination validation
  static const double _destinationProximityThreshold = 100.0; // 100 meters to consider "arrived"
  static const double _safetyZoneRadius = 200.0; // 200 meters safety zone around destination

  // Known Philippine landmarks with precise coordinates for safety
  static const Map<String, Map<String, dynamic>> _knownLandmarks = {
    // Your specific locations
    'LAMUAN CREEK': {
      'coordinates': {'lat': 14.6504335, 'lng': 121.0991006},
      'safety_zone': 150.0,
      'description': 'Lamuan Creek, Marikina City',
      'landmarks': ['Near Marikina River', 'Close to BDO Branch'],
    },
    'BDO MARIKINA LAMUAN BRANCH': {
      'coordinates': {'lat': 14.6504335, 'lng': 121.0991006},
      'safety_zone': 100.0,
      'description': 'BDO Bank Branch, Lamuan, Marikina',
      'landmarks': ['BDO Bank', 'Near Lamuan Creek'],
    },
    'FEU ROOSEVELT': {
      'coordinates': {'lat': 14.6505, 'lng': 121.0990},
      'safety_zone': 200.0,
      'description': 'Far Eastern University Roosevelt Campus',
      'landmarks': ['FEU Campus', 'University Area'],
    },
    
    // Major Philippine landmarks for safety
    'SM MALL OF ASIA': {
      'coordinates': {'lat': 14.5350, 'lng': 120.9819},
      'safety_zone': 300.0,
      'description': 'SM Mall of Asia, Pasay City',
      'landmarks': ['Large Shopping Mall', 'Near Manila Bay'],
    },
    'UP DILIMAN': {
      'coordinates': {'lat': 14.6539, 'lng': 121.0722},
      'safety_zone': 500.0,
      'description': 'University of the Philippines Diliman',
      'landmarks': ['UP Campus', 'Academic District'],
    },
    'MAKATI CBD': {
      'coordinates': {'lat': 14.5547, 'lng': 121.0244},
      'safety_zone': 400.0,
      'description': 'Makati Central Business District',
      'landmarks': ['Business District', 'High-rise Buildings'],
    },
    'NAIA TERMINAL 3': {
      'coordinates': {'lat': 14.5995, 'lng': 121.0972},
      'safety_zone': 200.0,
      'description': 'Ninoy Aquino International Airport Terminal 3',
      'landmarks': ['Airport Terminal', 'Aviation Area'],
    },
  };

  /// Get ultra-accurate current location for driver safety
  Future<Map<String, dynamic>?> getSafeCurrentLocation({
    Duration timeout = const Duration(seconds: 15),
    bool requireHighAccuracy = true,
  }) async {
    try {
      print('🛡️ Getting safe current location for driver...');

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied - required for driver safety');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions permanently denied - cannot ensure driver safety');
      }

      // Get multiple location readings for accuracy validation
      final List<Position> readings = [];
      
      // First reading with best accuracy
      Position firstReading = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: timeout,
      );
      readings.add(firstReading);

      // Get additional readings for accuracy averaging
      for (int i = 0; i < 2; i++) {
        try {
          Position reading = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          );
          readings.add(reading);
        } catch (e) {
          print('⚠️ Additional reading $i failed: $e');
        }
      }

      // Calculate average position and accuracy
      final averagePosition = _calculateAveragePosition(readings);
      final averageAccuracy = _calculateAverageAccuracy(readings);

      // Validate accuracy requirements for driver safety
      if (requireHighAccuracy && averageAccuracy > _acceptableAccuracy) {
        print('🚨 Location accuracy too low for driver safety: ${averageAccuracy.toStringAsFixed(1)}m (required: ≤${_acceptableAccuracy}m)');
        return {
          'position': averagePosition,
          'accuracy': averageAccuracy,
          'accuracy_level': _getAccuracyLevel(averageAccuracy),
          'is_safe_for_driving': false,
          'safety_warning': 'GPS accuracy too low for safe navigation',
          'recommendation': 'Move to open area or wait for better GPS signal',
        };
      }

      // Get address for safety verification
      String address = await _getAddressFromCoordinates(
        averagePosition.latitude,
        averagePosition.longitude,
      );

      return {
        'position': averagePosition,
        'address': address,
        'accuracy': averageAccuracy,
        'accuracy_level': _getAccuracyLevel(averageAccuracy),
        'is_safe_for_driving': true,
        'safety_warning': null,
        'recommendation': null,
        'timestamp': DateTime.now(),
      };

    } catch (e) {
      print('❌ Error getting safe current location: $e');
      return null;
    }
  }

  /// Validate destination accuracy and safety
  Future<Map<String, dynamic>> validateDestinationSafety({
    required String destination,
    required double currentLat,
    required double currentLng,
  }) async {
    try {
      print('🛡️ Validating destination safety for: $destination');

      // First, try to find in known landmarks
      final knownLandmark = _findKnownLandmark(destination);
      if (knownLandmark != null) {
        return _validateKnownDestination(
          destination: destination,
          landmark: knownLandmark,
          currentLat: currentLat,
          currentLng: currentLng,
        );
      }

      // Use Philippine geocoding service for better accuracy
      final philippineService = PhilippineGeocodingService();
      final coordinates = await philippineService.geocodePhilippineAddress(destination);
      
      if (coordinates != null) {
        return _validateKnownDestination(
          destination: destination,
          landmark: {
            'coordinates': {
              'lat': coordinates.latitude,
              'lng': coordinates.longitude,
            },
            'description': destination,
            'safety_zone': _destinationProximityThreshold,
          },
          currentLat: currentLat,
          currentLng: currentLng,
        );
      }

      // If Philippine geocoding fails, use original geocoding
      return await _validateGeocodedDestination(
        destination: destination,
        currentLat: currentLat,
        currentLng: currentLng,
      );

    } catch (e) {
      print('❌ Error validating destination safety: $e');
      return {
        'is_safe': false,
        'warning': 'Unable to validate destination safety',
        'recommendation': 'Contact operator for manual verification',
        'destination_coordinates': null,
        'distance_to_destination': null,
        'estimated_arrival': null,
      };
    }
  }

  /// Check if driver has arrived at destination safely
  Future<Map<String, dynamic>> checkArrivalSafety({
    required String destination,
    required double currentLat,
    required double currentLng,
  }) async {
    try {
      print('🎯 Checking arrival safety for: $destination');

      // Get destination coordinates
      final destinationValidation = await validateDestinationSafety(
        destination: destination,
        currentLat: currentLat,
        currentLng: currentLng,
      );

      if (!destinationValidation['is_safe']) {
        return {
          'has_arrived': false,
          'safety_status': 'destination_unsafe',
          'warning': destinationValidation['warning'],
          'distance_to_destination': destinationValidation['distance_to_destination'],
        };
      }

      final destLat = destinationValidation['destination_coordinates']['lat'];
      final destLng = destinationValidation['destination_coordinates']['lng'];
      final safetyZone = destinationValidation['safety_zone'] ?? _destinationProximityThreshold;

      // Calculate distance to destination
      final distance = Geolocator.distanceBetween(
        currentLat, currentLng, destLat, destLng,
      );

      // Check if within safety zone
      final hasArrived = distance <= safetyZone;
      final safetyStatus = _getArrivalSafetyStatus(distance, safetyZone);

      return {
        'has_arrived': hasArrived,
        'safety_status': safetyStatus,
        'distance_to_destination': distance,
        'safety_zone_radius': safetyZone,
        'destination_address': destinationValidation['destination_address'],
        'current_address': await _getAddressFromCoordinates(currentLat, currentLng),
        'warning': hasArrived ? null : 'Not yet at destination',
        'recommendation': _getArrivalRecommendation(distance, safetyZone),
      };

    } catch (e) {
      print('❌ Error checking arrival safety: $e');
      return {
        'has_arrived': false,
        'safety_status': 'error',
        'warning': 'Unable to verify arrival safety',
        'recommendation': 'Contact operator for manual verification',
      };
    }
  }

  /// Get route safety assessment
  Future<Map<String, dynamic>> assessRouteSafety({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      print('🛣️ Assessing route safety...');

      // Calculate total distance
      final totalDistance = Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
      
      // Get route using OSRM for safety analysis
      final route = await _getSafeRoute(startLat, startLng, endLat, endLng);
      
      // Analyze route safety
      final safetyAnalysis = _analyzeRouteSafety(route, totalDistance);
      
      return {
        'total_distance': totalDistance,
        'route_points': route.length,
        'estimated_duration': _estimateTravelTime(totalDistance),
        'safety_level': safetyAnalysis['safety_level'],
        'safety_warnings': safetyAnalysis['warnings'],
        'recommendations': safetyAnalysis['recommendations'],
        'route_coordinates': route,
      };

    } catch (e) {
      print('❌ Error assessing route safety: $e');
      return {
        'total_distance': null,
        'safety_level': 'unknown',
        'safety_warnings': ['Unable to assess route safety'],
        'recommendations': ['Use caution and follow traffic rules'],
      };
    }
  }

  // Helper methods

  Position _calculateAveragePosition(List<Position> readings) {
    double totalLat = 0, totalLng = 0;
    for (Position reading in readings) {
      totalLat += reading.latitude;
      totalLng += reading.longitude;
    }
    return Position(
      latitude: totalLat / readings.length,
      longitude: totalLng / readings.length,
      timestamp: DateTime.now(),
      accuracy: _calculateAverageAccuracy(readings),
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
  }

  double _calculateAverageAccuracy(List<Position> readings) {
    double totalAccuracy = 0;
    for (Position reading in readings) {
      totalAccuracy += reading.accuracy;
    }
    return totalAccuracy / readings.length;
  }

  String _getAccuracyLevel(double accuracy) {
    if (accuracy <= _excellentAccuracy) return 'Excellent';
    if (accuracy <= _goodAccuracy) return 'Good';
    if (accuracy <= _acceptableAccuracy) return 'Acceptable';
    if (accuracy <= _minimumAccuracy) return 'Poor';
    return 'Unreliable';
  }

  Future<String> _getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        return '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
      }
    } catch (e) {
      print('⚠️ Error getting address: $e');
    }
    return 'Unknown location';
  }

  Map<String, dynamic>? _findKnownLandmark(String destination) {
    final normalizedDest = destination.toUpperCase().trim();
    
    // Direct match
    if (_knownLandmarks.containsKey(normalizedDest)) {
      return _knownLandmarks[normalizedDest];
    }
    
    // Partial match
    for (String landmark in _knownLandmarks.keys) {
      if (normalizedDest.contains(landmark) || landmark.contains(normalizedDest)) {
        return _knownLandmarks[landmark];
      }
    }
    
    return null;
  }

  Map<String, dynamic> _validateKnownDestination({
    required String destination,
    required Map<String, dynamic> landmark,
    required double currentLat,
    required double currentLng,
  }) {
    final destLat = landmark['coordinates']['lat'];
    final destLng = landmark['coordinates']['lng'];
    final safetyZone = landmark['safety_zone'] ?? _destinationProximityThreshold;
    
    final distance = Geolocator.distanceBetween(
      currentLat, currentLng, destLat, destLng,
    );

    return {
      'is_safe': true,
      'destination_coordinates': {'lat': destLat, 'lng': destLng},
      'destination_address': landmark['description'],
      'distance_to_destination': distance,
      'safety_zone': safetyZone,
      'estimated_arrival': _estimateArrivalTime(distance),
      'landmarks': landmark['landmarks'],
      'warning': null,
      'recommendation': 'Proceed to destination safely',
    };
  }

  Future<Map<String, dynamic>> _validateGeocodedDestination({
    required String destination,
    required double currentLat,
    required double currentLng,
  }) async {
    try {
      List<Location> locations = await locationFromAddress(destination);
      if (locations.isEmpty) {
        return {
          'is_safe': false,
          'warning': 'Destination not found',
          'recommendation': 'Verify destination address with operator',
          'destination_coordinates': null,
          'distance_to_destination': null,
          'estimated_arrival': null,
        };
      }

      final destLat = locations.first.latitude;
      final destLng = locations.first.longitude;
      final distance = Geolocator.distanceBetween(
        currentLat, currentLng, destLat, destLng,
      );

      return {
        'is_safe': true,
        'destination_coordinates': {'lat': destLat, 'lng': destLng},
        'destination_address': destination,
        'distance_to_destination': distance,
        'safety_zone': _destinationProximityThreshold,
        'estimated_arrival': _estimateArrivalTime(distance),
        'warning': null,
        'recommendation': 'Proceed to destination safely',
      };

    } catch (e) {
      return {
        'is_safe': false,
        'warning': 'Unable to validate destination',
        'recommendation': 'Contact operator for manual verification',
        'destination_coordinates': null,
        'distance_to_destination': null,
        'estimated_arrival': null,
      };
    }
  }

  String _getArrivalSafetyStatus(double distance, double safetyZone) {
    if (distance <= safetyZone * 0.5) return 'excellent';
    if (distance <= safetyZone) return 'good';
    if (distance <= safetyZone * 1.5) return 'approaching';
    return 'far';
  }

  String _getArrivalRecommendation(double distance, double safetyZone) {
    if (distance <= safetyZone * 0.5) {
      return 'You have arrived at destination safely';
    } else if (distance <= safetyZone) {
      return 'You are at the destination area';
    } else if (distance <= safetyZone * 1.5) {
      return 'Approaching destination - slow down and look for landmarks';
    } else {
      return 'Continue following route to destination';
    }
  }

  Future<List<List<double>>> _getSafeRoute(double startLat, double startLng, double endLat, double endLng) async {
    try {
      final url = 'http://router.project-osrm.org/route/v1/driving/'
          '$startLng,$startLat;$endLng,$endLat'
          '?overview=full&geometries=geojson';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coordinates = data['routes'][0]['geometry']['coordinates'] as List;
        return coordinates.map((coord) => [coord[1] as double, coord[0] as double]).toList();
      }
    } catch (e) {
      print('⚠️ Error getting route: $e');
    }
    
    // Fallback to direct route
    return [[startLat, startLng], [endLat, endLng]];
  }

  Map<String, dynamic> _analyzeRouteSafety(List<List<double>> route, double totalDistance) {
    final warnings = <String>[];
    final recommendations = <String>[];

    // Analyze route length
    if (totalDistance > 50) { // 50km
      warnings.add('Long distance trip - ensure adequate rest');
      recommendations.add('Take breaks every 2 hours');
    }

    // Analyze route complexity
    if (route.length > 100) {
      warnings.add('Complex route with many turns');
      recommendations.add('Pay extra attention to navigation');
    }

    // Determine safety level
    String safetyLevel = 'safe';
    if (warnings.isNotEmpty) {
      safetyLevel = warnings.length > 2 ? 'caution' : 'moderate';
    }

    return {
      'safety_level': safetyLevel,
      'warnings': warnings,
      'recommendations': recommendations,
    };
  }

  Duration _estimateTravelTime(double distanceKm) {
    // Assume average speed of 30 km/h in urban areas
    final hours = distanceKm / 30;
    return Duration(minutes: (hours * 60).round());
  }

  DateTime _estimateArrivalTime(double distanceKm) {
    final travelTime = _estimateTravelTime(distanceKm);
    return DateTime.now().add(travelTime);
  }
}
