import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/ultra_accurate_gps_service.dart';

/// GPS Accuracy Test Widget
/// Shows real-time GPS accuracy and provides recommendations
class GPSAccuracyTestWidget extends StatefulWidget {
  const GPSAccuracyTestWidget({super.key});

  @override
  State<GPSAccuracyTestWidget> createState() => _GPSAccuracyTestWidgetState();
}

class _GPSAccuracyTestWidgetState extends State<GPSAccuracyTestWidget> {
  final UltraAccurateGPSService _gpsService = UltraAccurateGPSService();
  
  Position? _currentPosition;
  String _status = 'Initializing...';
  String _accuracyLevel = 'Unknown';
  double _currentAccuracy = double.infinity;
  bool _isTracking = false;
  List<String> _recommendations = [];
  Map<String, dynamic> _statistics = {};

  @override
  void initState() {
    super.initState();
    _startAccuracyTest();
  }

  @override
  void dispose() {
    _gpsService.stopTracking();
    super.dispose();
  }

  Future<void> _startAccuracyTest() async {
    try {
      setState(() {
        _status = 'Testing GPS accuracy...';
      });

      // Get initial ultra-accurate location
      final position = await _gpsService.getUltraAccurateLocation();
      
      if (position != null) {
        setState(() {
          _currentPosition = position;
          _currentAccuracy = position.accuracy;
          _accuracyLevel = _gpsService.getAccuracyLevel(position.accuracy);
          _status = 'GPS Test Complete';
        });

        // Get GPS status and recommendations
        final gpsStatus = _gpsService.getGPSStatus();
        setState(() {
          _recommendations = List<String>.from(gpsStatus['recommendations'] ?? []);
          _statistics = Map<String, dynamic>.from(gpsStatus['statistics'] ?? {});
        });

        // Start continuous tracking
        await _startContinuousTracking();
      } else {
        setState(() {
          _status = '❌ Could not get accurate location';
        });
      }

    } catch (e) {
      setState(() {
        _status = '❌ Error: $e';
      });
    }
  }

  Future<void> _startContinuousTracking() async {
    await _gpsService.startContinuousTracking(
      onLocationUpdate: (position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
            _currentAccuracy = position.accuracy;
            _accuracyLevel = _gpsService.getAccuracyLevel(position.accuracy);
            _isTracking = true;
          });
        }
      },
      onAccuracyUpdate: (accuracy) {
        if (mounted) {
          setState(() {
            _currentAccuracy = accuracy;
            _accuracyLevel = _gpsService.getAccuracyLevel(accuracy);
          });
        }
      },
    );
  }

  String _getAccuracyEmoji(double accuracy) {
    if (accuracy <= 5.0) return '🎯';
    if (accuracy <= 10.0) return '✅';
    if (accuracy <= 20.0) return '⚠️';
    if (accuracy <= 50.0) return '❌';
    return '🚨';
  }

  Color _getAccuracyColor(double accuracy) {
    if (accuracy <= 5.0) return Colors.green;
    if (accuracy <= 10.0) return Colors.lightGreen;
    if (accuracy <= 20.0) return Colors.orange;
    if (accuracy <= 50.0) return Colors.red;
    return Colors.red.shade900;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Accuracy Test'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.black87,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Card
              _buildStatusCard(),
              const SizedBox(height: 16),

              // Accuracy Display
              _buildAccuracyDisplay(),
              const SizedBox(height: 16),

              // Statistics Card
              _buildStatisticsCard(),
              const SizedBox(height: 16),

              // Recommendations Card
              _buildRecommendationsCard(),
              const SizedBox(height: 16),

              // Test Controls
              _buildTestControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isTracking ? Icons.gps_fixed : Icons.gps_off,
                  color: _isTracking ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                const Text(
                  'GPS Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: TextStyle(
                color: _status.contains('❌') ? Colors.red : Colors.white,
                fontSize: 16,
              ),
            ),
            if (_currentPosition != null) ...[
              const SizedBox(height: 8),
              Text(
                '📍 ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccuracyDisplay() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _getAccuracyEmoji(_currentAccuracy),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 8),
                const Text(
                  'GPS Accuracy',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Accuracy Bar
            Container(
              width: double.infinity,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green,
                          Colors.lightGreen,
                          Colors.orange,
                          Colors.red,
                          Colors.red.shade900,
                        ],
                        stops: const [0.0, 0.2, 0.4, 0.6, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            
            // Accuracy Text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_currentAccuracy.toStringAsFixed(1)} meters',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _getAccuracyColor(_currentAccuracy),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getAccuracyColor(_currentAccuracy),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _accuracyLevel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            // Accuracy Scale
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('5m', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text('10m', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text('20m', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text('50m', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text('100m+', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Statistics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            
            if (_statistics.isNotEmpty) ...[
              _buildStatRow('Average Accuracy', '${(_statistics['average_accuracy'] ?? double.infinity).toStringAsFixed(1)}m'),
              _buildStatRow('Readings Count', '${_statistics['readings_count'] ?? 0}'),
              _buildStatRow('Accuracy Level', '${_statistics['accuracy_level'] ?? 'Unknown'}'),
            ] else ...[
              const Text(
                'No statistics available yet',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecommendationsCard() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '💡 Recommendations',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            
            if (_recommendations.isNotEmpty) ...[
              ..._recommendations.map((recommendation) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Colors.blue)),
                    Expanded(
                      child: Text(
                        recommendation,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              )),
            ] else ...[
              const Text(
                'GPS accuracy is good! No recommendations needed.',
                style: TextStyle(color: Colors.green),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTestControls() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🔧 Test Controls',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _startAccuracyTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retest GPS'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final status = _gpsService.getGPSStatus();
                      print('📊 GPS Status: $status');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('GPS Status logged to console'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Log Status'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
