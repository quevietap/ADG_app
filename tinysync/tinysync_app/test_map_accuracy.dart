import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

/// Simple test widget to verify Google Maps API key and location accuracy
class MapAccuracyTest extends StatefulWidget {
  const MapAccuracyTest({super.key});

  @override
  State<MapAccuracyTest> createState() => _MapAccuracyTestState();
}

class _MapAccuracyTestState extends State<MapAccuracyTest> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  String _status = 'Initializing...';
  String _accuracy = 'Unknown';

  @override
  void initState() {
    super.initState();
    _testLocationAccuracy();
  }

  Future<void> _testLocationAccuracy() async {
    try {
      setState(() {
        _status = 'Checking permissions...';
      });

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _status = '❌ Location permission denied';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _status = '❌ Location permission permanently denied';
        });
        return;
      }

      setState(() {
        _status = 'Getting current location...';
      });

      // Get current location with high accuracy
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _status = '✅ Location obtained successfully';
        _accuracy = '${position.accuracy.toStringAsFixed(1)} meters';
      });

      print('📍 Test Location: ${position.latitude}, ${position.longitude}');
      print('📍 Accuracy: ${position.accuracy} meters');
      print('📍 Altitude: ${position.altitude} meters');
      print('📍 Speed: ${position.speed} m/s');
      print('📍 Heading: ${position.heading} degrees');

    } catch (e) {
      setState(() {
        _status = '❌ Error: $e';
      });
      print('❌ Location test error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Accuracy Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Status card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: $_status',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'GPS Accuracy: $_accuracy',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Instructions:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '• If you see "API_KEY" errors, add a valid Google Maps API key\n'
                  '• GPS accuracy should be 3-10 meters for good results\n'
                  '• Go outside for better GPS signal',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          
          // Map
          Expanded(
            child: _currentLocation != null
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _currentLocation!,
                      zoom: 15.0,
                    ),
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    markers: {
                      Marker(
                        markerId: const MarkerId('test_location'),
                        position: _currentLocation!,
                        infoWindow: InfoWindow(
                          title: 'Test Location',
                          snippet: 'Accuracy: $_accuracy',
                        ),
                      ),
                    },
                  )
                : const Center(
                    child: CircularProgressIndicator(),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _testLocationAccuracy,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
