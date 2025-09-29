import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/google_maps_service.dart';
import 'dart:async';
import 'dart:math';

class HighPerformanceGoogleMap extends StatefulWidget {
  final List<LatLng> tripPath;
  final LatLng? currentLocation;
  final LatLng? startLocation;
  final LatLng? endLocation;
  final List<LatLng>? waypoints;
  final double height;
  final bool showControls;
  final bool showTraffic;
  final bool showMyLocation;
  final Function(LatLng)? onLocationChanged;
  final Function(String)? onAddressResolved;
  final GoogleMapController? mapController;

  const HighPerformanceGoogleMap({
    super.key,
    required this.tripPath,
    this.currentLocation,
    this.startLocation,
    this.endLocation,
    this.waypoints,
    this.height = 300,
    this.showControls = true,
    this.showTraffic = false,
    this.showMyLocation = true,
    this.onLocationChanged,
    this.onAddressResolved,
    this.mapController,
  });

  @override
  State<HighPerformanceGoogleMap> createState() =>
      _HighPerformanceGoogleMapState();
}

class _HighPerformanceGoogleMapState extends State<HighPerformanceGoogleMap> {
  late GoogleMapController _mapController;
  final GoogleMapsService _mapsService = GoogleMapsService();
  final OptimizedLocationTracker _locationTracker = OptimizedLocationTracker();

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {};

  LatLng? _currentLocation;
  bool _isLoading = true;
  bool _isTracking = false;
  String? _currentAddress;

  // Performance optimization
  Timer? _updateTimer;
  static const Duration _updateInterval = Duration(milliseconds: 500);
  static const double _minDistanceForUpdate = 5.0; // meters

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    _locationTracker.stopTracking();
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Get current location with high accuracy
      _currentLocation = await _mapsService.getCurrentLocation();
      if (_currentLocation != null) {
        widget.onLocationChanged?.call(_currentLocation!);

        // Resolve address
        _currentAddress = await _mapsService.reverseGeocode(_currentLocation!);
        widget.onAddressResolved?.call(_currentAddress ?? 'Unknown location');
      }

      // Build markers and polylines
      await _buildMapElements();

      // Start location tracking if enabled
      if (widget.showMyLocation) {
        await _startLocationTracking();
      }

      setState(() {
        _isLoading = false;
      });

