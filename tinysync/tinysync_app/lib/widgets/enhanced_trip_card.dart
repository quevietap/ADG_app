import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'dart:async';
import '../services/notification_service.dart';
import '../services/trip_lifecycle_service.dart';
import '../services/driver_safety_location_service.dart';
import '../services/driver_location_service.dart';
import '../services/auth_persistence_service.dart';
import '../services/overdue_trip_service.dart';
import 'view_logs_modal.dart';
import 'beautiful_live_tracking_map.dart';

class EnhancedTripCard extends StatefulWidget {
  final Map<String, dynamic> trip;
  final int cardIndex;
  final bool isFromSchedule;
  final bool isToday;
  final Function()? onTripUpdated;
  final Function(String, String)? onStatusChanged;
  final bool showRealTimeTracking;
  final bool isDriver; // New: to determine if this is driver view
  final bool isOperator; // New: to determine if this is operator view
  final Map<String, dynamic>? userData; // User data for getting operator ID
  final Function(Map<String, dynamic>)?
      onAssignDriver; // Callback for driver assignment
  final Function(Map<String, dynamic>)?
      onAssignVehicle; // Callback for vehicle assignment
  final Function(Map<String, dynamic>)?
      onTripCancelled; // Callback for trip cancellation
  final Function(Map<String, dynamic>)?
      onTripDeleted; // Callback for trip deletion
  final Function(Map<String, dynamic>, String)?
      onCancel; // Callback for trip cancellation with reason
  final Function(Map<String, dynamic>, String)?
      onDelete; // Callback for trip deletion with reason

  const EnhancedTripCard({
    super.key,
    required this.trip,
    required this.cardIndex,
    this.isFromSchedule = false,
    this.isToday = false,
    this.onTripUpdated,
    this.onStatusChanged,
    this.showRealTimeTracking = true,
    this.isDriver = false,
    this.isOperator = true,
    this.userData,
    this.onAssignDriver,
    this.onAssignVehicle,
    this.onTripCancelled,
    this.onTripDeleted,
    this.onCancel,
    this.onDelete,
  });

  @override
  State<EnhancedTripCard> createState() => _EnhancedTripCardState();
}

class _EnhancedTripCardState extends State<EnhancedTripCard> {
  RealtimeChannel? _tripSubscription;
  RealtimeChannel? _locationSubscription;
  GoogleMapController? _mapController;
  List<LatLng> _tripPath = [];
  LatLng? _currentLocation;
  DateTime? _lastLocationUpdate;
  bool _isExpanded = false;
  bool _showMap = false;
  bool _isLoading = false;
  bool _isSendingReminder = false; // Loading state for reminder sending
  // String? _currentUserRole; // Unused - commented out

  // Driver location service for operator view
  final DriverLocationService _driverLocationService = DriverLocationService();
  StreamSubscription<Map<String, dynamic>>? _driverLocationSubscription;
  String? _driverTripStatus;

  @override
  void initState() {
    super.initState();
    _getCurrentUserRole();
    if (widget.showRealTimeTracking) {
      _initializeRealTimeTracking();
      _loadTripPath();

      // Initialize driver location tracking for operator view ONLY if driver has accepted
      if (widget.isOperator && !widget.isDriver && _hasDriverAcceptedTrip()) {
        _initializeDriverLocationTracking();
      }
    }
  }

  @override
  void dispose() {
    _tripSubscription?.unsubscribe();
    _locationSubscription?.unsubscribe();
    _driverLocationSubscription?.cancel();

    // Clear driver location cache when widget is disposed
    if (widget.isOperator && !widget.isDriver) {
      final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
      if (driverId != null) {
        _driverLocationService.clearDriverCache(driverId);
        print('🧹 Cleared driver cache for driver: $driverId');
      }
    }

    super.dispose();
  }

