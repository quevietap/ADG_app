import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class IoTConnectionService {
  static const String _iotSSID = 'TinySync_IoT';
  static const String _iotPassword =
      '12345678'; // Updated to match WiFi Direct password
  static const String _iotIP = '192.168.4.1';
  static const int _iotPort =
      8081; // FIXED: Changed from 8080 to 8081 (detection AI port)

  bool _isConnected = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _pollingTimer;

  // Callback for message forwarding
  Function(Map<String, dynamic>)? _onMessageReceived;

  void setOnMessageReceived(Function(Map<String, dynamic>) callback) {
    _onMessageReceived = callback;
  }

  bool get isConnected => _isConnected;

  // Connect to IoT via WiFi Direct
  Future<bool> connectToIoT() async {
    // On web, always return true to avoid connection issues
    if (kIsWeb) {
      print('🌐 Web mode - IoT connection disabled for UI testing');
      _isConnected = true;
      return true;
    }

    try {
      print('🔌 Connecting to IoT WiFi network: $_iotSSID');

      // Check if connected to IoT WiFi
      if (!await _isConnectedToIoTWiFI()) {
        print('❌ Not connected to IoT WiFi. Please connect to $_iotSSID');
        return false;
      }

      _isConnected = true;
      // Disable heartbeat and polling to reduce server load
      // _startHeartbeat();
      // _startPolling();

      print('✅ Connected to IoT via WiFi Direct!');
      return true;
    } catch (e) {
      print('❌ Failed to connect to IoT: $e');
      _isConnected = false;
      return false;
    }
  }

  // Check if connected to IoT WiFi network
  Future<bool> _isConnectedToIoTWiFI() async {
    try {
      // On web, we can't check WiFi networks the same way
      if (kIsWeb) {
        // For web, we'll try to connect directly to the IoT server
        // This will work if the user is on the same network as the Pi5
        return true;
      }

      // Actually test if we can reach the TinySync_IoT server
      // Try to connect to the TinySync_IoT server (192.168.4.1:8081) - FIXED PORT
      final response = await HttpClient()
          .getUrl(Uri.parse('http://$_iotIP:$_iotPort/api/health'))
          .timeout(
            const Duration(seconds: 3),
          );
      await response.close();

      print('✅ Connected to TinySync_IoT network');
      return true;
    } catch (e) {
      print('❌ Not connected to TinySync_IoT network: $e');
      return false;
    }
  }

  // Check if currently connected to IoT WiFi network
  Future<bool> isConnectedToIoTWiFi() async {
    return await _isConnectedToIoTWiFI();
  }

  // Send message to IoT via HTTP POST
  Future<void> sendMessage(Map<String, dynamic> message) async {
    if (!_isConnected) {
      print('❌ Not connected to IoT');
      return;
    }

    try {
      final request = await HttpClient()
          .postUrl(Uri.parse('http://$_iotIP:$_iotPort/api/control'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(message));
      await request.close();

      print('📤 Sent message to IoT: ${message['command'] ?? 'unknown'}');
    } catch (e) {
      print('❌ Failed to send message to IoT: $e');
    }
  }

  // Start heartbeat to keep connection alive
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // Reduce heartbeat frequency to every 60 seconds instead of 30
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (_isConnected) {
        sendMessage({
          'type': 'heartbeat',
          'timestamp': DateTime.now().toIso8601String()
        });
      }
    });
  }

  // Start polling for new messages
  void _startPolling() {
    _pollingTimer?.cancel();
    // Disable excessive polling - only poll every 30 seconds instead of every second
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        // Only send heartbeat, not poll requests
        sendMessage({
          'type': 'heartbeat',
          'timestamp': DateTime.now().toIso8601String()
        });
      }
    });
  }

  // Handle incoming messages
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data);
      print('📨 Received from IoT: $message');

      // Handle different message types
      switch (message['type']) {
        case 'heartbeat':
          // IoT is alive
          break;
        case 'monitoring_status':
          // Handle monitoring status updates
          print(
              '📹 Monitoring status: ${message['status']} - ${message['message'] ?? ''}');
          break;
        case 'system_status':
          // Handle system status updates
          print(
              '🔧 System status: ${message['status']} - ${message['message'] ?? ''}');
          break;
        case 'ai_status_log':
          // Handle AI status logs
          print('🤖 AI Status: ${message['message']}');
          // Forward to status page for local storage
          _onMessageReceived?.call(message);
          break;
        case 'ai_alert_log':
          // Handle AI alert logs
          print('🚨 AI Alert: ${message['message']}');
          // Forward to status page for local storage
          _onMessageReceived?.call(message);
          break;
        case 'ai_video_log':
          // Handle AI video logs
          print('📹 AI Video: ${message['message']}');
          // Forward to status page for local storage
          _onMessageReceived?.call(message);
          break;
        case 'drowsiness_alert':
          // Handle drowsiness detection
          print('😴 Drowsiness detected: ${message['data']}');
          break;
        case 'behavior_log':
          // Handle behavior logging
          print('📊 Behavior logged: ${message['data']}');
          break;
        default:
          print('Unknown message type: ${message['type']}');
      }
    } catch (e) {
      print('Error parsing message: $e');
    }
  }

  // Handle disconnect
  void _handleDisconnect() {
    print('🔌 Disconnected from IoT');
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _pollingTimer?.cancel();
    _scheduleReconnect();
  }

  // Handle error
  void _handleError(dynamic error) {
    print('❌ IoT connection error: $error');
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _pollingTimer?.cancel();
    _scheduleReconnect();
  }

  // Schedule reconnection
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      print('🔄 Attempting to reconnect to IoT...');
      connectToIoT();
    });
  }

  // Disconnect
  void disconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _pollingTimer?.cancel();
    _reconnectTimer?.cancel();
    print('🔌 Disconnected from IoT');
  }

  // Get connection status
  String getConnectionStatus() {
    if (_isConnected) {
      if (kIsWeb) {
        return 'Connected to IoT via Web';
      } else {
        return 'Connected to IoT via WiFi Direct';
      }
    } else {
      if (kIsWeb) {
        return 'Disconnected - IoT not reachable';
      } else {
        return 'Disconnected - Connect to TinySync_IoT WiFi';
      }
    }
  }

  // WiFi Direct Data Fetching Methods

  // ✅ UPDATED: Fetch snapshots from IoT via WiFi Direct (aligned with new detection_ai.py)
  Future<List<Map<String, dynamic>>> fetchSnapshots() async {
    if (!_isConnected) {
      print('❌ Not connected to IoT via WiFi Direct');
      return [];
    }

    try {
      print('📸 Fetching snapshots via WiFi Direct (new organized format)...');
      final request = await HttpClient()
          .getUrl(Uri.parse('http://$_iotIP:$_iotPort/api/snapshots'));
      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody);
        
        // ✅ NEW: Handle organized batch format from detection_ai.py
        List<Map<String, dynamic>> snapshots = [];
        if (data is List) {
          // Old format - direct list
          snapshots = List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data['organized_data'] != null) {
          // New organized batch format
          final organizedData = data['organized_data'];
          if (organizedData['snapshots'] != null) {
            snapshots = List<Map<String, dynamic>>.from(organizedData['snapshots']['items'] ?? []);
          }
        } else if (data['status'] == 'success' && data['video_clips'] != null) {
          // Legacy format support
          snapshots = List<Map<String, dynamic>>.from(data['video_clips']);
        }
        
        if (snapshots.isNotEmpty) {
          print('✅ Fetched ${snapshots.length} snapshots via WiFi Direct');
          return snapshots;
        }
      }

      print('⚠️ No snapshots available via WiFi Direct');
      return [];
    } catch (e) {
      print('❌ Error fetching snapshots via WiFi Direct: $e');
      return [];
    }
  }

  // ✅ NEW: Handle organized batch sync from detection_ai.py
  Future<Map<String, dynamic>?> fetchOrganizedBatchSync() async {
    if (!_isConnected) {
      print('❌ Not connected to IoT via WiFi Direct');
      return null;
    }

    try {
      print('📦 Fetching organized batch sync via WiFi Direct...');
      final request = await HttpClient()
          .getUrl(Uri.parse('http://$_iotIP:$_iotPort/api/sync/pending'));
      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody);
        
        if (data['sync_type'] == 'organized_batch') {
          print('✅ Received organized batch sync: ${data['total_items']} items (unified snapshots table)');
          return data;
        }
      }

      print('⚠️ No organized batch sync available');
      return null;
    } catch (e) {
      print('❌ Error fetching organized batch sync: $e');
      return null;
    }
  }

  // ✅ NEW: Fetch actual image data from IoT
  Future<Uint8List?> fetchSnapshotImage(String filename) async {
    if (!_isConnected) {
      print('❌ Not connected to IoT via WiFi Direct');
      return null;
    }

    try {
      print('🖼️ Fetching image data for: $filename');
      final request = await HttpClient()
          .getUrl(Uri.parse('http://$_iotIP:$_iotPort/api/snapshot/$filename'));
      final response = await request.close();

      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>(
          <int>[],
          (List<int> previous, List<int> element) => previous..addAll(element),
        );
        print('✅ Fetched image data: ${bytes.length} bytes');
        return Uint8List.fromList(bytes);
      }

      print('⚠️ Image not found: $filename');
      return null;
    } catch (e) {
      print('❌ Error fetching image data: $e');
      return null;
    }
  }

  // ✅ UPDATED: Fetch snapshots logs from IoT via WiFi Direct (aligned with unified table in detection_ai.py)
  Future<List<Map<String, dynamic>>> fetchSnapshotsLogs() async {
    if (!_isConnected) {
      print('❌ Not connected to IoT via WiFi Direct');
      return [];
    }

    try {
      print('📝 Fetching snapshots logs via WiFi Direct (unified table format)...');
      final request = await HttpClient()
          .getUrl(Uri.parse('http://$_iotIP:$_iotPort/api/data/behavior_logs'));
      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody);
        
        // ✅ NEW: Handle organized batch format from detection_ai.py (unified snapshots table)
        List<Map<String, dynamic>> logs = [];
        if (data is List) {
          // Old format - direct list
          logs = List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data['organized_data'] != null) {
          // New organized batch format
          final organizedData = data['organized_data'];
          if (organizedData['behavior_logs'] != null) {
            logs = List<Map<String, dynamic>>.from(organizedData['behavior_logs']['items'] ?? []);
          }
        }

        final snapshotsLogs =
            logs.map((log) => Map<String, dynamic>.from(log)).toList();
        print('✅ Fetched ${snapshotsLogs.length} snapshots logs via WiFi Direct');
        return snapshotsLogs;
      }

      print('⚠️ No behavior logs available via WiFi Direct');
      return [];
    } catch (e) {
      print('❌ Error fetching behavior logs via WiFi Direct: $e');
      return [];
    }
  }

  // Fetch system status from IoT via WiFi Direct
  Future<Map<String, dynamic>> fetchSystemStatus() async {
    if (!_isConnected) {
      print('❌ Not connected to IoT via WiFi Direct');
      return {};
    }

    try {
      print('📊 Fetching system status via WiFi Direct...');
      final request = await HttpClient()
          .getUrl(Uri.parse('http://$_iotIP:$_iotPort/api/stats'));
      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final stats = json.decode(responseBody);

        print('✅ Fetched system status via WiFi Direct');
        return Map<String, dynamic>.from(stats);
      }

      print('⚠️ System status not available via WiFi Direct');
      return {};
    } catch (e) {
      print('❌ Error fetching system status via WiFi Direct: $e');
      return {};
    }
  }

  // Fetch IoT health status via WiFi Direct
  Future<Map<String, dynamic>> fetchIoTHealth() async {
    if (!_isConnected) {
      print('❌ Not connected to IoT via WiFi Direct');
      return {};
    }

    try {
      print('🏥 Fetching IoT health via WiFi Direct...');
      final request = await HttpClient()
          .getUrl(Uri.parse('http://$_iotIP:$_iotPort/api/health'));
      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final health = json.decode(responseBody);

        print('✅ Fetched IoT health via WiFi Direct');
        return Map<String, dynamic>.from(health);
      }

      print('⚠️ IoT health not available via WiFi Direct');
      return {};
    } catch (e) {
      print('❌ Error fetching IoT health via WiFi Direct: $e');
      return {};
    }
  }

  // Send command to IoT via WiFi Direct
  Future<bool> sendCommand(String command, {Map<String, dynamic>? data}) async {
    if (!_isConnected) {
      print('❌ Not connected to IoT via WiFi Direct');
      return false;
    }

    try {
      print('📤 Sending command via WiFi Direct: $command');

      String endpoint;
      Map<String, dynamic> message;

      switch (command) {
        case 'start':
          endpoint = '/api/monitoring/start';
          message = {}; // ✅ Simplified - no data needed
          break;
        case 'stop':
          endpoint = '/api/monitoring/stop';
          message = {}; // ✅ Simplified - no data needed
          break;
        case 'sync_start':
          // CRITICAL FIX: sync_start should NOT start detection
          // This command is only for data synchronization, not detection control
          print('🔄 Sync command - data synchronization only, not detection control');
          return true;
        case 'heartbeat':
          // For heartbeat, we'll use health check instead
          print('💓 Heartbeat - using health check');
          return true;
        default:
          print('❌ Unknown command: $command');
          return false;
      }

      final request = await HttpClient()
          .postUrl(Uri.parse('http://$_iotIP:$_iotPort$endpoint'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(message));
      final response = await request.close();

      if (response.statusCode == 200) {
        print('✅ Command sent successfully via WiFi Direct: $command');
        return true;
      } else {
        print('❌ Command failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error sending command via WiFi Direct: $e');
      return false;
    }
  }
}
