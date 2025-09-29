import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';

class RealGoogleMapsWidget extends StatefulWidget {
  final List<LatLng> tripPath;
  final LatLng? currentLocation;
  final LatLng? startLocation;
  final LatLng? endLocation;
  final double height;
  final bool showControls;
  final bool showMyLocation;
  final Function(LatLng)? onLocationChanged;
  final Function(String)? onAddressResolved;

  const RealGoogleMapsWidget({
    super.key,
    required this.tripPath,
    this.currentLocation,
    this.startLocation,
    this.endLocation,
    required this.height,
    this.showControls = true,
    this.showMyLocation = true,
    this.onLocationChanged,
    this.onAddressResolved,
  });

  @override
  State<RealGoogleMapsWidget> createState() => _RealGoogleMapsWidgetState();
}

class _RealGoogleMapsWidgetState extends State<RealGoogleMapsWidget> {
  final MapController _mapController = MapController();
  Timer? _locationTimer;
  String? _currentAddress;

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    _resolveCurrentAddress();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  void _startLocationUpdates() {
    if (widget.showMyLocation) {
      // Increase frequency for better real-time tracking (every 3 seconds)
      _locationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        _getCurrentLocation();
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final location = LatLng(position.latitude, position.longitude);

      if (widget.onLocationChanged != null) {
        widget.onLocationChanged!(location);
      }

      setState(() {
        // Update current location
      });
    } catch (e) {
      print('❌ Error getting current location: $e');
    }
  }

  Future<void> _resolveCurrentAddress() async {
    if (widget.currentLocation != null) {
      try {
        final placemarks = await placemarkFromCoordinates(
          widget.currentLocation!.latitude,
          widget.currentLocation!.longitude,
        );

        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          final address =
              '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';

          setState(() {
            _currentAddress = address;
          });

          if (widget.onAddressResolved != null) {
            widget.onAddressResolved!(address);
          }
        }
      } catch (e) {
        print('❌ Error resolving address: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final centerLocation = widget.currentLocation ??
        widget.startLocation ??
        const LatLng(0.0, 0.0); // Will be updated when real GPS data arrives

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
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
            // Main Map
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: centerLocation,
                initialZoom: 13.0,
                maxZoom: 18.0,
                minZoom: 3.0,
                onTap: (tapPosition, point) {
                  // Handle map tap
                },
              ),
              children: [
                // Map Tiles
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.tinysync.app',
                  tileProvider: NetworkTileProvider(),
                ),

                // Trip Path
                if (widget.tripPath.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.tripPath,
                        strokeWidth: 4.0,
                        color: Colors.blue.withOpacity(0.8),
                      ),
                    ],
                  ),

                // Markers
                MarkerLayer(
                  markers: [
                    // Current Location Marker
                    if (widget.currentLocation != null)
                      Marker(
                        point: widget.currentLocation!,
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),

                    // Start Location Marker
                    if (widget.startLocation != null)
                      Marker(
                        point: widget.startLocation!,
                        width: 25,
                        height: 25,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),

                    // End Location Marker
                    if (widget.endLocation != null)
                      Marker(
                        point: widget.endLocation!,
                        width: 25,
                        height: 25,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.stop,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Map Controls
            if (widget.showControls) ...[
              // Zoom Controls
              Positioned(
                top: 16,
                right: 16,
                child: Column(
                  children: [
                    Container(
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
                        children: [
                          IconButton(
                            onPressed: () {
                              _mapController.move(centerLocation, 15.0);
                            },
                            icon: const Icon(Icons.add, size: 20),
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                          Container(
                            height: 1,
                            color: Colors.grey.withOpacity(0.3),
                          ),
                          IconButton(
                            onPressed: () {
                              _mapController.move(centerLocation, 10.0);
                            },
                            icon: const Icon(Icons.remove, size: 20),
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Location Button
              if (widget.showMyLocation)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Container(
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
                    child: IconButton(
                      onPressed: () {
                        if (widget.currentLocation != null) {
                          _mapController.move(widget.currentLocation!, 15.0);
                        }
                      },
                      icon: const Icon(Icons.my_location, size: 20),
                      padding: const EdgeInsets.all(8),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                ),
            ],

            // Address Display
            if (_currentAddress != null)
              Positioned(
                top: 16,
                left: 16,
                right: widget.showControls ? 80 : 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _currentAddress!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