  Future<void> _getCurrentUserRole() async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        // final userResponse = await Supabase.instance.client
        //     .from('users')
        //     .select('role')
        //     .eq('id', currentUser.id)
        //     .single();
        // setState(() {
        //   // _currentUserRole = userResponse['role']; // Unused - commented out
        // });
      }
    } catch (e) {
      print('❌ Error getting current user role: $e');
    }
  }

  void _initializeRealTimeTracking() {
    try {
      final tripId = widget.trip['id'];

      // Subscribe to trip updates
      _tripSubscription = Supabase.instance.client
          .channel('enhanced_trip_updates_$tripId')
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
              print('🔄 Enhanced trip update received: $payload');
              _handleTripStatusChange(payload);
              if (widget.onTripUpdated != null) {
                widget.onTripUpdated!();
              }
            },
          )
          .subscribe();

      // Subscribe to location updates
      _locationSubscription = Supabase.instance.client
          .channel('enhanced_trip_locations_$tripId')
          .subscribe();
    } catch (e) {
      print('❌ Error initializing real-time tracking: $e');
    }
  }

  /// Initialize driver location tracking for operator view
  void _initializeDriverLocationTracking() async {
    try {
      final tripId = widget.trip['id'];
      print('🚗 Initializing driver location tracking for trip: $tripId');

      // Get initial driver status
      _driverTripStatus =
          await _driverLocationService.getDriverTripStatus(tripId);

      // Subscribe to real-time driver location updates
      _driverLocationSubscription = _driverLocationService
          .subscribeToTripDriverLocation(tripId)
          .listen((locationData) {
        _handleDriverLocationUpdate(locationData);
      });

      // Load initial driver location
      await _loadDriverLocation();

      setState(() {});
      print('✅ Driver location tracking initialized');
    } catch (e) {
      print('❌ Error initializing driver location tracking: $e');
    }
  }

  void _handleTripStatusChange(PostgresChangePayload payload) {
    try {
      final newRecord = payload.newRecord;
      final oldRecord = payload.oldRecord;

      // Check for status changes
      if (oldRecord.isNotEmpty) {
        final newStatus = newRecord['status'];
        final oldStatus = oldRecord['status'];

        // Check if trip just started
        if (newStatus == 'in_progress' && oldStatus != 'in_progress') {
          _sendTripStartNotification();

          // Initialize driver location tracking for operator when driver starts trip
          if (widget.isOperator &&
              !widget.isDriver &&
              _driverLocationSubscription == null) {
            print(
                '🚗 Driver started trip - initializing location tracking for operator');
            _initializeDriverLocationTracking();
          }
        }

        // Check if driver accepted the trip (accepted_at or started_at changed)
        final newAcceptedAt = newRecord['accepted_at'];
        final oldAcceptedAt = oldRecord['accepted_at'];
        final newStartedAt = newRecord['started_at'];
        final oldStartedAt = oldRecord['started_at'];

        if ((newAcceptedAt != null && oldAcceptedAt == null) ||
            (newStartedAt != null && oldStartedAt == null)) {
          // Initialize driver location tracking for operator when driver accepts
          if (widget.isOperator &&
              !widget.isDriver &&
              _driverLocationSubscription == null) {
            print(
                '🚗 Driver accepted trip - initializing location tracking for operator');
            _initializeDriverLocationTracking();
          }
        }

        // Update UI
        setState(() {});
      }
    } catch (e) {
      print('❌ Error handling trip status change: $e');
    }
  }

  void _sendTripStartNotification() {
    try {
      final driverName = _getDriverName();
      final tripRefNumber =
          widget.trip['trip_ref_number'] ?? 'TRIP-${widget.trip['id']}';

      // Send notification to operator
      NotificationService().sendTripStartNotification(
        tripId: widget.trip['id'].toString(),
        driverName: driverName,
        tripRefNumber: tripRefNumber,
      );

      print('🔔 Trip start notification sent for driver: $driverName');
    } catch (e) {
      print('❌ Error sending trip start notification: $e');
    }
  }

  String _getDriverName() {
    final mainDriver = widget.trip['users'] ?? {};
    if (mainDriver.isNotEmpty) {
      return '${mainDriver['first_name'] ?? ''} ${mainDriver['last_name'] ?? ''}'
          .trim();
    }
    return 'Unknown Driver';
  }

  // Show safety information to driver
  void _showSafetyInformation({
    required String destination,
    required Map<String, dynamic> destinationValidation,
    required Map<String, dynamic> routeSafety,
    required Map<String, dynamic> safeLocation,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.security, color: Colors.green),
              SizedBox(width: 8),
              Text('Trip Safety Validation'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // GPS Accuracy
                _buildSafetyRow(
                  icon: Icons.gps_fixed,
                  title: 'GPS Accuracy',
                  value:
                      '${safeLocation['accuracy_level']} (${safeLocation['accuracy'].toStringAsFixed(1)}m)',
                  color: _getAccuracyColor(safeLocation['accuracy_level']),
                ),

                const Divider(),

                // Destination
                _buildSafetyRow(
                  icon: Icons.location_on,
                  title: 'Destination',
                  value: destinationValidation['destination_address'],
                  color: Colors.blue,
                ),

                // Distance
                _buildSafetyRow(
                  icon: Icons.route,
                  title: 'Distance',
                  value:
                      '${(destinationValidation['distance_to_destination'] / 1000).toStringAsFixed(2)} km',
                  color: Colors.orange,
                ),

                // Route Safety
                _buildSafetyRow(
                  icon: Icons.security,
                  title: 'Route Safety',
                  value: routeSafety['safety_level'].toString().toUpperCase(),
                  color: _getSafetyColor(routeSafety['safety_level']),
                ),

                // Safety Warnings
                if (routeSafety['safety_warnings'].isNotEmpty) ...[
                  const Divider(),
                  const Text('Safety Warnings:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 8),
                  ...routeSafety['safety_warnings'].map(
                    (warning) => Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.warning,
                              size: 16, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(warning,
                                  style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    ),
                  ),
                ],

                // Recommendations
                if (routeSafety['recommendations'].isNotEmpty) ...[
                  const Divider(),
                  const Text('Recommendations:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 8),
                  ...routeSafety['recommendations'].map(
                    (rec) => Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 16, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(rec,
                                  style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Proceed Safely'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSafetyRow({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getAccuracyColor(String accuracyLevel) {
    switch (accuracyLevel.toLowerCase()) {
      case 'excellent':
        return Colors.green;
      case 'good':
        return Colors.blue;
      case 'acceptable':
        return Colors.orange;
      case 'poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getSafetyColor(String safetyLevel) {
    switch (safetyLevel.toLowerCase()) {
      case 'safe':
        return Colors.green;
      case 'moderate':
        return Colors.orange;
      case 'caution':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /*
  void _handleLocationUpdate(Map<String, dynamic> payload) {
    try {
      final data = payload['payload'];
      if (data != null) {
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        
        if (lat != null && lng != null) {
          setState(() {
            _currentLocation = LatLng(lat, lng);
            _tripPath.add(_currentLocation!);
          });
          
          // Center map on current location
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(_currentLocation!, 15.0),
          );
        }
      }
    } catch (e) {
      print('❌ Error handling location update: $e');
    }
  }
  */

  /// Handle driver location updates for operator view
  void _handleDriverLocationUpdate(Map<String, dynamic> locationData) {
    try {
      final lat = locationData['latitude'] as double?;
      final lng = locationData['longitude'] as double?;
      final timestamp = locationData['timestamp'] as String?;

      if (lat != null && lng != null) {
        setState(() {
          _currentLocation = LatLng(lat, lng);
          _lastLocationUpdate = timestamp != null
              ? DateTime.tryParse(timestamp) ?? DateTime.now()
              : DateTime.now();
          _driverTripStatus = 'Driver en route';
        });

        // Center map on driver's location
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_currentLocation!, 15.0),
        );

        print(
            '📍 Driver location update: $lat, $lng at ${_lastLocationUpdate}');
      }
    } catch (e) {
      print('❌ Error handling driver location update: $e');
    }
  }

  /// Load driver location for operator view
  Future<void> _loadDriverLocation() async {
    try {
      final tripId = widget.trip['id'];
      print(
          '🔄 LOADING DRIVER LOCATION: Using force refresh for trip: $tripId');

      // Use force refresh to ensure we get fresh data for the current operator
      final driverLocation = await _driverLocationService
          .forceRefreshDriverLocationForTrip(tripId);

      if (driverLocation != null) {
        final lat = driverLocation['latitude'] as double?;
        final lng = driverLocation['longitude'] as double?;
        final timestamp = driverLocation['timestamp'] as String?;

        if (lat != null && lng != null) {
          setState(() {
            _currentLocation = LatLng(lat, lng);
            _lastLocationUpdate = timestamp != null
                ? DateTime.tryParse(timestamp) ?? DateTime.now()
                : DateTime.now();
            _driverTripStatus = 'Driver en route';
          });

          print(
              '✅ FRESH DRIVER LOCATION LOADED: $lat, $lng at ${_lastLocationUpdate}');
          print('📱 This is the DRIVER\'S location, NOT the operator\'s');
        }
      } else {
        // Update driver status if no location available
        _driverTripStatus =
            await _driverLocationService.getDriverTripStatus(tripId);
        setState(() {});
        print('⚠️ No driver location available for trip: $tripId');
      }
    } catch (e) {
      print('❌ Error loading driver location: $e');
    }
  }

  Future<void> _loadTripPath() async {
    try {
      final tripId = widget.trip['id'];

      // Load trip locations from database
      final response = await Supabase.instance.client
          .from('trip_locations')
          .select('latitude, longitude, location_type, timestamp')
          .eq('trip_id', tripId)
          .order('timestamp');

      setState(() {
        _tripPath = (response as List).map((location) {
          return LatLng(
            location['latitude'] as double,
            location['longitude'] as double,
          );
        }).toList();
      });

      // For operator view, use driver location instead of trip path
      if (widget.isOperator && !widget.isDriver) {
        // Driver location will be set by _loadDriverLocation()
        return;
      }

      // Set current location to last known position (for driver view)
      if (_tripPath.isNotEmpty) {
        _currentLocation = _tripPath.last;
        _lastLocationUpdate =
            DateTime.now(); // Set timestamp for trip path location
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_currentLocation!, 15.0),
        );
      }
    } catch (e) {
      print('❌ Error loading trip path: $e');
    }
  }

  // Start Trip Function (for drivers) with Safety Validation
  Future<void> _startTrip() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final tripId = widget.trip['id'];
      final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
      final origin = widget.trip['origin'] ?? 'Unknown';
      final destination = widget.trip['destination'] ?? 'Unknown';

      print('🛡️ Starting trip with safety validation...');

      // Step 1: Get safe current location
      final safetyService = DriverSafetyLocationService();
      final safeLocation = await safetyService.getSafeCurrentLocation();

      if (safeLocation == null) {
        throw Exception('Unable to get current location for safety validation');
      }

      if (!safeLocation['is_safe_for_driving']) {
        throw Exception(
            'GPS accuracy too low for safe navigation: ${safeLocation['safety_warning']}');
      }

      // Step 2: Validate destination safety
      final destinationValidation =
          await safetyService.validateDestinationSafety(
        destination: destination,
        currentLat: safeLocation['position'].latitude,
        currentLng: safeLocation['position'].longitude,
      );

      if (!destinationValidation['is_safe']) {
        throw Exception(
            'Destination safety validation failed: ${destinationValidation['warning']}');
      }

      // Step 3: Assess route safety
      final routeSafety = await safetyService.assessRouteSafety(
        startLat: safeLocation['position'].latitude,
        startLng: safeLocation['position'].longitude,
        endLat: destinationValidation['destination_coordinates']['lat'],
        endLng: destinationValidation['destination_coordinates']['lng'],
      );

      // Step 4: Show safety information to driver
      if (mounted) {
        _showSafetyInformation(
          destination: destination,
          destinationValidation: destinationValidation,
          routeSafety: routeSafety,
          safeLocation: safeLocation,
        );
      }

      // Step 5: Use TripLifecycleService to start trip with validated coordinates
      final result = await TripLifecycleService().startTrip(
        tripId: tripId,
        driverId: driverId,
        origin: origin,
        destination: destination,
        startLatitude: safeLocation['position'].latitude,
        startLongitude: safeLocation['position'].longitude,
      );

      if (result['success']) {
        // Send notification to operator
        _sendTripStartNotification();

        // Show success message with safety info
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result['message'],
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                      'GPS Accuracy: ${safeLocation['accuracy_level']} (${safeLocation['accuracy'].toStringAsFixed(1)}m)'),
                  Text(
                      'Distance to destination: ${(destinationValidation['distance_to_destination'] / 1000).toStringAsFixed(2)} km'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }

        // Refresh trip data
        if (widget.onTripUpdated != null) {
          widget.onTripUpdated!();
        }
      } else {
        throw Exception(result['message']);
      }
    } catch (e) {
      print('❌ Error starting trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting trip: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Complete Trip Function (for drivers)
  Future<void> _completeTrip() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final tripId = widget.trip['id'];
      final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
      final origin = widget.trip['origin'] ?? 'Unknown';
      final destination = widget.trip['destination'] ?? 'Unknown';

      // Use TripLifecycleService to complete trip and create session log
      print(
          '🚀 DRIVER: About to complete trip $tripId with driver_completed status');
      final result = await TripLifecycleService().completeTrip(
        tripId: tripId,
        driverId: driverId,
        origin: origin,
        destination: destination,
        endLatitude: _currentLocation?.latitude,
        endLongitude: _currentLocation?.longitude,
      );
      print('🚀 DRIVER: TripLifecycleService.completeTrip result: $result');

      if (result['success']) {
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.orange,
            ),
          );
        }

        // Refresh trip data
        if (widget.onTripUpdated != null) {
          widget.onTripUpdated!();
        }
      } else {
        throw Exception(result['message']);
      }
    } catch (e) {
      print('❌ Error completing trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error completing trip: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Confirm Completion Function (for operators)
  Future<void> _confirmCompletion() async {
    if (_isLoading) return;

    // Validate that trip is in the correct status for confirmation
    if (widget.trip['status'] != 'driver_completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trip is not ready for operator confirmation'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final tripId = widget.trip['id'];

      // Get the operator ID with multiple fallback strategies
      String? operatorId;

      // Strategy 1: Try userData (passed from parent)
      if (widget.userData != null && widget.userData!['id'] != null) {
        operatorId = widget.userData!['id'];
      }
      // Strategy 2: Try AuthPersistenceService
      else {
        try {
          final savedAuth = await AuthPersistenceService.getCurrentUserData();
          if (savedAuth != null && savedAuth['id'] != null) {
            operatorId = savedAuth['id'];
          }
        } catch (e) {
          print('⚠️ AuthPersistenceService failed: $e');
        }
      }

      // Strategy 3: Try Supabase auth
      if (operatorId == null) {
        final currentUser = Supabase.instance.client.auth.currentUser;
        if (currentUser != null) {
          operatorId = currentUser.id;
        }
      }

      final origin = widget.trip['origin'] ?? 'Unknown';
      final destination = widget.trip['destination'] ?? 'Unknown';

      // Strategy 4: Last resort - get any operator from database
      if (operatorId == null || operatorId.isEmpty) {
        try {
          final operatorResponse = await Supabase.instance.client
              .from('users')
              .select('id')
              .eq('role', 'operator')
              .limit(1)
              .single();

          operatorId = operatorResponse['id'];
        } catch (e) {
          throw Exception(
              'Unable to identify operator. Please ensure you are logged in properly.');
        }
      }

      // Final validation
      if (operatorId == null || operatorId.isEmpty) {
        throw Exception(
            'Operator ID is not available. Please ensure you are logged in properly.');
      }

      // Use TripLifecycleService to confirm trip completion
      final result = await TripLifecycleService().confirmTripCompletion(
        tripId: tripId,
        operatorId: operatorId,
        origin: origin,
        destination: destination,
      );

      if (result['success']) {
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
            ),
          );
        }

        // Refresh trip data
        if (widget.onTripUpdated != null) {
          widget.onTripUpdated!();
        }
      } else {
        throw Exception(result['message']);
      }
    } catch (e) {
      print('❌ Error confirming trip completion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming trip completion: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getTripStatus() {
    return widget.trip['status'] ?? 'unknown';
  }

  String _getDisplayStatus() {
    // Check if trip is overdue first
    if (_isTripOverdue()) {
      return 'OVERDUE';
    }

    switch (_getTripStatus()) {
      case 'pending':
        return 'PENDING';
      case 'assigned':
        return 'ASSIGNED';
      case 'in_progress':
        return 'IN PROGRESS';
      case 'driver_completed':
        return 'AWAITING'; // Shortened from "AWAITING CONFIRMATION"
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      case 'archived':
        return 'ARCHIVED';
      default:
        return _getTripStatus().toUpperCase();
    }
  }

  /// Check if the trip is overdue
  bool _isTripOverdue() {
    final isOverdue = OverdueTripService.isTripOverdue(widget.trip);

    // Debug logging
    print('🔍 OVERDUE CHECK for trip ${widget.trip['trip_ref_number']}:');
    print('   📅 Start time: ${widget.trip['start_time']}');
    print('   📊 Status: ${widget.trip['status']}');
    print('   ⚠️ Is overdue: $isOverdue');
    print('   👤 Is operator: ${widget.isOperator}');
    print('   🚗 Is driver: ${widget.isDriver}');
    print(
        '   🔘 Show button: ${widget.isOperator && !widget.isDriver && isOverdue}');

    return isOverdue;
  }

  /// Send reminder to driver (for operators) - Enhanced with real-time delivery
  Future<void> _remindDriver() async {
    if (_isSendingReminder) return; // Prevent multiple clicks

    setState(() {
      _isSendingReminder = true;
    });

    try {
      print('🔔 ENHANCED REMINDER: Starting immediate notification process...');

      // Show immediate loading feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('📤 Sending reminder to driver...'),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Send enhanced reminder with real-time delivery
      await _sendEnhancedReminderToDriver();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('✅ Reminder sent to driver instantly!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Error sending enhanced reminder: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('❌ Failed to send reminder: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingReminder = false;
        });
      }
    }
  }

  /// Enhanced reminder delivery with multiple channels for immediate notification
  Future<void> _sendEnhancedReminderToDriver() async {
    final tripId = widget.trip['id'];
    final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
    final tripRef = widget.trip['trip_ref_number'] ?? 'TRIP-$tripId';
    final origin = widget.trip['origin'] ?? 'Unknown';
    final destination = widget.trip['destination'] ?? 'Unknown';

    if (driverId == null) {
      throw Exception('No driver assigned to trip');
    }

    print('🚀 ENHANCED REMINDER: Using optimized NotificationService...');
    print('   📋 Trip: $tripRef ($origin → $destination)');
    print('   👤 Driver ID: $driverId');

    // Use enhanced notification service for immediate delivery
    await NotificationService().sendEnhancedDriverReminder(
      tripId: tripId,
      driverId: driverId,
      tripRef: tripRef,
      origin: origin,
      destination: destination,
    );

    // Also use existing overdue service as additional fallback
    try {
      await OverdueTripService().sendReminderToDriver(tripId);
      print('✅ Fallback service reminder sent');
    } catch (fallbackError) {
      print('⚠️ Fallback reminder failed: $fallbackError');
    }

    print('🎯 ENHANCED REMINDER COMPLETE: Multi-service delivery attempted');
  }

  Color _getStatusColor() {
    // Check if trip is overdue first
    if (_isTripOverdue()) {
      return Colors.red; // Red for overdue trips
    }

    switch (_getTripStatus()) {
      case 'pending':
        return Colors.orange; // Orange for pending - needs attention
      case 'assigned':
        return Colors.blue; // Blue for assigned - ready to start
      case 'in_progress':
        return Colors.green; // Green for in progress - active
      case 'driver_completed':
        return Colors
            .orange; // Changed to orange for awaiting confirmation (both container and badge)
      case 'completed':
        return Colors.teal; // Teal for fully completed
      case 'cancelled':
        return Colors.red; // Red for cancelled
      case 'archived':
        return Colors.grey; // Grey for archived
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    // Check if trip is overdue first
    if (_isTripOverdue()) {
      return Icons.warning; // Warning icon for overdue trips
    }

    switch (_getTripStatus()) {
      case 'pending':
        return Icons.pending_actions; // Pending assignment
      case 'assigned':
        return Icons.assignment_ind; // Driver assigned
      case 'in_progress':
        return Icons.local_shipping; // Trip in progress
      case 'driver_completed':
        return Icons.rule; // Awaiting operator confirmation
      case 'completed':
        return Icons.check_circle; // Fully completed
      case 'cancelled':
        return Icons.cancel; // Cancelled
      case 'archived':
        return Icons.archive; // Archived
      default:
        return Icons.help;
    }
  }

  double _getProgressPercentage() {
    switch (_getTripStatus()) {
      case 'pending':
        return 0.0; // No progress yet
      case 'assigned':
        return 25.0; // Driver assigned but not started
      case 'in_progress':
        return 60.0; // Trip actively in progress
      case 'driver_completed':
        return 85.0; // Driver completed, waiting for operator confirmation
      case 'completed':
        return 100.0; // Fully completed
      case 'cancelled':
        return 0.0; // No progress for cancelled trips
      case 'archived':
        return 100.0; // Archived trips are complete
      default:
        return 0.0;
    }
  }

  String _formatTripId(Map<String, dynamic> trip) {
    return trip['trip_ref_number'] ??
        'TRIP-${trip['id']?.toString().substring(0, 8)}';
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'normal':
        return Colors.blue;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Check if trip is outdated (should be moved to history)
  bool _isTripOutdated() {
    final startTime = widget.trip['start_time'];
    if (startTime == null) return false;

    final tripDate = DateTime.tryParse(startTime);
    if (tripDate == null) return false;

    final today = DateTime.now();
    return tripDate.year != today.year ||
        tripDate.month != today.month ||
        tripDate.day != today.day;
  }

  // Check if trip is archived (transferred to history)
  bool _isTripArchived() {
    return widget.trip['status'] == 'archived';
  }

  // Build start time section for pending trips
  Widget _buildStartTimeSection() {
    final status = _getTripStatus();
    final startTime = widget.trip['start_time'];

    if (startTime == null) return const SizedBox.shrink();

    DateTime? scheduledTime;
    try {
      scheduledTime = DateTime.parse(startTime);
    } catch (e) {
      print('Error parsing start time: $e');
      return const SizedBox.shrink();
    }

    // Format the scheduled time
    String formattedTime = _formatDateTime(scheduledTime);
    String statusText = _getScheduleStatusText(scheduledTime, status);
    Color statusColor = _getScheduleStatusColor(scheduledTime, status);
    IconData statusIcon = _getScheduleStatusIcon(scheduledTime, status);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            statusIcon,
            color: statusColor,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Scheduled: $formattedTime',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for start time section
  String _formatDateTime(DateTime dateTime) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final tripDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    String dateStr;
    if (tripDate == today) {
      dateStr = 'Today';
    } else if (tripDate == tomorrow) {
      dateStr = 'Tomorrow';
    } else {
      dateStr = '${months[dateTime.month - 1]} ${dateTime.day}';
    }

    final hour = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final amPm = dateTime.hour >= 12 ? 'PM' : 'AM';
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$dateStr at $hour:$minute $amPm';
  }

  String _getScheduleStatusText(DateTime scheduledTime, String status) {
    final now = DateTime.now();

    switch (status) {
      case 'pending':
        if (now.isAfter(scheduledTime)) {
          return 'Trip Overdue';
        } else {
          final difference = scheduledTime.difference(now);
          if (difference.inHours < 1) {
            return 'Starting Soon';
          } else if (difference.inDays < 1) {
            return 'Starting Today';
          } else {
            return 'Scheduled';
          }
        }
      case 'assigned':
        return 'Driver Assigned';
      case 'in_progress':
        return 'Trip Started';
      case 'driver_completed':
        return 'Awaiting Confirmation'; // Full text for container display
      case 'completed':
        return 'Trip Completed';
      default:
        return status.toUpperCase();
    }
  }

  Color _getScheduleStatusColor(DateTime scheduledTime, String status) {
    final now = DateTime.now();

    switch (status) {
      case 'pending':
        if (now.isAfter(scheduledTime)) {
          return Colors.red; // Overdue
        } else {
          final difference = scheduledTime.difference(now);
          if (difference.inHours < 1) {
            return Colors.orange; // Starting soon
          } else {
            return Colors.blue; // Scheduled
          }
        }
      case 'assigned':
        return Colors.amber;
      case 'in_progress':
        return Colors.green;
      case 'driver_completed':
        return Colors
            .orange; // Changed from purple to orange for awaiting confirmation
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getScheduleStatusIcon(DateTime scheduledTime, String status) {
    final now = DateTime.now();

    switch (status) {
      case 'pending':
        if (now.isAfter(scheduledTime)) {
          return Icons.warning; // Overdue
        } else {
          return Icons.access_time; // Scheduled
        }
      case 'assigned':
        return Icons.assignment_ind;
      case 'in_progress':
        return Icons.local_shipping;
      case 'driver_completed':
        return Icons.pending_actions;
      case 'completed':
        return Icons.check_circle;
      default:
        return Icons.schedule;
    }
  }

  // Build dynamic action section based on trip status
  Widget _buildActionSection() {
    final status = _getTripStatus();

    switch (status) {
      case 'pending':
      case 'assigned':
        // For pending/assigned trips, only show action buttons if it's in today's schedule
        // Pending trips in the main "Pending Trips" page should not have View Logs/Live Map buttons
        if (widget.isToday || widget.isFromSchedule) {
          return _buildActionButtons();
        } else {
          return _buildStatusIndicator();
        }

      case 'in_progress':
      case 'driver_completed':
      case 'completed':
      case 'archived':
        // For active/completed trips, always show the action buttons
        return _buildActionButtons();

      default:
        return _buildStatusIndicator();
    }
  } // Build status indicator for pending/assigned trips

  Widget _buildStatusIndicator() {
    final status = _getTripStatus();
    String statusText;
    Color statusColor;
    IconData statusIcon;
    String statusDescription;

    switch (status) {
      case 'pending':
        statusText = 'Waiting for Assignment';
        statusColor = Colors.orange;
        statusIcon = Icons.pending_actions;
        statusDescription = 'Trip is pending driver and vehicle assignment';
        break;
      case 'assigned':
        statusText = 'Driver Assigned';
        statusColor = Colors.blue;
        statusIcon = Icons.person;
        statusDescription = 'Waiting for driver to start the trip';
        break;
      default:
        statusText = status.toUpperCase();
        statusColor = Colors.grey;
        statusIcon = Icons.info;
        statusDescription = 'Trip status: $status';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[900]!,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                statusIcon,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusDescription,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Add Remind Driver button for overdue assigned trips
          if (widget.isOperator &&
              !widget.isDriver &&
              _isTripOverdue() &&
              status == 'assigned') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _remindDriver();
                },
                icon: const Icon(Icons.notifications_active, size: 16),
                label: const Text('Remind Driver'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build action buttons for active/completed trips
  Widget _buildActionButtons() {
    List<Widget> buttons = [];
    final status = _getTripStatus();

    // Only show View Logs and Live Map buttons for trips that are NOT pending/assigned
    // OR if they are pending/assigned but in Today's Schedule (isToday/isFromSchedule)
    final shouldShowTrackingButtons =
        (status != 'pending' && status != 'assigned') ||
            (widget.isToday || widget.isFromSchedule);

    // Build the main action buttons column
    List<Widget> actionWidgets = [];

    // Remind Driver Button (only for operators on overdue trips) - MOVED TO TOP AND MADE FULL WIDTH
    if (widget.isOperator && !widget.isDriver && _isTripOverdue()) {
      print(
          '✅ ADDING REMIND DRIVER BUTTON for trip ${widget.trip['trip_ref_number']}');

      actionWidgets.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSendingReminder
                ? null
                : () async {
                    await _remindDriver();
                  },
            icon: _isSendingReminder
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.notifications_active, size: 18),
            label: Text(_isSendingReminder ? 'Sending...' : 'Remind Driver'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isSendingReminder
                  ? Colors.blue.withOpacity(0.7)
                  : Colors.blue, // CHANGED FROM ORANGE TO BLUE
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      );

      actionWidgets
          .add(const SizedBox(height: 8)); // Add spacing below remind button
    } else {
      print(
          '❌ NOT ADDING REMIND BUTTON for trip ${widget.trip['trip_ref_number']}:');
      print('   Is operator: ${widget.isOperator}');
      print('   Is driver: ${widget.isDriver}');
      print('   Is overdue: ${_isTripOverdue()}');
    }

    // View Logs Button - only for active trips or scheduled trips
    if (shouldShowTrackingButtons) {
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showViewLogsDialog(),
            icon: const Icon(Icons.visibility, size: 18),
            label: const Text('View Logs'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      );

      buttons.add(const SizedBox(width: 8));
    }

    // Live Map Button - only for active trips or scheduled trips
    if (shouldShowTrackingButtons) {
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _shouldShowLiveMap()
                ? () {
                    print('🎯 BUTTON CLICKED: Live Map button pressed!');
                    _showLiveDriverMap();
                  }
                : null,
            icon: Icon(
              _shouldShowLiveMap() ? Icons.map : Icons.map_outlined,
              size: 18,
            ),
            label: Text(
              _shouldShowLiveMap()
                  ? (_isTripArchived() ? 'Live Map' : 'Live Map')
                  : (widget.isOperator && !widget.isDriver)
                      ? (_hasDriverAssigned()
                          ? 'Trip Not Started'
                          : 'No Driver')
                      : 'Driver Not Started',
              style: TextStyle(
                fontSize: _shouldShowLiveMap() ? 14 : 12,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _shouldShowLiveMap() ? Colors.green : Colors.grey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      );
    }

    // Add the horizontal buttons row to action widgets if any buttons exist
    if (buttons.isNotEmpty) {
      actionWidgets.add(Row(children: buttons));
    }

    // If no widgets to show, return empty container
    if (actionWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: actionWidgets,
    );
  }

  // Check if trip should show live map functionality
  bool _shouldShowLiveMap() {
    final status = widget.trip['status'];

    // For operator view, show live map if driver has accepted the trip
    if (widget.isOperator && !widget.isDriver) {
      // Check if driver has accepted the trip (not just assigned)
      final hasDriverAccepted = _hasDriverAcceptedTrip();
      if (!hasDriverAccepted) {
        print('🚫 Driver has not accepted trip yet - not showing live map');
        return false;
      }

      // Show live map if driver has accepted (location may or may not be available yet)
      print(
          '✅ Driver has accepted trip - showing live map (location: ${_currentLocation != null ? 'available' : 'waiting'})');
      return true;
    }

    // Show live map for in_progress trips and archived trips that were in_progress
    return status == 'in_progress' ||
        (status == 'archived' && widget.trip['started_at'] != null);
  }

  // Check if a driver is assigned to the trip
  bool _hasDriverAssigned() {
    final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
    final hasDriver = driverId != null;
    print(
        '🚗 _hasDriverAssigned: $hasDriver (driver_id: ${widget.trip['driver_id']}, sub_driver_id: ${widget.trip['sub_driver_id']})');
    return hasDriver;
  }

  // Check if driver has accepted the trip assignment
  bool _hasDriverAcceptedTrip() {
    final status = widget.trip['status'];
    final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
    final acceptedAt = widget.trip['accepted_at'];
    final startedAt = widget.trip['started_at'];

    print('🔍 ACCEPTANCE CHECK for trip ${widget.trip['trip_ref_number']}:');
    print('   📊 Status: $status');
    print('   👤 Driver ID: $driverId');
    print('   ✅ Accepted at: $acceptedAt');
    print('   🚀 Started at: $startedAt');
    print('   📍 Current location: ${_currentLocation != null}');
    print('   🕐 Last location update: $_lastLocationUpdate');

    // If no driver assigned, they can't have accepted
    if (driverId == null) {
      print('❌ No driver assigned');
      return false;
    }

    // Driver has accepted if:
    // 1. Trip status is 'in_progress' (driver started the trip)
    // 2. Trip has a started_at timestamp (driver actually began the trip)
    // 3. Trip has accepted_at timestamp (explicit acceptance)
    // 4. Trip status is 'assigned' AND driver is actively sharing recent location
    final hasStarted = status == 'in_progress' || startedAt != null;
    final hasExplicitAcceptance = acceptedAt != null;
    final isAssigned = status == 'assigned';

    if (hasStarted) {
      if (status == 'in_progress') {
        print('✅ Trip is in progress - driver has started');
      } else {
        print('✅ Trip has started_at timestamp - driver has started');
      }
      return true;
    }

    if (hasExplicitAcceptance) {
      print('✅ Driver has explicitly accepted trip (accepted_at: $acceptedAt)');
      return true;
    }

    if (isAssigned) {
      // For assigned trips, check if driver is actively sharing recent location
      final isSharingLocation =
          _currentLocation != null && _lastLocationUpdate != null;
      if (isSharingLocation) {
        // Make sure the location is very recent (within last 5 minutes) to indicate active acceptance
        final timeDiff =
            DateTime.now().difference(_lastLocationUpdate!).inMinutes;
        if (timeDiff <= 5) {
          print(
              '✅ Driver has accepted trip and is actively sharing location (${timeDiff}min ago)');
          return true;
        } else {
          print(
              '⏳ Trip is assigned but driver location is stale (${timeDiff}min ago) - not showing map');
          return false;
        }
      } else {
        print(
            '⏳ Trip is assigned but driver not yet sharing location - not showing map');
        return false;
      }
    }

    print('❌ Driver has not accepted trip (status: $status)');
    return false;
  }

  void _showCancelConfirmation(
      BuildContext context, Map<String, dynamic> trip) {
    TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.blue.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.cancel_outlined,
                      color: Colors.blue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Cancel Trip',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to cancel trip',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${trip['trip_ref_number'] ?? 'TRIP-${trip['id']}'}?',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: reasonController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Cancellation Reason',
                    labelStyle: TextStyle(
                      color: Colors.grey.withOpacity(0.7),
                      fontSize: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.blue.withOpacity(0.6),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 20),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Cancel',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue,
                            Colors.blue.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            if (widget.onCancel != null) {
                              widget.onCancel!(trip, reasonController.text);
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Cancel Trip',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(
      BuildContext context, Map<String, dynamic> trip) {
    TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.red.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Delete Trip',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to permanently delete trip',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${trip['trip_ref_number'] ?? 'TRIP-${trip['id']}'}?',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: reasonController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Deletion Reason',
                    labelStyle: TextStyle(
                      color: Colors.grey.withOpacity(0.7),
                      fontSize: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.red.withOpacity(0.6),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 20),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Cancel',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.red,
                            Colors.red.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            if (widget.onDelete != null) {
                              widget.onDelete!(trip, reasonController.text);
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Delete Trip',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isTripCompleted() {
    final status = _getTripStatus();
    // Trip is only truly completed when operator has confirmed it
    return status == 'completed' &&
        widget.trip['operator_confirmed_at'] != null;
  }

  // Check if trip needs operator confirmation
  bool _needsOperatorConfirmation() {
    // Trip needs operator confirmation if it's driver_completed status
    // AND it's being displayed in today's schedule (not in pending trips)
    return widget.trip['status'] == 'driver_completed' &&
        (widget.isToday || widget.isFromSchedule);
  }

  @override
  Widget build(BuildContext context) {
    final priority = widget.trip['priority'] ?? 'normal';
    final isOutdated = _isTripOutdated();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER SECTION - Trip ID and Badges
                Row(
                  children: [
                    // Trip Icon and ID
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.local_shipping,
                        size: 24,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trip ID',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTripId(widget.trip),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    // Status Badges
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Priority Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getPriorityColor(priority)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _getPriorityColor(priority)
                                  .withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            priority.toUpperCase(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: _getPriorityColor(priority),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _getStatusColor().withValues(alpha: 0.15),
                                _getStatusColor().withValues(alpha: 0.08),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _getStatusColor().withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _getDisplayStatus(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // START TIME DISPLAY - Show scheduled start time for pending trips
                _buildStartTimeSection(),

                const SizedBox(height: 16),

                // PROGRESS BAR (Real-time tracking)
                if (widget.showRealTimeTracking) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getStatusIcon(),
                            color: Colors
                                .blue, // Always blue instead of dynamic status color
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Trip Progress',
                            style: const TextStyle(
                              color: Colors
                                  .blue, // Always blue instead of dynamic status color
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_getProgressPercentage().toInt()}%',
                            style: const TextStyle(
                              color: Colors
                                  .blue, // Always blue instead of dynamic status color
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _getProgressPercentage() / 100,
                        backgroundColor: Colors.grey.withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(Colors
                            .blue), // Always blue instead of dynamic status color
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ORIGIN AND DESTINATION - Minimized view (icons only)
                if (!_isExpanded) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Origin - Bottom Left (icon only)
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: Colors.blue, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.trip['origin'] ?? 'Not specified',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[300],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Destination - Bottom Right (icon only)
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Icon(Icons.location_on,
                                color: Colors.red, size: 14),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                widget.trip['destination'] ?? 'Not specified',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[300],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                // VEHICLE INFORMATION (if available)
                if (_isExpanded) ...[
                  const SizedBox(height: 12),
                  _buildVehicleInfoSection(),
                ],

                // EXPANDED CONTENT
                if (_isExpanded) ...[
                  const SizedBox(height: 16),

                  // DRIVER INFORMATION (Expanded view)
                  Row(
                    children: [
                      // Main Driver
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[700]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.person,
                                      color: Colors.white, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Main Driver',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                () {
                                  final mainDriver =
                                      widget.trip['driver'] ?? {};
                                  if (mainDriver['first_name'] != null &&
                                      mainDriver['last_name'] != null) {
                                    return '${mainDriver['first_name']} ${mainDriver['last_name']}';
                                  }
                                  return mainDriver['username'] ?? 'Unassigned';
                                }(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Sub Driver
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[700]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.person_add,
                                      color: Colors.white, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Sub Driver',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                () {
                                  final subDriver =
                                      widget.trip['sub_driver'] ?? {};
                                  if (subDriver['first_name'] != null &&
                                      subDriver['last_name'] != null) {
                                    return '${subDriver['first_name']} ${subDriver['last_name']}';
                                  }
                                  return subDriver['username'] ?? 'None';
                                }(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ORIGIN AND DESTINATION - Expanded view (with labels)
                  Row(
                    children: [
                      // Origin - Left
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.location_on,
                                      color: Colors.blue, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Origin',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.trip['origin'] ?? 'Not specified',
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Destination - Right
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.location_on,
                                      color: Colors.red, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Destination',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.trip['destination'] ?? 'Not specified',
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Real-time Location Tracking
                  if (widget.showRealTimeTracking &&
                      _currentLocation != null &&
                      _getTripStatus() == 'in_progress') ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.my_location, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Live Location',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                Text(
                                  '${_currentLocation!.latitude.toStringAsFixed(4)}, ${_currentLocation!.longitude.toStringAsFixed(4)}',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _showMap = !_showMap;
                              });
                            },
                            icon: Icon(
                              _showMap ? Icons.map : Icons.map_outlined,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Driver Status Indicator
                  if (_getTripStatus() == 'assigned') ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Driver Status',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                                Text(
                                  _driverTripStatus ??
                                      'Checking driver status...',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                                // Show driver location if available (for operator view)
                                if (widget.isOperator &&
                                    !widget.isDriver &&
                                    _currentLocation != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Driver Location: ${_currentLocation!.latitude.toStringAsFixed(4)}, ${_currentLocation!.longitude.toStringAsFixed(4)}',
                                    style: TextStyle(
                                      color: Colors.green[400],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Show map toggle for operator view when driver has accepted
                          if (widget.isOperator &&
                              !widget.isDriver &&
                              _shouldShowLiveMap())
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _showMap = !_showMap;
                                });
                              },
                              icon: Icon(
                                _showMap ? Icons.map : Icons.map_outlined,
                                color: Colors.green,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Beautiful Live Tracking Map View - Only show when driver has accepted
                  if (widget.showRealTimeTracking &&
                      _showMap &&
                      _shouldShowLiveMap()) ...[
                    // Debug info for operator view
                    if (widget.isOperator && !widget.isDriver) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '🔍 DEBUG INFO (Operator View)',
                              style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '📍 Driver Location: ${_currentLocation?.latitude.toStringAsFixed(6)}, ${_currentLocation?.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(
                                  color: Colors.blue, fontSize: 12),
                            ),
                            Text(
                              '🚗 Driver ID: ${widget.trip['driver_id'] ?? widget.trip['sub_driver_id'] ?? 'None'}',
                              style: const TextStyle(
                                  color: Colors.blue, fontSize: 12),
                            ),
                            Text(
                              '📱 Trip Status: ${_driverTripStatus ?? 'Unknown'}',
                              style: const TextStyle(
                                  color: Colors.blue, fontSize: 12),
                            ),
                            Text(
                              '🎯 Location Source: ${_currentLocation != null ? 'Driver GPS' : 'Not Available'}',
                              style: const TextStyle(
                                  color: Colors.blue, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () async {
                                print(
                                    '🔄 FORCE REFRESH: Manual refresh requested');
                                await _loadDriverLocation();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                              ),
                              child: const Text('Force Refresh',
                                  style: TextStyle(fontSize: 10)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    BeautifulLiveTrackingMap(
                      trip: widget.trip,
                      driverId: widget.trip['driver_id'] ??
                          widget.trip['sub_driver_id'] ??
                          '',
                      height: 200,
                      isOperatorView: widget.isOperator && !widget.isDriver,
                      driverLocation: widget.isOperator && !widget.isDriver
                          ? (_currentLocation != null
                              ? latlong2.LatLng(_currentLocation!.latitude,
                                  _currentLocation!.longitude)
                              : null)
                          : null,
                      onProgressUpdate: (percentage) {
                        print('Progress: $percentage%');
                      },
                      onLocationUpdate: (location) {
                        print('Location: $location');
                      },
                      onDistanceUpdate: (distance) {
                        print('Total distance: $distance km');
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Dynamic Action Section - Show different content based on trip status
                  _buildActionSection(),

                  const SizedBox(height: 12),

                  // Trip Control Buttons (Driver/Operator specific)

                  // Driver: Start Trip Button (for assigned trips)
                  if (widget.isDriver && _getTripStatus() == 'assigned') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _startTrip,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.play_arrow, size: 18),
                        label: Text(_isLoading ? 'Starting...' : 'Start Trip'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Driver: Complete Trip Button (for in_progress trips)
                  if (widget.isDriver && _getTripStatus() == 'in_progress') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _completeTrip,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 18),
                        label: Text(
                            _isLoading ? 'Completing...' : 'Complete Trip'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Driver: Complete Trip Button (for in_progress trips)
                  if (widget.isDriver && _getTripStatus() == 'in_progress') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _completeTrip,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 18),
                        label: Text(
                            _isLoading ? 'Completing...' : 'Complete Trip'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Operator: Confirm Completion Button (for completed trips that need operator confirmation)
                  if (widget.isOperator && _needsOperatorConfirmation()) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _confirmCompletion,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle, size: 18),
                        label: Text(_isLoading
                            ? 'Confirming...'
                            : 'Confirm Completion'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Operator: Complete Trip Button (for archived trips that are not completed)
                  if (widget.isOperator &&
                      _isTripArchived() &&
                      _getTripStatus() != 'completed') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _completeTrip,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 18),
                        label: Text(
                            _isLoading ? 'Completing...' : 'Complete Trip'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Outdated Trip Warning
                  if (isOutdated && !_isTripArchived()) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This trip is from a previous date and will be moved to History.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Archived Trip Info
                  if (_isTripArchived()) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.archive, color: Colors.blue, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This trip has been transferred to History. All functionality remains available.',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Assignment Actions for Pending Trips (Operator Only)
                  if (widget.isOperator && _getTripStatus() == 'pending') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey[900]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trip Assignment',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _showAssignDriverDialog(),
                                  icon: const Icon(Icons.person_add, size: 18),
                                  label: const Text('Assign Driver'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _showAssignVehicleDialog(),
                                  icon: const Icon(Icons.local_shipping,
                                      size: 18),
                                  label: const Text('Assign Truck'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Cancel & Delete Actions for All Trips (Operator Only)
                  if (widget.isOperator && !_isTripCompleted()) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey[900]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trip Management',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    print(
                                        '🔶 CANCEL BUTTON: Pressed. onCancel callback is: ${widget.onCancel != null ? 'NOT NULL' : 'NULL'}');
                                    print(
                                        '🔶 CANCEL BUTTON: isOperator: ${widget.isOperator}, isDriver: ${widget.isDriver}');
                                    _showCancelConfirmation(
                                        context, widget.trip);
                                  },
                                  icon: const Icon(Icons.cancel, size: 18),
                                  label: const Text('Cancel Trip'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    print(
                                        '🔴 DELETE BUTTON: Pressed. onDelete callback is: ${widget.onDelete != null ? 'NOT NULL' : 'NULL'}');
                                    print(
                                        '🔴 DELETE BUTTON: isOperator: ${widget.isOperator}, isDriver: ${widget.isDriver}');
                                    _showDeleteConfirmation(
                                        context, widget.trip);
                                  },
                                  icon: const Icon(Icons.delete, size: 18),
                                  label: const Text('Delete Trip'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Show View Logs Dialog
  void _showViewLogsDialog() {
    showDialog(
      context: context,
      builder: (context) => ViewLogsModal(trip: widget.trip),
    );
  }

  // Show Enhanced Map with smooth navigation
  void _showLiveDriverMap() {
    print('🎯 ENHANCED MODAL: Opening beautiful live tracking map!');

    // Check if trip can show live map
    if (!_shouldShowLiveMap()) {
      final hasDriverAccepted = _hasDriverAcceptedTrip();
      String message;

      if (_isTripArchived()) {
        message =
            'Trip map is available for archived trips that were in progress.';
      } else if (widget.isOperator && !widget.isDriver) {
        if (!_hasDriverAssigned()) {
          message =
              'No driver assigned to this trip yet. Live tracking will be available once a driver is assigned and starts the trip.';
        } else if (!hasDriverAccepted) {
          message =
              'Trip not started yet. Live tracking will be available once driver starts the trip.';
        } else {
          message = 'Driver location is not available yet.';
        }
      } else {
        message =
            'Live map is only available when the driver has started the trip.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
    if (driverId != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.95,
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar with improved design
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Header with smooth animations
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          const Icon(Icons.map, color: Colors.blue, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isTripArchived()
                            ? 'Trip History Map'
                            : (widget.isOperator &&
                                    !widget.isDriver &&
                                    _getTripStatus() == 'assigned' &&
                                    _currentLocation != null)
                                ? 'Driver Location Tracking'
                                : 'Live Trip Tracking',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Live Tracking Map (Full Screen)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: BeautifulLiveTrackingMap(
                    trip: widget.trip,
                    driverId: driverId,
                    height: 400,
                    isOperatorView: widget.isOperator && !widget.isDriver,
                    driverLocation: widget.isOperator && !widget.isDriver
                        ? (_currentLocation != null
                            ? latlong2.LatLng(_currentLocation!.latitude,
                                _currentLocation!.longitude)
                            : null)
                        : null,
                    onProgressUpdate: (percentage) {
                      print('Progress: $percentage%');
                    },
                    onLocationUpdate: (location) {
                      print('Location: $location');
                    },
                    onDistanceUpdate: (distance) {
                      print('Total distance: $distance km');
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildVehicleInfoSection() {
    // Extract vehicle information from trip data
    final vehicleId = widget.trip['vehicle_id'];

    if (vehicleId == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.local_shipping, color: Colors.grey, size: 16),
            SizedBox(width: 8),
            Text(
              'No Vehicle Assigned',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    // Build vehicle info display
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getVehicleWithColor(vehicleId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'Loading vehicle information...',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final vehicle = snapshot.data;
        if (vehicle == null) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Text(
                  'Vehicle information not available',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[900]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.local_shipping, color: Colors.orange, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Assigned Vehicle',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicle['plate_number'] ?? 'Unknown Plate',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'
                              .trim(),
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Color indicator
                  _buildVehicleColorDisplay(vehicle),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVehicleColorDisplay(Map<String, dynamic> vehicle) {
    final colorName = vehicle['color'];

    if (colorName != null && colorName.toString().isNotEmpty) {
      Color displayColor = _getColorFromName(colorName);

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: displayColor,
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.white.withOpacity(0.3), width: 1),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            colorName,
            style: TextStyle(
              color: Colors.grey[300],
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      );
    }

    return Text(
      'No Color',
      style: TextStyle(
        color: Colors.grey.withOpacity(0.5),
        fontSize: 10,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Future<Map<String, dynamic>?> _getVehicleWithColor(String vehicleId) async {
    try {
      final response = await Supabase.instance.client
          .from('vehicles')
          .select('*')
          .eq('id', vehicleId)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error fetching vehicle with color: $e');
      return null;
    }
  }

  Color _getColorFromName(String? colorName) {
    if (colorName == null || colorName.isEmpty) return Colors.grey;

    switch (colorName.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'pink':
        return Colors.pink;
      case 'brown':
        return Colors.brown;
      case 'white':
        return Colors.white;
      default:
        return Colors.grey;
    }
  }

  // Show assign driver dialog
  void _showAssignDriverDialog() {
    if (widget.trip.isEmpty || widget.trip['id'] == null) {
      debugPrint('Invalid trip data');
      return;
    }

    // Use the callback if provided, otherwise show simple dialog
    if (widget.onAssignDriver != null) {
      widget.onAssignDriver!(widget.trip);
    } else {
      // Fallback simple dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Assign Driver'),
          content: const Text(
              'Driver assignment feature not available in this context.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // Show assign vehicle dialog
  void _showAssignVehicleDialog() {
    if (widget.trip.isEmpty || widget.trip['id'] == null) {
      debugPrint('Invalid trip data');
      return;
    }

    // Use the callback if provided, otherwise show simple dialog
    if (widget.onAssignVehicle != null) {
      widget.onAssignVehicle!(widget.trip);
    } else {
      // Fallback simple dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Assign Vehicle'),
          content: const Text(
              'Vehicle assignment feature not available in this context.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}

// Simple Assignment Dialogs
class AssignDriverDialog extends StatefulWidget {
  final Map<String, dynamic> trip;
  final VoidCallback? onAssignmentComplete;

  const AssignDriverDialog({
    super.key,
    required this.trip,
    this.onAssignmentComplete,
  });

  @override
  State<AssignDriverDialog> createState() => _AssignDriverDialogState();
}

class _AssignDriverDialogState extends State<AssignDriverDialog> {
  List<Map<String, dynamic>> drivers = [];
  String? selectedDriverId;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('id, first_name, last_name, profile_picture, role')
          .eq('role', 'driver');

      setState(() {
        drivers = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      debugPrint('Error loading drivers: $e');
    }
  }

  Future<void> _assignDriver() async {
    if (selectedDriverId == null) return;

    try {
      await Supabase.instance.client.from('trips').update({
        'driver_id': selectedDriverId,
        'status': 'assigned',
      }).eq('id', widget.trip['id']);

      // Send assignment notification to driver
      try {
        final startTime = DateTime.parse(widget.trip['start_time']);
        await NotificationService().sendTripAssignmentNotification(
          driverId: selectedDriverId!,
          tripId: widget.trip['id'],
          tripRefNumber: widget.trip['trip_ref_number'] ?? 'Unknown',
          origin: widget.trip['origin'] ?? 'Unknown Origin',
          destination: widget.trip['destination'] ?? 'Unknown Destination',
          startTime: startTime,
        );
        print('✅ Assignment notification sent to driver');
      } catch (notifError) {
        print('⚠️ Assignment notification failed: $notifError');
        // Continue even if notification fails
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onAssignmentComplete?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver assigned successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error assigning driver: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assign Driver',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (drivers.isEmpty)
              const Text('No drivers available')
            else ...[
              const Text('Select a driver:'),
              const SizedBox(height: 12),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: drivers.length,
                  itemBuilder: (context, index) {
                    final driver = drivers[index];
                    final isSelected = selectedDriverId == driver['id'];

                    return ListTile(
                      selected: isSelected,
                      title: Text(
                          '${driver['first_name']} ${driver['last_name']}'),
                      onTap: () {
                        setState(() {
                          selectedDriverId = driver['id'];
                        });
                      },
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: selectedDriverId != null ? _assignDriver : null,
                  child: const Text('Assign'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Simple Vehicle Assignment Dialog
class AssignVehicleDialog extends StatefulWidget {
  final Map<String, dynamic> trip;
  final VoidCallback? onAssignmentComplete;

  const AssignVehicleDialog({
    super.key,
    required this.trip,
    this.onAssignmentComplete,
  });

  @override
  State<AssignVehicleDialog> createState() => _AssignVehicleDialogState();
}

class _AssignVehicleDialogState extends State<AssignVehicleDialog> {
  List<Map<String, dynamic>> vehicles = [];
  String? selectedVehicleId;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    try {
      final response = await Supabase.instance.client
          .from('vehicles')
          .select('*')
          .eq('status', 'Available');

      setState(() {
        vehicles = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      debugPrint('Error loading vehicles: $e');
    }
  }

  Future<void> _assignVehicle() async {
    if (selectedVehicleId == null) return;

    try {
      await Supabase.instance.client.from('trips').update({
        'vehicle_id': selectedVehicleId,
      }).eq('id', widget.trip['id']);

      if (mounted) {
        Navigator.of(context).pop();
        widget.onAssignmentComplete?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle assigned successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error assigning vehicle: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assign Vehicle',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (vehicles.isEmpty)
              const Text('No vehicles available')
            else ...[
              const Text('Select a vehicle:'),
              const SizedBox(height: 12),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: vehicles.length,
                  itemBuilder: (context, index) {
                    final vehicle = vehicles[index];
                    final isSelected = selectedVehicleId == vehicle['id'];

                    return ListTile(
                      selected: isSelected,
                      title: Text(
                          '${vehicle['plate_number']} - ${vehicle['make']} ${vehicle['model']}'),
                      subtitle: vehicle['color'] != null
                          ? Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: _getColorFromName(vehicle['color']),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Text(vehicle['color']),
                              ],
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          selectedVehicleId = vehicle['id'];
                        });
                      },
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: selectedVehicleId != null ? _assignVehicle : null,
                  child: const Text('Assign'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorFromName(String? colorName) {
    if (colorName == null || colorName.isEmpty) return Colors.grey;

    switch (colorName.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'pink':
        return Colors.pink;
      case 'brown':
        return Colors.brown;
      case 'white':
        return Colors.white;
      default:
        return Colors.grey;
    }
  }
}
