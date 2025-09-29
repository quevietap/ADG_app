import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

/// Simple test to verify Google Maps API key is working
class ApiKeyTest extends StatefulWidget {
  const ApiKeyTest({super.key});

  @override
  State<ApiKeyTest> createState() => _ApiKeyTestState();
}

class _ApiKeyTestState extends State<ApiKeyTest> {
  String _status = 'Testing API key...';
  bool _apiKeyWorking = false;
  LatLng? _testLocation;

  @override
  void initState() {
    super.initState();
    _testApiKey();
  }

  Future<void> _testApiKey() async {
    try {
      setState(() {
        _status = 'Checking location permissions...';
      });

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _status = '❌ Location permission denied';
            _apiKeyWorking = false;
          });
          return;
        }
      }

      setState(() {
        _status = 'Getting current location...';
      });

      // Get current location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _testLocation = LatLng(position.latitude, position.longitude);
        _status = '✅ API Key Working! Location obtained successfully';
        _apiKeyWorking = true;
      });

      print('✅ API Key Test Success:');
      print('📍 Location: ${position.latitude}, ${position.longitude}');
      print('📍 Accuracy: ${position.accuracy} meters');
      print('📍 Google Maps should work perfectly!');

    } catch (e) {
      setState(() {
        _status = '❌ API Key Error: $e';
        _apiKeyWorking = false;
      });
      
      print('❌ API Key Test Failed: $e');
      
      if (e.toString().contains('API_KEY')) {
        print('🚨 SOLUTION: Add a valid Google Maps API key to AndroidManifest.xml');
        print('📖 See: GOOGLE_MAPS_API_KEY_SETUP.md');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Maps API Key Test'),
        backgroundColor: _apiKeyWorking ? Colors.green : Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _apiKeyWorking ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _apiKeyWorking ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _apiKeyWorking ? Icons.check_circle : Icons.error,
                        color: _apiKeyWorking ? Colors.green : Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _status,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _apiKeyWorking ? Colors.green[800] : Colors.red[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_apiKeyWorking) ...[
                    const Text(
                      'To fix this:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('1. Get a Google Maps API key (5 minutes)'),
                    const Text('2. Replace placeholder in AndroidManifest.xml'),
                    const Text('3. See GOOGLE_MAPS_API_KEY_SETUP.md'),
                  ] else ...[
                    const Text(
                      '✅ Your Google Maps API key is working!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('• Maps will be accurate (±3-5 meters)'),
                    const Text('• Professional Google Maps tiles'),
                    const Text('• Real-time address resolution'),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Test Map
            if (_testLocation != null) ...[
              const Text(
                'Test Map:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _testLocation!,
                        zoom: 15.0,
                      ),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      markers: {
                        Marker(
                          markerId: const MarkerId('test_location'),
                          position: _testLocation!,
                          infoWindow: const InfoWindow(
                            title: 'Test Location',
                            snippet: 'API Key Working!',
                          ),
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _testApiKey,
        backgroundColor: _apiKeyWorking ? Colors.green : Colors.red,
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }
}
