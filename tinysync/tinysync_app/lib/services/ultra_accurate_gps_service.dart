import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Ultra-accurate GPS service for driver safety
/// Provides the highest possible location accuracy with multiple validation layers
class UltraAccurateGPSService {
  static final UltraAccurateGPSService _instance = UltraAccurateGPSService._internal();
  factory UltraAccurateGPSService() => _instance;
  UltraAccurateGPSService._internal();

  // GPS accuracy thresholds for driver safety
  static const double _excellentAccuracy = 5.0;    // 5 meters or better
  static const double _goodAccuracy = 10.0;        // 10 meters or better
  static const double _acceptableAccuracy = 20.0;  // 20 meters or better
  static const double _minimumAccuracy = 50.0;     // 50 meters maximum

  // Location tracking state
  Position? _lastKnownPosition;
  Timer? _accuracyTimer;
  StreamSubscription<Position>? _positionStream;
  
  // Accuracy statistics
  double _averageAccuracy = double.infinity;
  int _accuracyReadings = 0;
  final List<double> _accuracyHistory = [];

  /// Get ultra-accurate current location
  Future<Position?> getUltraAccurateLocation({
    Duration timeout = const Duration(seconds: 15),
    bool requireHighAccuracy = true,
  }) async {
    try {
      print('🎯 Getting ultra-accurate location...');

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions permanently denied');
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

      // Validate accuracy requirements
      if (requireHighAccuracy && averageAccuracy > _acceptableAccuracy) {
        print('❌ Location accuracy too low: ${averageAccuracy.toStringAsFixed(1)}m (required: ≤${_acceptableAccuracy}m)');
        return null;
      }

      // Update accuracy statistics
      _updateAccuracyStatistics(averageAccuracy);

      // Log accuracy level
      _logAccuracyLevel(averageAccuracy);

      _lastKnownPosition = averagePosition;
      return averagePosition;

    } catch (e) {
      print('❌ Error getting ultra-accurate location: $e');
      return _lastKnownPosition; // Return last known position as fallback
    }
  }

  /// Start continuous high-accuracy tracking
  Future<void> startContinuousTracking({
    Duration interval = const Duration(seconds: 3),
    Function(Position)? onLocationUpdate,
    Function(double)? onAccuracyUpdate,
  }) async {
    try {
      print('🔄 Starting continuous high-accuracy tracking...');

      // Stop existing tracking
      stopTracking();

      // Get initial position
      final initialPosition = await getUltraAccurateLocation();
      if (initialPosition != null) {
        onLocationUpdate?.call(initialPosition);
        onAccuracyUpdate?.call(initialPosition.accuracy);
      }

      // Start continuous tracking with optimized settings
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5, // Update every 5 meters
          timeLimit: Duration(seconds: 10),
        ),
      ).listen((Position position) {
        // Validate accuracy before updating
        if (position.accuracy <= _minimumAccuracy) {
          _lastKnownPosition = position;
          _updateAccuracyStatistics(position.accuracy);
          
          onLocationUpdate?.call(position);
          onAccuracyUpdate?.call(position.accuracy);
          
          _logAccuracyLevel(position.accuracy);
        } else {
          print('⚠️ Rejecting low-accuracy update: ${position.accuracy.toStringAsFixed(1)}m');
        }
      });

