import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:location/location.dart' as location_pkg;
import 'package:geocoding/geocoding.dart' hide Location;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/geocoding_provider.dart';
import '../services/philippine_geocoding_provider.dart';

class BeautifulLiveTrackingMap extends StatefulWidget {
  final Map<String, dynamic> trip;
  final String driverId;
  final double height;
  final Function(double)? onProgressUpdate;
  final Function(String)? onLocationUpdate;
  final Function(double)? onDistanceUpdate;
  final bool isOperatorView; // New: to determine if this is operator view
  final latlong2.LatLng?
      driverLocation; // New: driver location for operator view

  const BeautifulLiveTrackingMap({
    super.key,
    required this.trip,
    required this.driverId,
    this.height = 400,
    this.onProgressUpdate,
    this.onLocationUpdate,
    this.onDistanceUpdate,
    this.isOperatorView = false, // Default to driver view
    this.driverLocation, // Driver location for operator view
  });

  @override
  State<BeautifulLiveTrackingMap> createState() =>
      _BeautifulLiveTrackingMapState();
}

class _BeautifulLiveTrackingMapState extends State<BeautifulLiveTrackingMap>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final location_pkg.Location _locationService = location_pkg.Location();
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<location_pkg.LocationData>? _locationSubscription;
  RealtimeChannel? _databaseSubscription;

  // Map state - simplified for live tracking
  location_pkg.LocationData? _currentLocation;
  double _progressPercentage = 0.0;
  double _remainingDistance = 0.0;
  DateTime? _startTime;
  DateTime? _estimatedArrival;

  // UI state
  bool _isLoading = true;
  String _statusMessage = 'Initializing GPS tracking...';
  bool _isFollowingDriver =
      false; // Start with follow disabled for better navigation
  bool _showTrackingCard = true;

  // Map locations - simplified for live tracking
  latlong2.LatLng?
      _endLocation; // Only destination needed for arrival detection
  latlong2.LatLng? _currentPosition;

  // Animation controllers
  late AnimationController _markerAnimationController;
  late AnimationController _cardAnimationController;
  late AnimationController _progressAnimationController;

  // GPS configuration (removed unused fields)

  // Real-time driver location refresh for operators
  Timer? _driverLocationRefreshTimer;
  static const Duration _driverLocationRefreshInterval = Duration(seconds: 5);

  // Map centering control
  bool _isUserDragging = false;
  bool _shouldAutoCenter = true;

  // POI and establishment data for operator view
  List<Map<String, dynamic>> _nearbyPOIs = [];
  bool _isLoadingPOIs = false;
  String? _driverAddress;
  bool _showPOIPanel = true; // Control POI panel visibility

  // Arrival detection
  bool _hasArrived = false;
  static const double _arrivalThreshold =
      50.0; // meters - consider arrived if within 50m

  // Geocoding service
  final GeocodingService _geocodingService = GeocodingService();

  @override
  void initState() {
    super.initState();
    _initializeAnimationControllers();
    _initializeGeocodingService();
    _initializeMap();

    // Only start GPS tracking if this is NOT operator view
    if (!widget.isOperatorView) {
      _startRealTimeGPSTracking();
    } else {
      // For operator view, start driver location refresh timer AND database subscription
      _startDriverLocationRefresh();
      _startDatabaseSubscription(); // Add real-time database updates for operator
    }
  }

  @override
  void didUpdateWidget(BeautifulLiveTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update driver location if it changed for operator view
    if (widget.isOperatorView &&
        widget.driverLocation != null &&
        widget.driverLocation != oldWidget.driverLocation) {
      setState(() {
        _currentPosition = widget.driverLocation;
      });
      print(
          '📍 Driver location updated: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    }
  }

  @override
  void dispose() {
    _markerAnimationController.dispose();
    _cardAnimationController.dispose();
    _progressAnimationController.dispose();
    _locationSubscription?.cancel();
    _databaseSubscription?.unsubscribe(); // Add database subscription cleanup
    // Route timer removed - focusing on live tracking only
    _driverLocationRefreshTimer?.cancel();
    super.dispose();
  }

  void _initializeAnimationControllers() {
    _markerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _cardAnimationController.forward();
  }

  void _initializeGeocodingService() {
    // Add Philippine geocoding provider (primary)
    _geocodingService.addProvider(PhilippineGeocodingProvider());

    // TODO: Add Google Maps provider when API key is available
    // _geocodingService.addProvider(GoogleMapsGeocodingProvider(apiKey: 'YOUR_API_KEY'));

    print(
        '🗺️ Geocoding service initialized with ${_geocodingService.availableProviders.length} providers');
  }

  Future<void> _initializeMap() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _statusMessage = 'Initializing live tracking...';
        });
      }

      // Initialize live tracking (no route calculation needed)
      await _initializeLiveTracking();

      // Set driver location for operator view
      if (widget.isOperatorView && widget.driverLocation != null) {
        _currentPosition = widget.driverLocation;
        print(
            '✅ Driver location set for operator view: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');

        // Center map on driver location immediately
        try {
          _mapController.move(_currentPosition!, 15.0);
          print('✅ Map centered on driver location for operator view');
        } catch (e) {
          print('⚠️ Map not ready yet, will center when rendered');
        }

        // Load nearby POIs for operator view
        _loadNearbyPOIs();
      }

      _startTime = DateTime.now();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = widget.isOperatorView
              ? 'Driver tracking active'
              : 'GPS tracking active';
        });
      }
    } catch (e) {
      print('❌ Error initializing map: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Map initialization failed';
        });
      }
    }
  }

  Future<void> _initializeLiveTracking() async {
    try {
      final destination = widget.trip['destination'] ?? '';

      print('🗺️ INITIALIZING LIVE TRACKING:');
      print('   🎯 Destination: "$destination"');

      if (destination.isNotEmpty) {
        // Only geocode destination for arrival detection
        print('🔍 Geocoding destination address...');
        final destCoords = await _geocodeAddress(destination);

        if (destCoords != null) {
          _endLocation = destCoords;

          print('✅ DESTINATION GEOCODED:');
          print(
              '   🎯 Destination coordinates: ${destCoords.latitude}, ${destCoords.longitude}');

          // Center map on destination initially
          _centerMapOnDestination();
          print('✅ Live tracking initialized - focusing on driver movement');
        } else {
          print('❌ DESTINATION GEOCODING FAILED:');
          print('   💡 Will track driver without destination reference');

          if (mounted) {
            setState(() {
              _statusMessage = 'Live tracking active (destination unknown)';
            });
          }
        }
      } else {
        print('❌ No destination provided - pure live tracking mode');
        if (mounted) {
          setState(() {
            _statusMessage = 'Live tracking active';
          });
        }
      }
    } catch (e) {
      print('❌ Error initializing live tracking: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Live tracking initialization failed';
        });
      }
    }
  }

  Future<latlong2.LatLng?> _geocodeAddress(String address) async {
    try {
      print('🔍 FLEXIBLE GEOCODING: "$address"');

      // Use the flexible geocoding service with multiple providers
      final result = await _geocodingService.geocode(address);

      if (result.isSuccess) {
        print('✅ GEOCODING SUCCESSFUL:');
        print(
            '   📍 Coordinates: ${result.coordinates!.latitude}, ${result.coordinates!.longitude}');
        print('   🎯 Accuracy: ${result.accuracy}');
        print('   📡 Source: ${result.source}');
        print(
            '   📊 Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%');
        print('   📝 Description: ${result.description}');

        // Check for warnings or suggestions
        if (result.warning != null) {
          print('⚠️ WARNING: ${result.warning}');
        }

        if (result.suggestions != null && result.suggestions!.isNotEmpty) {
          print('💡 SUGGESTIONS: ${result.suggestions!.join(', ')}');
        }

        return result.coordinates;
      } else {
        // Handle failure cases
        print('❌ GEOCODING FAILED:');
        print('   🚫 Error: ${result.error}');
        if (result.suggestions != null && result.suggestions!.isNotEmpty) {
          print('   💡 Try these instead: ${result.suggestions!.join(', ')}');
        }

        // Don't use generic fallback - return null to indicate failure
        return null;
      }
    } catch (e) {
      print('❌ CRITICAL GEOCODING ERROR for "$address": $e');
      return null;
    }
  }

  /// Center map on destination for initial view
  void _centerMapOnDestination() {
    if (_endLocation != null) {
      try {
        _mapController.move(_endLocation!, 13.0);
        print(
            '✅ Map centered on destination: ${_endLocation!.latitude}, ${_endLocation!.longitude}');
      } catch (e) {
        print('⚠️ Map not ready yet, will center when rendered');
      }
    }
  }

  /// Center map on driver location for live tracking
  void _centerMapOnDriver() {
    if (_currentPosition != null) {
      try {
        _mapController.move(_currentPosition!, 15.0);
        print(
            '✅ Map centered on driver: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
      } catch (e) {
        print('⚠️ Map not ready yet, will center when rendered');
      }
    }
  }

  // Unused method removed - focusing on live tracking only

  /// Start driver location refresh timer for operator view
  void _startDriverLocationRefresh() {
    if (!widget.isOperatorView) return;

    print('🔄 Starting driver location refresh timer for operator view');

    _driverLocationRefreshTimer =
        Timer.periodic(_driverLocationRefreshInterval, (timer) async {
      if (mounted && widget.driverLocation != null) {
        await _refreshDriverLocation();
      }
    });
  }

  /// Refresh driver location for operator view
  Future<void> _refreshDriverLocation() async {
    try {
      if (!widget.isOperatorView || widget.driverLocation == null) return;

      // Update current position with latest driver location
      setState(() {
        _currentPosition = widget.driverLocation;
      });

      // Center map on driver location only if user is not dragging
      if (_shouldAutoCenter && !_isUserDragging) {
        try {
          _mapController.move(_currentPosition!, 16.0);
          print(
              '📍 Driver location refreshed: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
        } catch (e) {
          print('⚠️ Map not ready for centering: $e');
        }
      } else {
        print(
            '📍 Driver location updated but map not centered (user is dragging or auto-center disabled)');
      }

      // Load nearby POIs for operator view
      await _loadNearbyPOIs();

      // Update progress for operator view
      _updateProgress();

      // Animate progress update
      _animateProgressUpdate();
    } catch (e) {
      print('❌ Error refreshing driver location: $e');
    }
  }

  /// Load nearby POIs and establishments for operator view
  Future<void> _loadNearbyPOIs() async {
    if (!widget.isOperatorView || _currentPosition == null) return;

    try {
      setState(() {
        _isLoadingPOIs = true;
      });

      print(
          '🏢 Loading nearby POIs for driver location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');

      // Get driver's address with timeout
      try {
        _driverAddress = await _getAddressFromCoordinates(
                _currentPosition!.latitude, _currentPosition!.longitude)
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⏰ Geocoding timeout, using coordinates');
            return 'Location: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}';
          },
        );
        print('✅ Driver address resolved: $_driverAddress');
      } catch (e) {
        print('❌ Error getting driver address: $e');
        _driverAddress =
            'Location: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}';
      }

      // Load nearby establishments
      _nearbyPOIs = await _getNearbyEstablishments(
          _currentPosition!.latitude, _currentPosition!.longitude);

      setState(() {
        _isLoadingPOIs = false;
      });

      print('✅ Loaded ${_nearbyPOIs.length} nearby POIs');
    } catch (e) {
      print('❌ Error loading nearby POIs: $e');
      setState(() {
        _isLoadingPOIs = false;
      });
    }
  }

  /// Get address from coordinates
  Future<String> _getAddressFromCoordinates(
      double latitude, double longitude) async {
    try {
      print('🔍 Getting address for coordinates: $latitude, $longitude');

      final placemarks = await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        print('📍 Raw placemark data: ${placemark.toString()}');

        // Build address string with null checks
        List<String> addressParts = [];

        if (placemark.street != null && placemark.street!.isNotEmpty) {
          addressParts.add(placemark.street!);
        }
        if (placemark.locality != null && placemark.locality!.isNotEmpty) {
          addressParts.add(placemark.locality!);
        }
        if (placemark.administrativeArea != null &&
            placemark.administrativeArea!.isNotEmpty) {
          addressParts.add(placemark.administrativeArea!);
        }
        if (placemark.country != null && placemark.country!.isNotEmpty) {
          addressParts.add(placemark.country!);
        }

        if (addressParts.isNotEmpty) {
          final address = addressParts.join(', ');
          print('✅ Resolved address: $address');
          return address;
        } else {
          print(
              '⚠️ No address components found, trying Philippine geocoding...');
          return await _tryPhilippineGeocoding(latitude, longitude);
        }
      } else {
        print('⚠️ No placemarks returned, trying Philippine geocoding...');
        return await _tryPhilippineGeocoding(latitude, longitude);
      }
    } catch (e) {
      print('❌ Error getting address from coordinates: $e');
      print('🇵🇭 Trying Philippine geocoding as fallback...');
      return await _tryPhilippineGeocoding(latitude, longitude);
    }
  }

  /// Try Philippine geocoding as fallback
  Future<String> _tryPhilippineGeocoding(
      double latitude, double longitude) async {
    try {
      final provider = PhilippineGeocodingProvider();
      final result = await provider.reverseGeocode(latitude, longitude);

      if (result.address != null && result.address!.isNotEmpty) {
        print('✅ Philippine geocoding success: ${result.address}');
        return result.address!;
      } else {
        print('⚠️ Philippine geocoding returned no address');
        return 'Near ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
      }
    } catch (e) {
      print('❌ Philippine geocoding error: $e');
      return 'Location: ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    }
  }

  /// Get nearby establishments and POIs
  Future<List<Map<String, dynamic>>> _getNearbyEstablishments(
      double latitude, double longitude) async {
    try {
      // This would typically use Google Places API or similar
      // For now, we'll use a mock implementation with Philippine establishments
      return _getMockNearbyEstablishments(latitude, longitude);
    } catch (e) {
      print('❌ Error getting nearby establishments: $e');
      return [];
    }
  }

  /// Mock nearby establishments (replace with real API call)
  List<Map<String, dynamic>> _getMockNearbyEstablishments(
      double latitude, double longitude) {
    // Mock data based on location - in real implementation, use Google Places API
    final establishments = <Map<String, dynamic>>[];

    // Add some mock establishments based on location
    if (latitude > 14.6 &&
        latitude < 14.8 &&
        longitude > 121.0 &&
        longitude < 121.1) {
      // Quezon City area
      establishments.addAll([
        {
          'name': 'SM Fairview',
          'type': 'Shopping Mall',
          'distance': '0.5 km',
          'coordinates': {'lat': 14.6969, 'lng': 121.0375},
          'icon': Icons.shopping_cart,
          'color': Colors.blue,
        },
        {
          'name': 'Robinsons Novaliches',
          'type': 'Shopping Mall',
          'distance': '1.2 km',
          'coordinates': {'lat': 14.7000, 'lng': 121.0400},
          'icon': Icons.shopping_cart,
          'color': Colors.blue,
        },
        {
          'name': '7-Eleven',
          'type': 'Convenience Store',
          'distance': '0.3 km',
          'coordinates': {'lat': latitude + 0.001, 'lng': longitude + 0.001},
          'icon': Icons.store,
          'color': Colors.green,
        },
        {
          'name': 'Jollibee',
          'type': 'Restaurant',
          'distance': '0.8 km',
          'coordinates': {'lat': latitude - 0.001, 'lng': longitude + 0.002},
          'icon': Icons.restaurant,
          'color': Colors.red,
        },
        {
          'name': 'McDonald\'s',
          'type': 'Restaurant',
          'distance': '1.0 km',
          'coordinates': {'lat': latitude + 0.002, 'lng': longitude - 0.001},
          'icon': Icons.restaurant,
          'color': Colors.red,
        },
        {
          'name': 'BDO Bank',
          'type': 'Bank',
          'distance': '0.6 km',
          'coordinates': {'lat': latitude - 0.002, 'lng': longitude - 0.002},
          'icon': Icons.account_balance,
          'color': Colors.orange,
        },
      ]);
    }

    return establishments;
  }

  Future<void> _startRealTimeGPSTracking() async {
    try {
      // Request location permissions
      bool serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _locationService.requestService();
        if (!serviceEnabled) {
          throw Exception('Location service is disabled');
        }
      }

      location_pkg.PermissionStatus permissionGranted =
          await _locationService.hasPermission();
      if (permissionGranted == location_pkg.PermissionStatus.denied) {
        permissionGranted = await _locationService.requestPermission();
        if (permissionGranted != location_pkg.PermissionStatus.granted) {
          throw Exception('Location permission denied');
        }
      }

      // Configure location settings for high accuracy
      await _locationService.changeSettings(
        accuracy: location_pkg.LocationAccuracy.high,
        interval: 2000, // 2 seconds
        distanceFilter: 5, // 5 meters
      );

      // Start real-time location tracking
      _locationSubscription = _locationService.onLocationChanged.listen(
        (locationData) {
          if (mounted) {
            _handleLocationUpdate(locationData);
          }
        },
        onError: (error) {
          print('❌ GPS tracking error: $error');
          if (mounted) {
            setState(() {
              _statusMessage = 'GPS error: $error';
            });
          }
        },
      );

      print('✅ Real-time GPS tracking started');
    } catch (e) {
      print('❌ Error starting GPS tracking: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'GPS initialization failed';
        });
      }
    }
  }

  /// Start database subscription for real-time location updates (operator view)
  Future<void> _startDatabaseSubscription() async {
    try {
      print('🔄 Starting database subscription for driver: ${widget.driverId}');

      _databaseSubscription = _supabase
          .channel('driver_location_${widget.driverId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'driver_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'driver_id',
              value: widget.driverId,
            ),
            callback: (payload) {
              print('📍 Database location INSERT: ${payload.newRecord}');
              _handleDatabaseLocationUpdate(payload.newRecord);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'driver_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'driver_id',
              value: widget.driverId,
            ),
            callback: (payload) {
              print('📍 Database location UPDATE: ${payload.newRecord}');
              _handleDatabaseLocationUpdate(payload.newRecord);
            },
          )
          .subscribe();

      print('✅ Database subscription started for driver: ${widget.driverId}');
    } catch (e) {
      print('❌ Error starting database subscription: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Database subscription failed';
        });
      }
    }
  }

  /// Handle database location updates for operator view
  void _handleDatabaseLocationUpdate(Map<String, dynamic> locationRecord) {
    if (!mounted || !widget.isOperatorView) return;

    try {
      // Safe conversion helper for numeric values from database
      double? _safeToDouble(dynamic value) {
        if (value == null) return null;
        if (value is double) return value;
        if (value is int) return value.toDouble();
        if (value is String) return double.tryParse(value);
        return null;
      }

      final lat = _safeToDouble(locationRecord['latitude']);
      final lng = _safeToDouble(locationRecord['longitude']);
      final speed = _safeToDouble(locationRecord['speed']);
      final tripId = locationRecord['trip_id'] as String?;

      // Only process if it's for the current trip (if trip is specified)
      final currentTripId = widget.trip['id']?.toString();
      if (currentTripId != null && tripId != currentTripId) {
        print(
            '⚠️ Ignoring location for different trip: $tripId (current: $currentTripId)');
        return;
      }

      if (lat != null && lng != null) {
        // Convert to location data format for consistency
        final fakeLocationData = location_pkg.LocationData.fromMap({
          'latitude': lat,
          'longitude': lng,
          'speed': speed ?? 0.0,
          'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
        });

        setState(() {
          _currentLocation = fakeLocationData;
          _currentPosition = latlong2.LatLng(lat, lng);
          _statusMessage = 'Live tracking active';
        });

        // Update progress and animations
        _updateProgress();
        _animateMarkerUpdate();
        _followDriverIfEnabled();

        // Call callbacks
        widget.onLocationUpdate?.call('$lat, $lng');

        print(
            '🗺️ Operator map updated from database: $lat, $lng, Speed: ${speed?.toStringAsFixed(1) ?? '0.0'} km/h');
      }
    } catch (e) {
      print('❌ Error handling database location update: $e');
    }
  }

  void _handleLocationUpdate(location_pkg.LocationData locationData) {
    if (!mounted) return;

    setState(() {
      _currentLocation = locationData;
      _currentPosition =
          latlong2.LatLng(locationData.latitude!, locationData.longitude!);
    });

    // Update progress (simplified for live tracking)
    _updateProgress();

    // Animate marker
    _animateMarkerUpdate();

    // Follow driver if enabled
    _followDriverIfEnabled();

    // Call callbacks
    widget.onLocationUpdate
        ?.call('${locationData.latitude}, ${locationData.longitude}');

    print('📍 GPS Update: ${locationData.latitude}, ${locationData.longitude}');
  }

  // Route-related methods removed - focusing on live tracking only

  void _updateProgress() {
    // Simplified progress calculation for live tracking
    if (_currentPosition == null || _endLocation == null) return;

    // Calculate remaining distance to destination
    _remainingDistance = _calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _endLocation!.latitude,
      _endLocation!.longitude,
    );

    // Simple progress calculation based on direct distance
    // This is more accurate for live tracking than route-based calculations
    _progressPercentage = 0.0; // Will be calculated based on actual movement

    // Check for arrival
    _checkArrival();

    // Update callbacks
    widget.onProgressUpdate?.call(_progressPercentage);
    widget.onDistanceUpdate?.call(_remainingDistance);
  }

  /// Check if driver has arrived at destination
  void _checkArrival() {
    if (_currentPosition == null || _endLocation == null) return;

    // Calculate distance to destination in meters
    final distanceToDestination = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          _endLocation!.latitude,
          _endLocation!.longitude,
        ) *
        1000; // Convert km to meters

    // Check if within arrival threshold
    if (distanceToDestination <= _arrivalThreshold && !_hasArrived) {
      setState(() {
        _hasArrived = true;
        _progressPercentage = 100.0;
      });

      print('🎉 ARRIVAL DETECTED! Driver has reached destination!');
      print(
          '📍 Distance to destination: ${distanceToDestination.toStringAsFixed(1)}m');
      print('✅ Progress: 100%');

      // You can add arrival notification here
      _showArrivalNotification();
    } else if (distanceToDestination > _arrivalThreshold && _hasArrived) {
      // Driver moved away from destination
      setState(() {
        _hasArrived = false;
      });
      print('📍 Driver moved away from destination');
    }
  }

  /// Show arrival notification
  void _showArrivalNotification() {
    // This could trigger a notification, sound, or UI update
    print('🔔 ARRIVAL NOTIFICATION: Driver has reached the destination!');
  }

  // ETA calculation method removed - focusing on live tracking only

  void _animateMarkerUpdate() {
    // Don't animate marker for operators since they're not moving
    if (widget.isOperatorView) return;

    _markerAnimationController.forward().then((_) {
      _markerAnimationController.reverse();
    });
  }

  void _animateProgressUpdate() {
    // Animate progress for both operators and drivers
    _progressAnimationController.forward().then((_) {
      _progressAnimationController.reverse();
    });
  }

  void _followDriverIfEnabled() {
    // Don't follow for operators since they're not moving
    if (widget.isOperatorView) return;

    if (_isFollowingDriver && _currentPosition != null) {
      // Only follow if user hasn't manually moved the map recently
      try {
        _mapController.move(_currentPosition!, 15.0);
      } catch (e) {
        print('⚠️ Map not ready yet, will follow when rendered');
      }
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  // Distance calculation method removed - focusing on live tracking only

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade900,
              Colors.blue.shade700,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Map
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _endLocation ?? const latlong2.LatLng(0.0, 0.0),
                initialZoom: 13.0,
                onTap: (_, __) {
                  // Handle map tap
                },
                onMapEvent: (MapEvent mapEvent) {
                  if (mapEvent is MapEventMoveStart) {
                    _isUserDragging = true;
                    _shouldAutoCenter = false;
                    print(
                        '🗺️ User started dragging map - auto-center disabled');
                  } else if (mapEvent is MapEventMoveEnd) {
                    _isUserDragging = false;
                    print('🗺️ User stopped dragging map');
                  }
                },
              ),
              children: [
                // High-quality OpenStreetMap tiles for better accuracy
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.tinysync.app',
                  maxZoom: 19,
                  additionalOptions: const {
                    'attribution': '© OpenStreetMap contributors',
                  },
                ),

                // Alternative high-quality tiles for better coverage
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.tinysync.app',
                  maxZoom: 19,
                  additionalOptions: const {
                    'attribution': '© OpenStreetMap contributors, © HOT',
                  },
                ),

                // Route polylines removed - focusing on truck tracking only

                // Origin and destination markers removed - focusing on live driver tracking only

                // Enhanced Driver Location Marker with Smooth Animation
                if (_currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentPosition!,
                        width: 90,
                        height: 90,
                        child: AnimatedBuilder(
                          animation: _markerAnimationController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: 1.0 +
                                  (_markerAnimationController.value * 0.1),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.isOperatorView
                                      ? Colors.blue.shade600
                                      : Colors.orange.shade600,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (widget.isOperatorView
                                              ? Colors.blue
                                              : Colors.orange)
                                          .withOpacity(0.6),
                                      blurRadius: 15,
                                      spreadRadius: 4,
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.8),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Pulsing ring effect
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: (widget.isOperatorView
                                                  ? Colors.blue
                                                  : Colors.orange)
                                              .withOpacity(0.3),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    // Main truck icon
                                    const Icon(
                                      Icons.local_shipping,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                    // Direction indicator (if available)
                                    if (_currentLocation?.heading != null)
                                      Positioned(
                                        top: 5,
                                        right: 5,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white, width: 1),
                                          ),
                                          child: const Icon(
                                            Icons.navigation,
                                            color: Colors.white,
                                            size: 8,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                // Nearby POI Markers (for operator view)
                if (widget.isOperatorView && _nearbyPOIs.isNotEmpty)
                  MarkerLayer(
                    markers: _nearbyPOIs.map((poi) {
                      final coordinates =
                          poi['coordinates'] as Map<String, dynamic>;
                      final lat = coordinates['lat'] as double;
                      final lng = coordinates['lng'] as double;
                      final icon = poi['icon'] as IconData;
                      final color = poi['color'] as Color;
                      final name = poi['name'] as String;

                      return Marker(
                        point: latlong2.LatLng(lat, lng),
                        width: 40,
                        height: 40,
                        child: Tooltip(
                          message: name,
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              icon,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),

          // Map Controls
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                // Center on Driver Button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (_currentPosition != null) {
                          try {
                            _mapController.move(_currentPosition!, 15.0);
                          } catch (e) {
                            print('⚠️ Map not ready yet');
                          }
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.my_location,
                            color: Colors.blue, size: 24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Follow Driver Toggle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _isFollowingDriver
                        ? Colors.blue.shade100
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: _isFollowingDriver
                        ? Border.all(color: Colors.blue, width: 2)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _isFollowingDriver = !_isFollowingDriver;
                        });
                        if (_isFollowingDriver && _currentPosition != null) {
                          // Immediately center on driver when enabling follow
                          try {
                            _mapController.move(_currentPosition!, 15.0);
                          } catch (e) {
                            print('⚠️ Map not ready yet');
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.gps_fixed,
                          color: _isFollowingDriver ? Colors.blue : Colors.grey,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Center on Route
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _centerMapOnDriver,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.my_location,
                            color: Colors.blue, size: 24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Arrival Banner
          if (_hasArrived)
            Positioned(
              top: 16,
              left: 16,
              right: 100,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Driver has arrived at destination!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Off Route Warning removed - focusing on live tracking only
          Positioned(
            top: 16,
            left: 16,
            right: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade600,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Recalculating route...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tracking Card
          if (_showTrackingCard)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: AnimatedBuilder(
                animation: _cardAnimationController,
                builder: (context, child) {
                  return Transform.translate(
                    offset:
                        Offset(0, 20 * (1 - _cardAnimationController.value)),
                    child: Opacity(
                      opacity: _cardAnimationController.value,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0.95),
                              Colors.white.withOpacity(0.9),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.gps_fixed,
                                    color: Colors.blue.shade700,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _hasArrived
                                            ? 'Trip Completed!'
                                            : 'Live GPS Tracking',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: _hasArrived
                                              ? Colors.green.shade700
                                              : Colors.grey.shade800,
                                        ),
                                      ),
                                      // Debug info for destination
                                      if (_endLocation != null) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: Colors.blue
                                                    .withOpacity(0.3)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (_endLocation != null)
                                                Text(
                                                  '🎯 Destination: ${_endLocation!.latitude.toStringAsFixed(6)}, ${_endLocation!.longitude.toStringAsFixed(6)}',
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.blue),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      Row(
                                        children: [
                                          Text(
                                            'Real-time location monitoring',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          if (_isFollowingDriver) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'Following',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.blue.shade700,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      setState(() {
                                        _showTrackingCard = false;
                                      });
                                      _cardAnimationController.reverse();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        Icons.close,
                                        color: Colors.grey.shade600,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Live Tracking Status
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _hasArrived
                                    ? Colors.green.shade50
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _hasArrived
                                      ? Colors.green.shade200
                                      : Colors.blue.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _hasArrived
                                        ? Icons.check_circle
                                        : Icons.location_on,
                                    color: _hasArrived
                                        ? Colors.green
                                        : Colors.blue,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _hasArrived
                                              ? 'Arrived at Destination!'
                                              : 'Live Tracking Active',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: _hasArrived
                                                ? Colors.green.shade700
                                                : Colors.blue.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _hasArrived
                                              ? 'Driver has reached the destination'
                                              : 'Real-time GPS tracking in progress',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Stats Grid
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.speed,
                                    title: 'Distance to Destination',
                                    value:
                                        '${_remainingDistance.toStringAsFixed(1)} km',
                                    subtitle: 'Direct distance',
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.access_time,
                                    title: 'Start Time',
                                    value: _formatTime(_startTime),
                                    subtitle: 'Trip began',
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.timer,
                                    title: 'ETA',
                                    value: _formatTime(_estimatedArrival),
                                    subtitle: 'Estimated arrival',
                                    color: Colors.purple,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    icon: Icons.gps_fixed,
                                    title: 'Speed',
                                    value: _currentLocation?.speed != null
                                        ? '${(_currentLocation!.speed! * 3.6).toStringAsFixed(1)} km/h'
                                        : '-- km/h',
                                    subtitle: 'Current speed',
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // POI Information Panel (for operator view)
          if (widget.isOperatorView && _nearbyPOIs.isNotEmpty && _showPOIPanel)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildPOIInformationPanel(),
            ),

          // Show POI Panel Button (when panel is hidden)
          if (widget.isOperatorView && _nearbyPOIs.isNotEmpty && !_showPOIPanel)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.small(
                onPressed: () {
                  setState(() {
                    _showPOIPanel = true;
                  });
                },
                backgroundColor: Colors.blue.shade600,
                child: const Icon(Icons.info_outline, color: Colors.white),
              ),
            ),

          // Follow Truck Button (for operator view)
          if (widget.isOperatorView && _currentPosition != null)
            Positioned(
              top: 16,
              right: 16,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    onPressed: () {
                      _centerMapOnDriver();
                    },
                    backgroundColor: Colors.blue.shade600,
                    child: const Icon(Icons.my_location, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _shouldAutoCenter ? 'Auto-Follow' : 'Manual',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Build POI Information Panel for operator view
  Widget _buildPOIInformationPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'Driver Location Context',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const Spacer(),
              if (_isLoadingPOIs)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 8),
              // Close button for POI panel
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showPOIPanel = false; // Hide the panel
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.close,
                    color: Colors.grey.shade600,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Driver Address
          if (_driverAddress != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.my_location,
                      color: Colors.blue.shade600, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _driverAddress!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Nearby Establishments
          Text(
            'Nearby Establishments',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),

          // POI List
          ...(_nearbyPOIs.take(4).map((poi) {
            final name = poi['name'] as String;
            final type = poi['type'] as String;
            final distance = poi['distance'] as String;
            final icon = poi['icon'] as IconData;
            final color = poi['color'] as Color;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        Text(
                          '$type • $distance',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList()),

          // Show more button if there are more POIs
          if (_nearbyPOIs.length > 4)
            Center(
              child: TextButton(
                onPressed: () {
                  // TODO: Show full POI list
                },
                child: Text(
                  'Show ${_nearbyPOIs.length - 4} more places',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
