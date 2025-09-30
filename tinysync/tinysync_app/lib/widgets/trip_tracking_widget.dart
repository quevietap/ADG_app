import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'beautiful_live_tracking_map.dart';

class TripTrackingWidget extends StatefulWidget {
  final Map<String, dynamic> trip;
  final Function()? onTripUpdated;
  final bool isOperatorView; // Add parameter to determine view type

  const TripTrackingWidget({
    super.key,
    required this.trip,
    this.onTripUpdated,
    this.isOperatorView = false, // Default to driver view
  });

  @override
  State<TripTrackingWidget> createState() => _TripTrackingWidgetState();
}

class _TripTrackingWidgetState extends State<TripTrackingWidget> {
  RealtimeChannel? _tripSubscription;
  RealtimeChannel? _locationSubscription;
  GoogleMapController? _mapController;
  final List<LatLng> _tripPath = [];
  LatLng? _currentLocation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _initializeTripTracking();
    _loadTripPath();
  }

  @override
  void dispose() {
    _tripSubscription?.unsubscribe();
    _locationSubscription?.unsubscribe();
    super.dispose();
  }

  void _initializeTripTracking() {
    try {
      final tripId = widget.trip['id'];

      // Subscribe to trip updates
      _tripSubscription = Supabase.instance.client
          .channel('trip_updates_$tripId')
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
              print('🔄 Trip update received: $payload');
              if (widget.onTripUpdated != null) {
                widget.onTripUpdated!();
              }
            },
          )
          .subscribe();

      // Subscribe to location updates with proper real-time handling
      _locationSubscription = Supabase.instance.client
          .channel('trip_locations_$tripId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'driver_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'trip_id',
              value: tripId,
            ),
            callback: (payload) {
              print('📍 Live location update received for trip: $tripId');
              _handleLocationUpdate(payload);
            },
          )
          .subscribe();
    } catch (e) {
      print('❌ Error initializing trip tracking: $e');
    }
  }

  void _handleLocationUpdate(PostgresChangePayload payload) {
    try {
      final data = payload.newRecord;
      
      // Safe conversion helper for numeric values
      double? _safeToDouble(dynamic value) {
        if (value == null) return null;
        if (value is double) return value;
        if (value is int) return value.toDouble();
        if (value is String) return double.tryParse(value);
        return null;
      }

      final lat = _safeToDouble(data['latitude']);
      final lng = _safeToDouble(data['longitude']);

      if (lat != null && lng != null) {
        setState(() {
          _currentLocation = LatLng(lat, lng);
          _tripPath.add(_currentLocation!);
        });

        // Smoothly animate map to new location for real-time tracking
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_currentLocation!, 15.0),
        );

        print('🗺️ Map updated with new location: $lat, $lng');
      }
    } catch (e) {
      print('❌ Error handling location update: $e');
    }
  }

  Future<void> _loadTripPath() async {
    try {
      // For now, skip loading trip locations since the table doesn't exist
      // TODO: Create trip_locations table or use alternative location tracking
      print('⚠️ Trip locations table not available - skipping path loading');

      // Don't set default location - wait for real GPS data
      if (_currentLocation == null) {
        print(
            '⚠️ No GPS location available yet - map will center when location is obtained');
        // Map will remain at default view until real GPS data arrives
      }
    } catch (e) {
      print('❌ Error loading trip path: $e');
    }
  }

  String _getTripStatus() {
    return widget.trip['status'] ?? 'unknown';
  }

  Color _getStatusColor() {
    switch (_getTripStatus()) {
      case 'assigned':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (_getTripStatus()) {
      case 'assigned':
        return Icons.schedule;
      case 'in_progress':
        return Icons.local_shipping;
      case 'completed':
        return Icons.check_circle;
      default:
        return Icons.help;
    }
  }

  double _getProgressPercentage() {
    switch (_getTripStatus()) {
      case 'assigned':
        return 0.0;
      case 'in_progress':
        return 50.0;
      case 'completed':
        return 100.0;
      default:
        return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 4,
      child: Column(
        children: [
          // Trip Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getStatusColor().withOpacity(0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _getStatusColor(),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getStatusIcon(),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip: ${widget.trip['trip_ref_number'] ?? 'Unknown'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Driver: ${widget.trip['driver_name'] ?? 'Unknown'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                      },
                      icon: Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),

                // Progress Bar
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _getProgressPercentage() / 100,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_getProgressPercentage().toInt()}% Complete',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Expanded Content
          if (_isExpanded) ...[
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Trip Details
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailCard(
                          'Origin',
                          widget.trip['origin'] ?? 'Not specified',
                          Icons.location_on,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDetailCard(
                          'Destination',
                          widget.trip['destination'] ?? 'Not specified',
                          Icons.location_on,
                          Colors.red,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Current Location
                  if (_currentLocation != null) ...[
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
                                  'Current Location',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                Text(
                                  '${_currentLocation!.latitude.toStringAsFixed(4)}, ${_currentLocation!.longitude.toStringAsFixed(4)}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Beautiful Live Tracking Map View
                  BeautifulLiveTrackingMap(
                    trip: widget.trip,
                    driverId: widget.trip['driver_id'] ?? '',
                    height: 200,
                    isOperatorView:
                        widget.isOperatorView, // Pass through the view type
                    onProgressUpdate: (percentage) {
                      print('📊 Progress: $percentage%');
                    },
                    onLocationUpdate: (location) {
                      print('📍 Location: $location');
                    },
                    onDistanceUpdate: (distance) {
                      print('📏 Distance: $distance km');
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