      // Start accuracy monitoring
      _startAccuracyMonitoring(onAccuracyUpdate);

    } catch (e) {
      print('❌ Error starting continuous tracking: $e');
    }
  }

  /// Stop continuous tracking
  void stopTracking() {
    _positionStream?.cancel();
    _accuracyTimer?.cancel();
    print('🛑 Stopped continuous tracking');
  }

  /// Get current accuracy statistics
  Map<String, dynamic> getAccuracyStatistics() {
    return {
      'current_accuracy': _lastKnownPosition?.accuracy ?? double.infinity,
      'average_accuracy': _averageAccuracy,
      'readings_count': _accuracyReadings,
      'accuracy_level': _getAccuracyLevel(_averageAccuracy),
      'accuracy_history': List<double>.from(_accuracyHistory),
    };
  }

  /// Get accuracy level description
  String getAccuracyLevel(double accuracy) {
    return _getAccuracyLevel(accuracy);
  }

  /// Calculate average position from multiple readings
  Position _calculateAveragePosition(List<Position> readings) {
    if (readings.isEmpty) throw Exception('No readings available');

    double totalLat = 0;
    double totalLng = 0;
    double totalAccuracy = 0;

    for (Position reading in readings) {
      totalLat += reading.latitude;
      totalLng += reading.longitude;
      totalAccuracy += reading.accuracy;
    }

    final avgLat = totalLat / readings.length;
    final avgLng = totalLng / readings.length;
    final avgAccuracy = totalAccuracy / readings.length;

    // Create a new Position with averaged values
    return Position(
      latitude: avgLat,
      longitude: avgLng,
      timestamp: DateTime.now(),
      accuracy: avgAccuracy,
      altitude: readings.first.altitude,
      heading: readings.first.heading,
      speed: readings.first.speed,
      speedAccuracy: readings.first.speedAccuracy,
      altitudeAccuracy: readings.first.altitudeAccuracy,
      headingAccuracy: readings.first.headingAccuracy,
    );
  }

  /// Calculate average accuracy from multiple readings
  double _calculateAverageAccuracy(List<Position> readings) {
    if (readings.isEmpty) return double.infinity;
    
    double totalAccuracy = 0;
    for (Position reading in readings) {
      totalAccuracy += reading.accuracy;
    }
    return totalAccuracy / readings.length;
  }

  /// Update accuracy statistics
  void _updateAccuracyStatistics(double accuracy) {
    _accuracyReadings++;
    _accuracyHistory.add(accuracy);
    
    // Keep only last 100 readings
    if (_accuracyHistory.length > 100) {
      _accuracyHistory.removeAt(0);
    }
    
    // Calculate running average
    double total = 0;
    for (double acc in _accuracyHistory) {
      total += acc;
    }
    _averageAccuracy = total / _accuracyHistory.length;
  }

  /// Start accuracy monitoring
  void _startAccuracyMonitoring(Function(double)? onAccuracyUpdate) {
    _accuracyTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_lastKnownPosition != null) {
        onAccuracyUpdate?.call(_lastKnownPosition!.accuracy);
      }
    });
  }

  /// Log accuracy level with emoji indicators
  void _logAccuracyLevel(double accuracy) {
    final level = _getAccuracyLevel(accuracy);
    final emoji = _getAccuracyEmoji(accuracy);
    
    print('$emoji GPS Accuracy: ${accuracy.toStringAsFixed(1)}m - $level');
  }

  /// Get accuracy level description
  String _getAccuracyLevel(double accuracy) {
    if (accuracy <= _excellentAccuracy) return 'Excellent';
    if (accuracy <= _goodAccuracy) return 'Good';
    if (accuracy <= _acceptableAccuracy) return 'Acceptable';
    if (accuracy <= _minimumAccuracy) return 'Poor';
    return 'Unreliable';
  }

  /// Get accuracy emoji indicator
  String _getAccuracyEmoji(double accuracy) {
    if (accuracy <= _excellentAccuracy) return '🎯';
    if (accuracy <= _goodAccuracy) return '✅';
    if (accuracy <= _acceptableAccuracy) return '⚠️';
    if (accuracy <= _minimumAccuracy) return '❌';
    return '🚨';
  }

  /// Get location with address resolution
  Future<Map<String, dynamic>?> getLocationWithAddress() async {
    try {
      final position = await getUltraAccurateLocation();
      if (position == null) return null;

      // Resolve address
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      String address = 'Unknown location';
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        address = '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
      }

      return {
        'position': position,
        'address': address,
        'accuracy': position.accuracy,
        'accuracy_level': _getAccuracyLevel(position.accuracy),
        'timestamp': position.timestamp,
      };
    } catch (e) {
      print('❌ Error getting location with address: $e');
      return null;
    }
  }

  /// Check if GPS accuracy is sufficient for driver safety
  bool isAccuracySufficientForDriverSafety(double accuracy) {
    return accuracy <= _acceptableAccuracy;
  }

  /// Get GPS status and recommendations
  Map<String, dynamic> getGPSStatus() {
    final currentAccuracy = _lastKnownPosition?.accuracy ?? double.infinity;
    
    return {
      'is_tracking': _positionStream != null,
      'current_accuracy': currentAccuracy,
      'accuracy_level': _getAccuracyLevel(currentAccuracy),
      'is_sufficient_for_driving': isAccuracySufficientForDriverSafety(currentAccuracy),
      'recommendations': _getGPSRecommendations(currentAccuracy),
      'statistics': getAccuracyStatistics(),
    };
  }

  /// Get GPS recommendations based on current accuracy
  List<String> _getGPSRecommendations(double accuracy) {
    final recommendations = <String>[];
    
    if (accuracy > _minimumAccuracy) {
      recommendations.add('Move to an open area for better GPS signal');
      recommendations.add('Check if GPS is enabled on your device');
      recommendations.add('Ensure you have a clear view of the sky');
    } else if (accuracy > _acceptableAccuracy) {
      recommendations.add('GPS accuracy is acceptable but could be better');
      recommendations.add('Consider moving to a more open area');
    } else if (accuracy <= _excellentAccuracy) {
      recommendations.add('GPS accuracy is excellent for driver safety');
    }
    
    return recommendations;
  }
}
