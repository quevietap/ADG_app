import 'package:flutter/material.dart';
import '../services/iot_connection_service.dart';

class IoTConnectionStatus extends StatefulWidget {
  const IoTConnectionStatus({super.key});

  @override
  _IoTConnectionStatusState createState() => _IoTConnectionStatusState();
}

class _IoTConnectionStatusState extends State<IoTConnectionStatus> {
  final IoTConnectionService _connectionService = IoTConnectionService();
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _connectToIoT();
  }

  Future<void> _connectToIoT() async {
    setState(() {
      _isConnecting = true;
    });

    final success = await _connectionService.connectToIoT();

    setState(() {
      _isConnecting = false;
    });

    if (!success) {
      _showConnectionInstructions();
    }
  }

  void _showConnectionInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect to IoT'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To connect to your IoT device:'),
            SizedBox(height: 16),
            Text('1. Go to WiFi Settings'),
            Text('2. Find "TinySync_IoT" network'),
            Text('3. Connect with password: 12345678'),
            Text('4. Return to app and tap "Connect"'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _connectToIoT();
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _connectionService.isConnected
            ? Colors.green.shade50
            : Colors.red.shade50,
        border: Border.all(
          color: _connectionService.isConnected ? Colors.green : Colors.red,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _connectionService.isConnected ? Icons.wifi : Icons.wifi_off,
            color: _connectionService.isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _connectionService.isConnected
                      ? 'IoT Connected'
                      : 'IoT Disconnected',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _connectionService.isConnected
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                Text(
                  _connectionService.getConnectionStatus(),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (_isConnecting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (!_connectionService.isConnected)
            ElevatedButton(
              onPressed: _connectToIoT,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Connect'),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _connectionService.disconnect();
    super.dispose();
  }
}