      // Center map on optimal location
      _centerMapOnOptimalLocation();
    } catch (e) {
      print('❌ Error initializing map: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _buildMapElements() async {
    final markers = <Marker>{};
    final polylines = <Polyline>{};
    final circles = <Circle>{};

    // Add start marker
    if (widget.startLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('start'),
        position: widget.startLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(
          title: 'Start Point',
          snippet: 'Trip starting location',
        ),
      ));
    }

    // Add end marker
    if (widget.endLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('end'),
        position: widget.endLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(
          title: 'End Point',
          snippet: 'Trip destination',
        ),
      ));
    }

    // Add waypoint markers
    if (widget.waypoints != null) {
      for (int i = 0; i < widget.waypoints!.length; i++) {
        markers.add(Marker(
          markerId: MarkerId('waypoint_$i'),
          position: widget.waypoints![i],
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: 'Waypoint ${i + 1}',
            snippet: 'Intermediate stop',
          ),
        ));
      }
    }

    // Add current location marker with pulsing effect
    if (_currentLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('current_location'),
        position: _currentLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(
          title: 'Current Location',
          snippet: _currentAddress ?? 'Your current position',
        ),
        flat: true,
        rotation: 0, // Will be updated for bearing
      ));

      // Add accuracy circle
      circles.add(Circle(
        circleId: const CircleId('accuracy_circle'),
        center: _currentLocation!,
        radius: 20, // 20 meter accuracy circle
        fillColor: Colors.blue.withOpacity(0.2),
        strokeColor: Colors.blue.withOpacity(0.5),
        strokeWidth: 2,
      ));
    }

    // Build optimized route
    if (widget.tripPath.length > 1) {
      // Use Google Maps API for accurate routing
      List<LatLng> optimizedRoute = widget.tripPath;

      if (widget.startLocation != null && widget.endLocation != null) {
        try {
          optimizedRoute = await _mapsService.getRoute(
            widget.startLocation!,
            widget.endLocation!,
            waypoints: widget.waypoints,
            mode: 'driving',
          );
        } catch (e) {
          print('⚠️ Using fallback route: $e');
        }
      }

      polylines.add(Polyline(
        polylineId: const PolylineId('trip_route'),
        points: optimizedRoute,
        color: Colors.blue,
        width: 4,
        geodesic: true,
      ));

      // Add shadow effect
      polylines.add(Polyline(
        polylineId: const PolylineId('trip_route_shadow'),
        points: optimizedRoute,
        color: Colors.black.withOpacity(0.3),
        width: 6,
        geodesic: true,
      ));
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
      _circles = circles;
    });
  }

  Future<void> _startLocationTracking() async {
    try {
      await _locationTracker.startTracking(
        accuracy: LocationAccuracy.high,
        onLocationUpdate: (newLocation) {
          if (mounted) {
            setState(() {
              _currentLocation = newLocation;
            });

            // Update current location marker
            _updateCurrentLocationMarker(newLocation);

            // Update accuracy circle
            _updateAccuracyCircle(newLocation);

            // Resolve address
            _resolveAddress(newLocation);

            widget.onLocationChanged?.call(newLocation);
          }
        },
      );

      setState(() {
        _isTracking = true;
      });
    } catch (e) {
      print('❌ Error starting location tracking: $e');
    }
  }

  void _updateCurrentLocationMarker(LatLng newLocation) {
    final updatedMarkers = Set<Marker>.from(_markers);

    // Remove old current location marker
    updatedMarkers
        .removeWhere((marker) => marker.markerId.value == 'current_location');

    // Add new current location marker
    updatedMarkers.add(Marker(
      markerId: const MarkerId('current_location'),
      position: newLocation,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow: InfoWindow(
        title: 'Current Location',
        snippet: _currentAddress ?? 'Your current position',
      ),
      flat: true,
    ));

    setState(() {
      _markers = updatedMarkers;
    });
  }

  void _updateAccuracyCircle(LatLng newLocation) {
    final updatedCircles = Set<Circle>.from(_circles);

    // Remove old accuracy circle
    updatedCircles
        .removeWhere((circle) => circle.circleId.value == 'accuracy_circle');

    // Add new accuracy circle
    updatedCircles.add(Circle(
      circleId: const CircleId('accuracy_circle'),
      center: newLocation,
      radius: 20,
      fillColor: Colors.blue.withOpacity(0.2),
      strokeColor: Colors.blue.withOpacity(0.5),
      strokeWidth: 2,
    ));

    setState(() {
      _circles = updatedCircles;
    });
  }

  Future<void> _resolveAddress(LatLng location) async {
    try {
      final address = await _mapsService.reverseGeocode(location);
      if (address != null && address != _currentAddress) {
        setState(() {
          _currentAddress = address;
        });
        widget.onAddressResolved?.call(address);
      }
    } catch (e) {
      print('❌ Error resolving address: $e');
    }
  }

  void _centerMapOnOptimalLocation() {
    if (_currentLocation != null) {
      _mapController.animateCamera(
        CameraUpdate.newLatLngZoom(_currentLocation!, 15.0),
      );
    } else if (widget.startLocation != null) {
      _mapController.animateCamera(
        CameraUpdate.newLatLngZoom(widget.startLocation!, 12.0),
      );
    } else if (widget.tripPath.isNotEmpty) {
      _mapController.animateCamera(
        CameraUpdate.newLatLngZoom(widget.tripPath.first, 12.0),
      );
    }
  }

  void _fitBoundsToPath() {
    if (widget.tripPath.length > 1) {
      final bounds = _calculateBounds(widget.tripPath);
      _mapController.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50.0),
      );
    }
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    double? minLat, maxLat, minLng, maxLng;

    for (final point in points) {
      minLat = minLat == null ? point.latitude : min(minLat, point.latitude);
      maxLat = maxLat == null ? point.latitude : max(maxLat, point.latitude);
      minLng = minLng == null ? point.longitude : min(minLng, point.longitude);
      maxLng = maxLng == null ? point.longitude : max(maxLng, point.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading high-accuracy map...'),
            ],
          ),
        ),
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Google Map
            GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
              },
              initialCameraPosition: CameraPosition(
                target: _currentLocation ??
                    widget.startLocation ??
                    const LatLng(
                        0.0, 0.0), // Will be updated with real GPS data
                zoom: 15.0,
              ),
              markers: _markers,
              polylines: _polylines,
              circles: _circles,
              myLocationEnabled: widget.showMyLocation,
              myLocationButtonEnabled: false, // We'll add custom button
              trafficEnabled: widget.showTraffic,
              mapType: MapType.normal,
              zoomControlsEnabled: false, // We'll add custom controls
              compassEnabled: true,
              tiltGesturesEnabled: true,
              rotateGesturesEnabled: true,
              onCameraMove: (position) {
                // Optimize performance by limiting updates
                _updateTimer?.cancel();
                _updateTimer = Timer(_updateInterval, () {
                  // Handle camera movement if needed
                });
              },
            ),

            // Custom controls
            if (widget.showControls) ...[
              // Zoom controls
              Positioned(
                right: 16,
                top: 16,
                child: Column(
                  children: [
                    _buildControlButton(
                      icon: Icons.add,
                      onPressed: () {
                        _mapController.animateCamera(
                          CameraUpdate.zoomIn(),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildControlButton(
                      icon: Icons.remove,
                      onPressed: () {
                        _mapController.animateCamera(
                          CameraUpdate.zoomOut(),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Location and fit controls
              Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  children: [
                    _buildControlButton(
                      icon: Icons.my_location,
                      onPressed: _centerMapOnOptimalLocation,
                      backgroundColor: _isTracking ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    _buildControlButton(
                      icon: Icons.fit_screen,
                      onPressed: _fitBoundsToPath,
                    ),
                  ],
                ),
              ),

              // Location info card
              if (_currentAddress != null)
                Positioned(
                  left: 16,
                  top: 16,
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
                        const Row(
                          children: [
                            Icon(Icons.location_on,
                                color: Colors.blue, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Current Location',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 200,
                          child: Text(
                            _currentAddress!,
                            style: const TextStyle(fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? backgroundColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: backgroundColor != null ? Colors.white : Colors.grey[700],
          size: 20,
        ),
        iconSize: 20,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
      ),
    );
  }
}
