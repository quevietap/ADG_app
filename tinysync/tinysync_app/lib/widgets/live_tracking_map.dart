import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class LiveTrackingMap extends StatefulWidget {
  final String tripId;
  final String driverId;
  final double height;
  final bool showDriverInfo;
  final Function(LatLng)? onLocationUpdate;

  const LiveTrackingMap({
    super.key,
    required this.tripId,
    required this.driverId,
    this.height = 400,
    this.showDriverInfo = true,
    this.onLocationUpdate,
  });

  @override
  State<LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends State<LiveTrackingMap> {
  GoogleMapController? _mapController;
  RealtimeChannel? _locationSubscription;

  // Tracking data
  LatLng? _currentLocation;
  List<LatLng> _tripPath = [];
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // Driver info
  String _driverStatus = 'Unknown';
  double _currentSpeed = 0.0;
  String _lastUpdate = 'Never';

  @override
  void initState() {
    super.initState();
    _initializeLiveTracking();
    _loadTripHistory();
  }

  @override
  void dispose() {
    _locationSubscription?.unsubscribe();
    super.dispose();
  }

  /// Initialize real-time location tracking
  void _initializeLiveTracking() {
    try {
      print(
          '🚀 Starting live tracking for trip: ${widget.tripId}, driver: ${widget.driverId}');

      _locationSubscription = Supabase.instance.client
          .channel('live_tracking_${widget.driverId}_${widget.tripId}')
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
              print('📍 Live location INSERT received: ${payload.newRecord}');
              // Only process if it's for the current trip
              final receivedTripId = payload.newRecord['trip_id'];
              if (receivedTripId == widget.tripId) {
                _handleLiveLocationUpdate(payload.newRecord);
              } else {
                print(
                    '⚠️ Ignoring location for different trip: $receivedTripId');
              }
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
              print('📍 Live location UPDATE received: ${payload.newRecord}');
              // Only process if it's for the current trip
              final receivedTripId = payload.newRecord['trip_id'];
              if (receivedTripId == widget.tripId) {
                _handleLiveLocationUpdate(payload.newRecord);
              } else {
                print(
                    '⚠️ Ignoring location update for different trip: $receivedTripId');
              }
            },
          )
          .subscribe();

      print(
          '✅ Live tracking subscription active for driver: ${widget.driverId}');
    } catch (e) {
      print('❌ Error initializing live tracking: $e');
    }
  }

  /// Handle real-time location updates
  void _handleLiveLocationUpdate(Map<String, dynamic> locationData) {
    try {
      final lat = locationData['latitude'] as double?;
      final lng = locationData['longitude'] as double?;
      final speed = locationData['speed'] as double?;
      final timestamp = locationData['timestamp'] as String?;

      if (lat != null && lng != null) {
        final newLocation = LatLng(lat, lng);

        setState(() {
          _currentLocation = newLocation;
          _tripPath.add(newLocation);
          _currentSpeed = speed ?? 0.0;
          _lastUpdate = timestamp ?? DateTime.now().toIso8601String();
          _driverStatus = 'Moving';
        });

        // Update markers and polylines
        _updateMapElements();

        // Animate to new location
        _animateToLocation(newLocation);

        // Notify parent widget
        widget.onLocationUpdate?.call(newLocation);

        print(
            '🗺️ Map updated - Location: $lat, $lng, Speed: ${_currentSpeed.toStringAsFixed(1)} km/h');
      }
    } catch (e) {
      print('❌ Error handling live location update: $e');
    }
  }

  /// Load trip history for path display
  Future<void> _loadTripHistory() async {
    try {
      final response = await Supabase.instance.client
          .from('driver_locations')
          .select('latitude, longitude, timestamp')
          .eq('trip_id', widget.tripId)
          .order('timestamp', ascending: true);

      if (response.isNotEmpty) {
        final locations = response as List<dynamic>;
        setState(() {
          _tripPath = locations
              .map((loc) => LatLng(
                    loc['latitude'] as double,
                    loc['longitude'] as double,
                  ))
              .toList();
        });

        if (_tripPath.isNotEmpty) {
          _currentLocation = _tripPath.last;
          _updateMapElements();
        }

        print('📍 Loaded ${_tripPath.length} historical locations');
      }
    } catch (e) {
      print('❌ Error loading trip history: $e');
    }
  }

  /// Update map markers and polylines
  void _updateMapElements() {
    setState(() {
      _markers.clear();
      _polylines.clear();

      // Add current location marker
      if (_currentLocation != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: _currentLocation!,
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: 'Driver Location',
              snippet: 'Speed: ${_currentSpeed.toStringAsFixed(1)} km/h',
            ),
          ),
        );
      }

      // Add trip path polyline
      if (_tripPath.length > 1) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('trip_path'),
            points: _tripPath,
            color: Colors.blue,
            width: 4,
            patterns: const [],
          ),
        );
      }
    });
  }

  /// Animate map to new location
  void _animateToLocation(LatLng location) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: location,
          zoom: 16.0,
          tilt: 0.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Google Map
            GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                if (_currentLocation != null) {
                  _animateToLocation(_currentLocation!);
                }
              },
              initialCameraPosition: CameraPosition(
                target: _currentLocation ?? const LatLng(0.0, 0.0),
                zoom: _currentLocation != null
                    ? 14.0
                    : 2.0, // World view until GPS data arrives
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              mapType: MapType.normal,
              zoomControlsEnabled: false,
            ),

            // Driver info overlay
            if (widget.showDriverInfo)
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Live Tracking',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Status: $_driverStatus',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Speed: ${_currentSpeed.toStringAsFixed(1)} km/h',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Path: ${_tripPath.length} points',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Last Update: ${_lastUpdate.substring(11, 19)}',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

            // Connection status indicator
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color:
                      _locationSubscription != null ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
