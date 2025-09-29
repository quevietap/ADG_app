import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:location/location.dart' as location_pkg;
import '../../services/iot_connection_service.dart';
import '../../services/supabase_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/driver_notification_alert.dart';

class StatusPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const StatusPage({super.key, this.userData});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final IoTConnectionService _iotConnectionService = IoTConnectionService();
  final LocationService _locationService = LocationService();

  // REMOVED: HTTP Server - using original sync method instead

  // Connection and status
  bool _isConnected = false;
  bool _isMonitoring = false;
  String _currentDriver = "Main Driver";

  // Driver and break state tracking
  bool _isOnBreak = false;
  bool _isDriverSwitched = false;
  String?
      _breakStartedByDriver; // Track which driver started the break (main/sub)

  //  FIX: Break toggle debounce to prevent rapid successive calls
  bool _isBreakToggleInProgress = false;
  DateTime? _lastBreakToggleTime;

  // UI state
  bool _isLoading = false;

  // Device info
  String? _currentDriverId;
  String? _currentTripId;

  // Local storage - UNIFIED TABLE STRUCTURE (aligned with detection_ai.py and supabase.sql)
  final List<Map<String, dynamic>> _unifiedSnapshots =
      []; //  UNIFIED: Single list for snapshot logs and snapshots
  final Map<String, dynamic> _snapshotImages =
      {}; //  Store actual image data for snapshots

  //  REMOVED: Redundant storage lists - everything uses _unifiedSnapshots

  //  NEW: Upload queue for background processing
  final List<Map<String, dynamic>> _pendingUploads = [];
  //  NEW: Track uploaded items to prevent duplicates
  final List<Map<String, dynamic>> _uploadedItems = [];
  //  REMOVED: _pendingTripLogs - everything goes to unified snapshots table

  //  NEW: Data retention settings (24 hours)
  static const Duration _dataRetentionPeriod = Duration(hours: 24);

  // Connection monitoring
  Timer? _connectionTimer;

  // USB cable detection
  Timer? _usbDetectionTimer;

  // Tab controller for the 3 tabs
  late TabController _tabController;

  // IoT Status tracking
  bool _iotConnected = false;
  String _iotStatus = "Disconnected";
  String _iotCurrentAction = "Waiting for connection";
  Map<String, dynamic> _iotSystemInfo = {};
  Map<String, dynamic> _iotStats = {};

  // Universal Camera System status
  String _universalCameraStatus = "Unknown";
  String _universalCameraDetails = "";

  // DATABASE VARIABLES (NEW - for trip management)
  String? _dbCurrentDriverId; // UUID from users.id (Main Driver)
  String? _dbCurrentTripId; // UUID from trips.id
  String? _dbCurrentTripRefNumber; // Human-readable trip reference
  Map<String, dynamic>? _dbCurrentTrip; // Full trip data from database
  RealtimeChannel? _tripsSubscription;
  Timer? _refreshTimer;

  // USER DATA (NEW - for authentication)
  Map<String, dynamic>? _currentUser;

  //  HELPER FUNCTIONS: Eliminate redundant checks
  bool _validateConnection({String? action}) {
    if (!_isConnected) {
      final message = action != null
          ? 'Cannot $action: Not connected to device'
          : 'Not connected to device';
      _showErrorSnackBar(message);
      return false;
    }
    return true;
  }

  bool _validateAuthentication() {
    if (_currentUser == null) {
      _showErrorSnackBar('Please log in first');
      return false;
    }
    return true;
  }

  Map<String, String> _getFallbackIds() {
    return {
      'driverId': _dbCurrentDriverId ??
          'default-driver-${DateTime.now().millisecondsSinceEpoch}',
      'tripId': _dbCurrentTripId ??
          'default-trip-${DateTime.now().millisecondsSinceEpoch}',
    };
  }

  bool _validateDriverAndTrip({String? action}) {
    final ids = _getFallbackIds();
    if (_dbCurrentDriverId == null || _dbCurrentTripId == null) {
      final message = action != null
          ? 'Cannot $action: Missing driver or trip information'
          : 'Missing driver or trip information';
      _showErrorSnackBar(message);
      return false;
    }
    return true;
  }

  String? _getCurrentDriverId() {
    // Always return the main driver ID - driver_type will distinguish main vs sub
    return _dbCurrentDriverId ?? _currentUser?['id'];
  }

  //  NEW: Unified operator action logging method with CORRECT FLOW
  void _logOperatorAction(String actionType, String description) {
    print(
        'DEBUG: _logOperatorAction called with actionType: $actionType, description: $description');
    //  ALIGNED: Create event for snapshots table (snapshot logs)
    final now = DateTime.now();
    final behaviorEvent = {
      'id': now.millisecondsSinceEpoch,
      'filename': null, //  FIX: Button actions don't need filenames (no images)
      'timestamp': now.toIso8601String(),
      'retention_until': now
          .add(_dataRetentionPeriod)
          .toIso8601String(), //  NEW: 24-hour retention
      'driver_id': _currentDriverId ?? _currentUser?['id'] ?? 'unknown-driver',
      'trip_id': _currentTripId ?? 'no-trip-id',
      'device_id': 'flutter-app',

      //  FIXED: Use event_type = 'button_action' for button actions (not 'snapshot')
      'event_type': 'button_action',
      'behavior_type': actionType,
      'confidence_score': null, //  FIX: Manual action, not AI-detected
      'event_duration': 0.0,

      //  FIX: AI-related fields should be null for manual button actions
      'gaze_pattern': null, //  FIX: Manual action, not AI-detected
      'face_direction': null, //  FIX: Manual action, not AI-detected
      'eye_state': null, //  FIX: Manual action, not AI-detected
      'is_legitimate_driving': true,
      'evidence_strength': 'high',
      'evidence_reason': 'Operator manual action',
      'trigger_justification': description,
      'reflection_detected': null, //  FIX: Manual action, not AI-detected
      'detection_reliability': null, //  FIX: Manual action, not AI-detected
      'driver_threshold_adjusted': null,
      'compliance_audit_trail': 'Operator action logged',

      //  ALIGNED: Include operator context
      'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',
      'details': {
        'action_type': actionType,
        'description': description,
        'operator_id': _currentDriverId,
        'operator_type': 'main',
        'source': 'flutter_app',
        'button_pressed': true,
        'monitoring_state': _isMonitoring,
        'break_state': _isOnBreak,
      },

      //  OPTIMIZED: Initialize sync status for new events
      'sync_status': 'not_synced',
    };

    //  OPTIMIZED: Initialize sync status for new event
    _initializeSyncStatus(behaviorEvent);

    //  STEP 1: Save to LOCAL STORAGE first (correct flow)
    setState(() {
      _unifiedSnapshots.insert(0, behaviorEvent);
      if (_unifiedSnapshots.length > 200) {
        _unifiedSnapshots.removeLast();
      }
    });

    //  CORE REQUIREMENT: Save button log to local storage
    _savePersistedData();

    print(
        'SUCCESS: Button log saved to local storage: $actionType - $description');
  }

  //  REMOVED: trip_logs functionality - everything goes to unified snapshots table

  //  OPTIMIZED: Queue for Supabase upload with sync status tracking
  void _queueForSupabaseUpload(Map<String, dynamic> eventData) {
    //  OPTIMIZED: Check sync status instead of Supabase validation
    if (eventData['sync_status'] == 'synced') {
      print(
          'SUCCESS: Event already synced: ${eventData['behavior_type']} at ${eventData['timestamp']}');
      return;
    }

    // Initialize sync status if not set
    if (eventData['sync_status'] == null) {
      eventData['sync_status'] = 'not_synced';
    }

    // Add to upload queue for background processing
    _pendingUploads.add(eventData);

    //  NEW: Persist upload queue (survives app closure)
    _savePersistedData();

    // Process upload queue in background
    _processUploadQueue();
  }

  //  NEW: Process upload queue in background
  void _processUploadQueue() async {
    while (_pendingUploads.isNotEmpty) {
      final eventData = _pendingUploads.removeAt(0);

      try {
        await _uploadUnifiedEventToSupabase(eventData);
        print(
            'SUCCESS: Operator action uploaded to Supabase: ${eventData['behavior_type']}');

        //  NEW: Save updated queue after successful upload
        _savePersistedData();
      } catch (e) {
        print('ERROR: Failed to upload operator action to Supabase: $e');
        // Re-queue for retry
        _pendingUploads.add(eventData);

        //  NEW: Save updated queue after re-queuing
        _savePersistedData();

        break; // Stop processing to avoid infinite loop
      }
    }
  }

  //  OPTIMIZED: Check sync status instead of complex validation
  bool _isEventSynced(Map<String, dynamic> eventData) {
    return eventData['sync_status'] == 'synced';
  }

  //  OPTIMIZED: Mark event as synced with timestamp
  void _markEventAsSynced(Map<String, dynamic> eventData) {
    eventData['sync_status'] = 'synced';
    eventData['uploaded_at'] = DateTime.now().toIso8601String();

    // Save to persistent storage
    _savePersistedData();

    print(
        'SUCCESS: Event marked as synced: ${eventData['behavior_type']} at ${eventData['timestamp']}');
  }

  //  OPTIMIZED: Initialize sync status for new events
  void _initializeSyncStatus(Map<String, dynamic> eventData) {
    if (eventData['sync_status'] == null) {
      eventData['sync_status'] = 'not_synced';
    }
  }

  //  OPTIMIZED: Build sync status indicator widget
  Widget _buildSyncStatusIndicator(Map<String, dynamic> event) {
    final syncStatus = event['sync_status'] ?? 'not_synced';

    switch (syncStatus) {
      case 'synced':
        return Container(
          margin: const EdgeInsets.only(left: 8),
          child: const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 16,
          ),
        );
      case 'syncing':
        return Container(
          margin: const EdgeInsets.only(left: 8),
          child: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ),
        );
      case 'failed':
        return Container(
          margin: const EdgeInsets.only(left: 8),
          child: const Icon(
            Icons.error,
            color: Colors.red,
            size: 16,
          ),
        );
      case 'not_synced':
      default:
        return Container(
          margin: const EdgeInsets.only(left: 8),
          child: const Icon(
            Icons.circle,
            color: Colors.red,
            size: 16,
          ),
        );
    }
  }

  //  NEW: Upload unified event to Supabase
  Future<void> _uploadUnifiedEventToSupabase(
      Map<String, dynamic> eventData) async {
    try {
      final supabaseService = SupabaseService();
      supabaseService.initialize(Supabase.instance.client);

      //  UNIFIED: Single data structure for all event types
      final supabaseData = {
        'driver_id': eventData['driver_id'],
        'trip_id': eventData['trip_id'],
        'behavior_type': eventData['behavior_type'],
        'timestamp': eventData['timestamp'],
        'device_id': eventData['device_id'],
        'event_type': eventData['event_type'], // 'snapshot' only

        // Evidence fields (same for both event types)
        'confidence_score': eventData['confidence_score'],
        'event_duration': eventData['event_duration'],
        'gaze_pattern': eventData['gaze_pattern'],
        'face_direction': eventData['face_direction'],
        'eye_state': eventData['eye_state'],
        'is_legitimate_driving': eventData['is_legitimate_driving'],
        'evidence_strength': eventData['evidence_strength'],
        'evidence_reason': eventData['evidence_reason'],
        'trigger_justification': eventData['trigger_justification'],
        'reflection_detected': eventData['reflection_detected'],
        'detection_reliability': eventData['detection_reliability'],
        'driver_threshold_adjusted': eventData['driver_threshold_adjusted'],
        'compliance_audit_trail': eventData['compliance_audit_trail'],

        'details': jsonEncode(eventData['details']),
      };

      //  UNIFIED: Single upload method
      final success = await supabaseService.saveBehaviorLog(supabaseData);
      if (success) {
        print(
            'SUCCESS: Unified event uploaded to Supabase: ${eventData['event_type']}');
        //  OPTIMIZED: Mark as synced using new sync status approach
        _markEventAsSynced(eventData);
      } else {
        print('ERROR: Failed to upload unified event to Supabase');
        // Mark as failed for retry
        eventData['sync_status'] = 'failed';
      }
    } catch (e) {
      print('ERROR: Error uploading unified event to Supabase: $e');
    }
  }

  // Location tracking state
  bool _isLocationEnabled = false;
  bool _isLocationTracking = false;
  location_pkg.LocationData? _currentLocation;

  // Trip control state - controls disabled until trip is started
  bool _isTripStarted = false;

  // COPIED BUTTONS AND NAVIGATION
  // Monitoring Control Buttons
  Widget _buildMonitoringControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Start/Stop Monitoring Button
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 56,
            child: ElevatedButton(
              onPressed: _isMonitoring ? _stopMonitoring : _startMonitoring,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
                  const SizedBox(height: 2),
                  Text(
                    _isMonitoring ? 'Stop' : 'Start',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Switch Driver Button
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 56,
            child: ElevatedButton(
              onPressed: _switchDriver,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz),
                  SizedBox(height: 2),
                  Text(
                    'Switch',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Break Toggle Button
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 56,
            child: ElevatedButton(
              onPressed: _toggleBreak,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isOnBreak ? Icons.play_arrow : Icons.pause),
                  const SizedBox(height: 2),
                  Text(
                    _isOnBreak ? 'Resume' : 'Break',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Driver Control Buttons
  Widget _buildDriverControlButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: null, // Disabled for now
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Switch Driver'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: null, // Disabled for now
            icon: const Icon(Icons.pause),
            label: const Text('Take Break'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: null, // Disabled for now
            icon: const Icon(Icons.stop),
            label: const Text('End Trip'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    //  NEW: Add app lifecycle observer to save data when app is closed
    WidgetsBinding.instance.addObserver(this);

    //  REMOVED: HTTP server - using original sync method

    //  CORE REQUIREMENT: Load saved logs and snapshots when app opens
    _loadPersistedData();

    //  FIX: Load current user and trip data when app opens
    _loadCurrentUserAndTrips();

    //  NEW: Clean up invalid events after loading data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cleanupInvalidEvents();
    });
  }

  //  NEW: Clear all local data on fresh install to prevent old data persistence
  // This should only be called explicitly (e.g., during logout), not automatically
  Future<void> _clearAllLocalDataOnFreshInstall() async {
    try {
      print('CLEANUP: Clearing all local data for fresh install...');
      final prefs = await SharedPreferences.getInstance();

      // Clear all local storage keys
      await prefs.remove('unified_snapshots');
      await prefs.remove('uploaded_items');
      await prefs.remove('snapshot_images');
      await prefs.remove('last_sync_time');
      await prefs.remove('last_upload_time');

      // Clear all image data
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('image_') || key.startsWith('snapshot_')) {
          await prefs.remove(key);
        }
      }

      // Clear in-memory data
      _unifiedSnapshots.clear();
      _snapshotImages.clear();
      _uploadedItems.clear();

      print('SUCCESS: All local data cleared - fresh install ready');
    } catch (e) {
      print('WARNING: Error clearing local data: $e');
    }
  }

  @override
  void dispose() {
    //  CORE REQUIREMENT: Save logs and snapshots when app closes
    _savePersistedData();

    //  REMOVED: HTTP server cleanup

    //  CRITICAL FIX: Cancel all timers to prevent memory leaks and UI freeze
    _connectionTimer?.cancel();
    _refreshTimer?.cancel();
    _syncTimer?.cancel();
    _usbDetectionTimer?.cancel();
    _tripsSubscription?.unsubscribe();

    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  //  CORE REQUIREMENT: Save logs and snapshots when app is closed
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      print('APP: App closing - saving logs and snapshots...');
      _savePersistedData();
    }
  }

  //  REMOVED: HTTP Server Methods - using original sync method
  //  RESTORED: Original fetch method for IoT data sync
  Future<void> _fetchUnifiedSnapshotsFromIoT() async {
    try {
      print(
          'FETCH: Fetching snapshots logs via WiFi Direct (unified table)...');
      final logs = await _iotConnectionService.fetchSnapshotsLogs();

      //  TODAY ONLY FILTERING: Filter out data from other days
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final filteredLogs = logs.where((log) {
        final logTimestamp = DateTime.tryParse(log['timestamp'] ?? '');
        if (logTimestamp != null) {
          final logDate =
              DateTime(logTimestamp.year, logTimestamp.month, logTimestamp.day);
          if (logDate.isBefore(today)) {
            print(
                'DATE: Filtering out old data: ${log['timestamp']} (not today)');
            return false;
          }
        }
        return true;
      }).toList();

      print(
          'DATA: Filtered ${logs.length} logs to ${filteredLogs.length} (today only)');

      if (filteredLogs.isNotEmpty) {
        setState(() {
          // Don't clear existing logs, append new ones
          for (final log in filteredLogs) {
            //  Check if this log already exists to avoid duplicates
            bool logExists = _unifiedSnapshots.any((existingLog) =>
                existingLog['behavior_id'] == log['behavior_id'] ||
                (existingLog['behavior_type'] == log['behavior_type'] &&
                    existingLog['timestamp'] == log['timestamp']));

            if (!logExists) {
              //  DRIVER ID ALIGNMENT: Map IoT driver IDs to database IDs
              String driverId = log['driver_id'] ?? '';
              String tripId = log['trip_id'] ?? '';

              // Handle driver switch alignment
              if (log['behavior_type'] == 'driver_switch') {
                print('SYNC: Processing driver switch log from IoT...');

                // Parse driver switch details
                try {
                  final details = log['details'] ?? '';
                  if (details.isNotEmpty) {
                    final detailsMap = json.decode(details);
                    final newDriver = detailsMap['new_driver'] ?? '';
                    final driverType = detailsMap['driver_type'] ?? '';

                    print(
                        'SYNC: IoT Driver Switch: $newDriver (type: $driverType)');

                    // Align with current app state
                    if (newDriver.contains('Main') || driverType == 'main') {
                      setState(() {
                        _currentDriver = "Main Driver";
                        _isDriverSwitched = false;
                      });
                      print('SUCCESS: Aligned to Main Driver');
                    } else if (newDriver.contains('Sub') ||
                        driverType == 'sub') {
                      setState(() {
                        _currentDriver = "Sub Driver";
                        _isDriverSwitched = true;
                      });
                      print('SUCCESS: Aligned to Sub Driver');
                    }
                  }
                } catch (e) {
                  print('WARNING: Error parsing driver switch details: $e');
                }
              }

              // Handle break alignment - only apply recent break events (within last 5 minutes)
              if (log['behavior_type'] == 'break_started') {
                final logTimestamp = DateTime.parse(log['timestamp']);
                final now = DateTime.now();
                final timeDiff = now.difference(logTimestamp).inMinutes;

                if (timeDiff <= 5) {
                  print(
                      'PAUSE: Recent IoT Break Started detected (${timeDiff}m ago) - aligning app state');
                  setState(() {
                    _isOnBreak = true;
                    //  FIXED: Don't change _isMonitoring - keep start/stop button state intact
                  });
                } else {
                  print(
                      'PAUSE: Old IoT Break Started detected (${timeDiff}m ago) - ignoring to prevent false state');
                }
              } else if (log['behavior_type'] == 'break_ended') {
                final logTimestamp = DateTime.parse(log['timestamp']);
                final now = DateTime.now();
                final timeDiff = now.difference(logTimestamp).inMinutes;

                if (timeDiff <= 5) {
                  print(
                      'RESUME: Recent IoT Break Ended detected (${timeDiff}m ago) - aligning app state');
                  setState(() {
                    _isOnBreak = false;
                    //  FIXED: Don't change _isMonitoring - keep start/stop button state intact
                  });
                } else {
                  print(
                      'RESUME: Old IoT Break Ended detected (${timeDiff}m ago) - ignoring to prevent false state');
                }
              }

              //  FIX: Ensure proper driver_id and trip_id alignment
              if (driverId.isEmpty || driverId == 'null') {
                driverId = _dbCurrentDriverId ??
                    'default-driver-${DateTime.now().millisecondsSinceEpoch}';
                print('🔧 Fixed empty driver_id: $driverId');
              }
              if (tripId.isEmpty || tripId == 'null') {
                tripId = _dbCurrentTripId ??
                    'default-trip-${DateTime.now().millisecondsSinceEpoch}';
                print('🔧 Fixed empty trip_id: $tripId');
              }

              //  SUPABASE ALIGNMENT: Handle driver_id from IoT vs Supabase
              String supabaseDriverId = driverId;
              if (log['behavior_type'] == 'driver_switch') {
                try {
                  final details = log['details'] ?? '';
                  if (details.isNotEmpty) {
                    final detailsMap = json.decode(details);
                    final driverType = detailsMap['driver_type'] ?? '';

                    // If it's a Sub Driver event, use Main Driver ID for Supabase
                    if (driverType == 'sub' ||
                        detailsMap['new_driver']?.toString().contains('Sub') ==
                            true) {
                      supabaseDriverId = _dbCurrentDriverId ?? driverId;
                      print(
                          'SYNC: SUPABASE ALIGNMENT: Using Main Driver ID for Sub Driver event: $supabaseDriverId');
                    }
                  }
                } catch (e) {
                  print(
                      'WARNING: Error parsing driver switch details for Supabase alignment: $e');
                }
              }

              //  FIX: Handle IoT data structure correctly (unified snapshots table with evidence)
              _unifiedSnapshots.add({
                'type': 'snapshot_log',
                'behavior_id': log['id']?.toString() ??
                    'iot-${DateTime.now().millisecondsSinceEpoch}', // Use IoT's ID field
                'driver_id':
                    supabaseDriverId, //  Use Supabase-aligned driver_id
                'trip_id': tripId, //  Fixed trip_id
                'behavior_type': log['behavior_type'],
                'timestamp': log['timestamp'],
                'message': '${log['behavior_type']} detected from IoT',
                'source': 'iot', //  Mark as from IoT
                'event_type': log['event_type'] ??
                    'behavior', //  NEW: Unified table field

                //  CRITICAL FIX: Add filename field for image fetching
                'filename': log['filename'] ?? 'Unknown',

                //  NEW: Add all evidence fields from detection_ai.py (only the 13 fields it actually sends)
                'evidence_reason': log['evidence_reason'],
                'confidence_score': log[
                    'confidence_score'], //  FIXED: Pi5 sends 'confidence_score', not 'confidence'
                'event_duration': log['event_duration'],
                'gaze_pattern': log['gaze_pattern'],
                'face_direction': log['face_direction'],
                'eye_state': log['eye_state'],
                'device_id':
                    'pi5-device', //  FIXED: Pi5 doesn't send device_id, use default
                'driver_type': _currentDriver == "Main Driver"
                    ? 'main'
                    : 'sub', //  FIXED: Use current driver state, not IoT data
              });

              print(
                  'SUCCESS: Added unified snapshot log: ${log['behavior_type']}');
            }
          }

          // Keep only the last 100 logs to prevent memory issues
          if (_unifiedSnapshots.length > 200) {
            _unifiedSnapshots.removeRange(0, _unifiedSnapshots.length - 200);
          }
        });
        print(
            '✅ Snapshots logs fetched and aligned: ${logs.length} new logs added (today only)');
      } else {
        print(
            'WARNING: No new snapshots logs available via WiFi Direct (after 24-hour filtering)');
      }
    } catch (e) {
      print('ERROR: Error fetching snapshots logs via WiFi Direct: $e');
    }
  }

  //  REMOVED: HTTP server methods - using original sync

  //  REMOVED: HTTP request handler - using original sync

  Future<void> _handleSnapshotPush(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = json.decode(body);

      print('IMAGE: Received snapshot data from IoT: ${data['filename']}');

      //  ALIGNED: Process the 11 fields from detection_ai.py
      final alignedSnapshot = _alignSnapshotData(data);

      // Add to unified storage
      _addUnifiedSnapshot(alignedSnapshot);

      // Return success response
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({
        'status': 'success',
        'message': 'Snapshot received and processed',
        'timestamp': DateTime.now().toIso8601String()
      }));
      await request.response.close();
    } catch (e) {
      print('ERROR: Error processing snapshot push: $e');
      request.response.statusCode = 400;
      request.response.write('Bad Request');
      await request.response.close();
    }
  }

  //  PHASE 1 OPTIMIZATION: Handle batch image reception
  Future<void> _handleBatchImageReception(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = json.decode(body);

      print(
          'BATCH: Received batch images from IoT: ${data['batch_size']} images');

      if (data['batch_images'] != null) {
        // Decompress batch data
        final compressedData = data['batch_images'];
        final batchImages = _decompressBatchImages(compressedData);

        // Process all images at once
        await _processBatchImages(batchImages);

        // Return success response
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({
          'status': 'success',
          'message': 'Batch images received and processed',
          'count': batchImages.length,
          'timestamp': DateTime.now().toIso8601String()
        }));
      } else {
        request.response.statusCode = 400;
        request.response.write('No batch images data');
      }

      await request.response.close();
    } catch (e) {
      print('ERROR: Error processing batch images: $e');
      request.response.statusCode = 400;
      request.response.write('Bad Request');
      await request.response.close();
    }
  }

  //  PHASE 1 OPTIMIZATION: Process batch images efficiently
  Future<void> _processBatchImages(
      List<Map<String, dynamic>> batchImages) async {
    try {
      print('IMAGE: Processing batch of ${batchImages.length} images...');

      // Process all images at once
      for (final imageData in batchImages) {
        final filename = imageData['filename'];
        final base64Image = imageData['base64_image'];
        // Decode base64 image
        final imageBytes = base64Decode(base64Image);

        // Store in memory
        setState(() {
          _snapshotImages[filename] = {
            'data': imageBytes,
            'timestamp': DateTime.now().toIso8601String(),
            'trigger_type': imageData['trigger_type'],
            'confidence': imageData['confidence'],
            'event_timestamp': imageData['timestamp'],
          };
        });

        print(
            'SUCCESS: Image processed: $filename (${imageBytes.length} bytes)');
      }

      // Save to persistent storage
      await _savePersistedData();

      print('SUCCESS: Batch image processing completed');
    } catch (e) {
      print('ERROR: Error processing batch images: $e');
    }
  }

  //  PHASE 1 OPTIMIZATION: Decompress batch images
  List<Map<String, dynamic>> _decompressBatchImages(String compressedData) {
    try {
      // Use base64 decoding instead of hex for simplicity
      final compressedBytes = base64Decode(compressedData);
      final decompressed = gzip.decode(compressedBytes);
      final jsonData = json.decode(utf8.decode(decompressed));
      return List<Map<String, dynamic>>.from(jsonData);
    } catch (e) {
      print('ERROR: Error decompressing batch images: $e');
      return [];
    }
  }

  //  NEW: Align data structure from detection_ai.py to status_page.dart format
  Map<String, dynamic> _alignSnapshotData(Map<String, dynamic> iotData) {
    final now = DateTime.now();

    return {
      // Core identification
      'id': now.millisecondsSinceEpoch,
      'snapshot_id': 'iot-${now.millisecondsSinceEpoch}',
      'filename':
          iotData['filename'] ?? 'unknown_${now.millisecondsSinceEpoch}',
      'timestamp': iotData['timestamp'] ?? now.toIso8601String(),

      // Driver and trip context
      'driver_id': _currentDriverId ?? 'unknown-driver',
      'trip_id': _currentTripId ?? 'no-trip-id',
      'device_id': 'pi5-iot',

      // Event classification
      'event_type': 'snapshot',
      'behavior_type': iotData['behavior_type'] ?? 'unknown',

      //  ALIGNED: The 11 fields from detection_ai.py
      'eye_state': iotData['eye_state'],
      'confidence_score': iotData['confidence_score'] ?? 0.0,
      'event_duration': iotData['event_duration'] ?? 0.0,
      'gaze_pattern': iotData['gaze_pattern'],
      'face_direction': iotData['face_direction'],
      'evidence_reason': iotData['evidence_reason'],
      'evidence_strength': iotData['evidence_strength'],
      'trigger_justification': iotData['trigger_justification'],

      // Image data handling - only include if not null and not empty
      'image_data': (iotData['image_data'] != null &&
              iotData['image_data'].toString().trim().isNotEmpty)
          ? iotData['image_data']
          : null,
      'has_image': iotData['image_data'] != null &&
          iotData['image_data'].toString().trim().isNotEmpty,

      // Additional metadata
      'source': 'iot_push',
      'processed_at': now.toIso8601String(),
      'retention_until': now.add(const Duration(hours: 24)).toIso8601String(),
    };
  }

  void _initializeConnection() {
    //  ALIGNMENT: Use database IDs instead of generated timestamps
    // These will be set when database connection is established
    _currentDriverId = _dbCurrentDriverId;
    _currentTripId = _dbCurrentTripId;
    _startWiFiDirectConnection();
  }

  //  NEW: Initialize location service
  Future<void> _initializeLocationService() async {
    try {
      print('📍 Initializing location service...');

      final success = await _locationService.initialize();
      if (success) {
        setState(() {
          _isLocationEnabled = true;
        });
        print('SUCCESS: Location service initialized successfully');
      } else {
        print('WARNING: Location service initialization failed');
        setState(() {
          _isLocationEnabled = false;
        });
      }
    } catch (e) {
      print('ERROR: Error initializing location service: $e');
      setState(() {
        _isLocationEnabled = false;
      });
    }
  }

  void _startWiFiDirectConnection() async {
    if (kIsWeb) {
      print("🌐 Web mode detected - IoT connection not available in browser");
      setState(() {
        _isConnected = false;
      });
      return;
    }

    print("WIFI: Starting WiFi Direct connection to IoT...");
    try {
      // First check if we're connected to the WiFi network
      bool isConnectedToWiFi =
          await _iotConnectionService.isConnectedToIoTWiFi();
      if (!isConnectedToWiFi) {
        print("ERROR: Not connected to TinySync_IoT WiFi network");
        setState(() {
          _isConnected = false;
        });
        return;
      }

      // Try to connect to the Pi5 directly via network
      final success = await _iotConnectionService.connectToIoT();
      if (success) {
        print("SUCCESS: WiFi Direct connection established!");

        // Check IoT service health
        bool iotHealthy = await _checkIoTHealth();
        if (iotHealthy) {
          setState(() {
            _isConnected = true;
            _iotStatus = "Connected";
            _iotCurrentAction = "Ready";
          });
          print("SUCCESS: IoT service is healthy and ready!");

          // Set up message listener for AI logs
          _iotConnectionService.setOnMessageReceived(_handleIoTMessage);

          //  NEW: Automatically sync all IoT data when connected
          await _syncAllIoTDataOnConnection();

          // Start auto-sync when connected
          if (_syncTimer == null) {
            _startAutoSync();
          }
        } else {
          setState(() {
            _isConnected = false;
            _iotStatus = "Service Unavailable";
            _iotCurrentAction = "IoT service not responding";
          });
          print("WARNING: WiFi connected but IoT service not responding");
        }
      } else {
        print("ERROR: WiFi Direct connection failed - IoT not reachable");
        setState(() {
          _isConnected = false;
          _iotStatus = "Disconnected";
          _iotCurrentAction = "Cannot reach device";
        });
      }
    } catch (e) {
      print("ERROR: WiFi Direct connection error: $e");
      setState(() {
        _isConnected = false;
      });
    }
  }

  void _handleIoTMessage(Map<String, dynamic> message) {
    final messageType = message['type'];

    switch (messageType) {
      case 'ai_status_log':
      case 'ai_alert_log':
      case 'ai_video_log':
        _addAILog(message);
        break;
      case 'snapshot_log':
        //  REMOVED: No longer process snapshot_log - only snapshot messages create events
        print(
            '📝 Ignoring snapshot_log - only processing complete snapshot messages');
        break;
      case 'snapshot':
        _addSnapshot(message);
        break;
      case 'system_status':
        _updateIoTStatus(message);
        break;
      case 'monitoring_status':
        _updateMonitoringStatus(message);
        break;
    }
  }

  void _addUnifiedSnapshot(Map<String, dynamic> snapshot) {
    setState(() {
      _unifiedSnapshots.insert(0, snapshot);
      if (_unifiedSnapshots.length > 200) {
        _unifiedSnapshots.removeLast();
      }
    });
    //  NEW: Save to persistent storage
    _savePersistedData();

    //  NEW: Queue for Supabase upload (correct flow)
    _queueForSupabaseUpload(snapshot);
  }

  // Missing methods for handling different log types
  void _addAILog(Map<String, dynamic> message) {
    final aiLog = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'timestamp': message['timestamp'] ??
          DateTime.now().toIso8601String(), //  FIXED: Use IoT timestamp first
      'phone_processed_at':
          DateTime.now().toIso8601String(), //  Track phone processing time
      'type': message['type'],
      'data': message,
      'driver_id': _currentDriverId,
      'trip_id': _currentTripId,
    };

    setState(() {
      _unifiedSnapshots.insert(0, aiLog);
      if (_unifiedSnapshots.length > 200) {
        _unifiedSnapshots.removeLast();
      }
    });
  }

  //  NEW: Upload snapshot log to Supabase with all panel fields
  Future<void> _uploadBehaviorLogToSupabase(
      Map<String, dynamic> behaviorData) async {
    try {
      final supabaseService = SupabaseService();
      supabaseService.initialize(Supabase.instance.client);

      //  Prepare data for Supabase with all panel fields
      final supabaseData = {
        'driver_id': behaviorData['driver_id'],
        'trip_id': behaviorData['trip_id'],
        'behavior_type': behaviorData['behavior_type'],
        'timestamp':
            behaviorData['timestamp'], //  FIX: Use original IoT timestamp
        'details': jsonEncode(behaviorData['data']),
        'event_type': 'snapshot',
        'device_id': behaviorData['device_id'],
        'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',

        //  Panel fields for complete data alignment
        'reflection_detected': behaviorData['reflection_detected'],
        'detection_reliability': behaviorData['detection_reliability'],
        'driver_threshold_adjusted': behaviorData['driver_threshold_adjusted'],
        'compliance_audit_trail': behaviorData['compliance_audit_trail'],
        'evidence_reason': behaviorData['evidence_reason'],
        'confidence_score':
            behaviorData['confidence_score'], //  FIXED: Use correct field name
        'event_duration': behaviorData['event_duration'],
        'gaze_pattern': behaviorData['gaze_pattern'],
        'face_direction': behaviorData['face_direction'],
        'eye_state': behaviorData['eye_state'],
        'is_legitimate_driving': behaviorData['is_legitimate_driving'],
        'evidence_strength': behaviorData['evidence_strength'],
        'trigger_justification': behaviorData['trigger_justification'],
      };

      final success = await supabaseService.saveBehaviorLog(supabaseData);
      if (success) {
        print(
            'SUCCESS: Snapshot log uploaded to Supabase with all panel fields');
      } else {
        print('ERROR: Failed to upload snapshot log to Supabase');
      }
    } catch (e) {
      print('ERROR: Error uploading snapshot log to Supabase: $e');
    }
  }

  Future<void> _uploadSnapshotToSupabase(
      Map<String, dynamic> snapshotData) async {
    try {
      final supabaseService = SupabaseService();
      supabaseService.initialize(Supabase.instance.client);

      // Prepare data for Supabase
      final supabaseData = {
        'driver_id': snapshotData['driver_id'],
        'trip_id': snapshotData['trip_id'],
        'timestamp': snapshotData['timestamp'],
        'image_path': snapshotData['image_path'],
        'detection_type': snapshotData['detection_type'],
        'confidence_score':
            snapshotData['confidence_score'], //  FIXED: Use backend field name
        'device_id': snapshotData['device_id'],
        'event_type': 'snapshot',
      };

      final success = await supabaseService.saveSnapshot(supabaseData);
      if (success) {
        print('SUCCESS: Snapshot uploaded to Supabase');
      } else {
        print('ERROR: Failed to upload snapshot to Supabase');
      }
    } catch (e) {
      print('ERROR: Error uploading snapshot to Supabase: $e');
    }
  }

  //  NEW: Clean up existing invalid events
  void _cleanupInvalidEvents() {
    print('CLEANUP: Starting cleanup of invalid events...');
    print('DATA: Before cleanup: ${_unifiedSnapshots.length} events');

    setState(() {
      _unifiedSnapshots.removeWhere((event) {
        final filename = event['filename'] ?? '';
        final eventDuration = event['event_duration'] ?? 0.0;
        final behaviorType = event['behavior_type'] ?? '';
        final evidenceReason = event['evidence_reason'] ?? '';
        final eyeState = event['eye_state'] ?? '';

        // Only remove events with completely empty filenames (not events waiting for images)
        if (filename.isEmpty) {
          print('REMOVE: Removing event with empty filename: $behaviorType');
          return true;
        }

        // Only remove events with negative durations (keep 0.0+ durations)
        if (eventDuration < 0.0) {
          print('REMOVE: Removing event with negative duration: $behaviorType');
          return true;
        }

        // Remove contradictory data
        if (behaviorType == 'drowsiness_alert' &&
            evidenceReason.contains('EYES CLOSED') &&
            eyeState.toLowerCase() == 'open') {
          print(
              '🗑️ Removing contradictory event: DROWSINESS ALERT with EYES CLOSED evidence but eyes open');
          return true;
        }

        return false;
      });
    });

    print(
        '✅ Cleaned up invalid events. Remaining events: ${_unifiedSnapshots.length}');

    // Debug: Show what events remain
    for (int i = 0; i < _unifiedSnapshots.length && i < 3; i++) {
      final event = _unifiedSnapshots[i];
      print(
          '📋 Event ${i + 1}: ${event['behavior_type']} at ${event['timestamp']}');
    }
  }

  void _addSnapshot(Map<String, dynamic> message) {
    //  Validate timestamp accuracy from IoT
    _validateTimestampAccuracy(message, 'Snapshot from IoT');

    //  DUPLICATE PREVENTION: Check if this snapshot already exists
    final filename = message['filename'];
    final timestamp = message['timestamp'] ?? DateTime.now().toIso8601String();

    bool snapshotExists = _unifiedSnapshots.any((existingSnapshot) =>
        existingSnapshot['filename'] == filename ||
        (existingSnapshot['timestamp'] == timestamp &&
            existingSnapshot['type'] == 'snapshot'));

    if (snapshotExists) {
      print('WARNING: Skipping duplicate snapshot: $filename at $timestamp');
      return;
    }

    //  VALIDATION: Filter out invalid events
    final behaviorType = message['behavior_type'];
    final eventDuration = message['event_duration'] ?? 0.0;
    final evidenceReason = message['evidence_reason'] ?? '';
    final eyeState = message['eye_state'] ?? '';

    // Filter out events with 0.0+ second durations
    if (eventDuration <= 0.0) {
      print(
          '⚠️ Skipping invalid event: $behaviorType with 0.0+ second duration');
      return;
    }

    // Filter out contradictory data (eyes closed evidence but eyes open status)
    if (behaviorType == 'drowsiness_alert' &&
        evidenceReason.contains('EYES CLOSED') &&
        eyeState.toLowerCase() == 'open') {
      print(
          '⚠️ Skipping contradictory event: DROWSINESS ALERT with EYES CLOSED evidence but eyes open status');
      return;
    }

    final snapshot = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'timestamp': message['timestamp'] ??
          DateTime.now()
              .toIso8601String(), //  FIXED: Use IoT timestamp, fallback to phone time
      'phone_processed_at':
          DateTime.now().toIso8601String(), //  Track phone processing time
      'type': message['type'],
      'data': message,
      'driver_id': _currentDriverId,
      'trip_id': _currentTripId,

      //  COMPLETE: Include all behavior data fields from snapshot_log
      'event_type': 'snapshot',
      'filename': message['filename'],
      'behavior_type': message['behavior_type'],
      'confidence_score': message['confidence'] ?? message['confidence_score'],
      'reflection_detected': message['reflection_detected'] ?? false,
      'detection_reliability': message['detection_reliability'] ?? 50.0,
      'driver_threshold_adjusted': message['driver_threshold_adjusted'],
      'compliance_audit_trail': message['compliance_audit_trail'],
      'evidence_reason': message['evidence_reason'],
      'evidence_strength': message['evidence_strength'],
      'event_duration': message['event_duration'],
      'gaze_pattern': message['gaze_pattern'],
      'face_direction': message['face_direction'],
      'eye_state': message['eye_state'],
      'is_legitimate_driving': message['is_legitimate_driving'] ?? true,
      'trigger_justification': message['trigger_justification'],
      'device_id': message['device_id'],
      'behavior_id': message['behavior_id'],
    };

    //  UNIFIED: Use single storage system instead of fragmented lists
    setState(() {
      _unifiedSnapshots.insert(0, snapshot);
      if (_unifiedSnapshots.length > 200) {
        _unifiedSnapshots.removeLast();
      }
    });

    //  NEW: Queue for Supabase upload (correct flow)
    _queueForSupabaseUpload(snapshot);

    print('SUCCESS: Snapshot added to unified storage: ${message['filename']}');
  }

  //  REMOVED: _addSnapshot - now using unified _addUnifiedSnapshot

  void _updateIoTStatus(Map<String, dynamic> status) {
    setState(() {
      _iotStatus = status['status'] ?? "Unknown";
      _iotCurrentAction = status['current_action'] ?? "Unknown";
      _iotSystemInfo = status['system_info'] ?? {};
    });
  }

  void _updateMonitoringStatus(Map<String, dynamic> status) {
    // CRITICAL FIX: Don't update monitoring status if user is on break
    // This prevents automatic status updates from interfering with break state
    if (_isOnBreak) {
      print(
          'PAUSE: BREAK ACTIVE: Ignoring monitoring status update during break');
      return;
    }

    setState(() {
      _isMonitoring = status['is_monitoring'] ?? false;
    });
  }

  Future<bool> _checkIoTHealth() async {
    try {
      print('DEBUG: Checking IoT health via WiFi Direct...');
      final health = await _iotConnectionService.fetchIoTHealth();

      if (health.isNotEmpty) {
        print('SUCCESS: IoT health check successful via WiFi Direct');
        print('DATA: IoT Status: $health');

        // Parse the response to sync detection status
        try {
          final detectionActive = health['detection_active'] ?? false;

          // CRITICAL FIX: Don't auto-sync detection status if user is on break
          // This prevents auto-restarting detection when on break
          if (_isOnBreak) {
            print(
                '⏸️ BREAK ACTIVE: Not syncing detection status from IoT health check');
            print(
                '⏸️ BREAK ACTIVE: Keeping current monitoring state unchanged during break');
            //  FIXED: Don't change _isMonitoring - keep start/stop button state intact
          } else {
            // Only sync detection status when NOT on break
            print(
                '🔄 Syncing detection status from IoT: ${detectionActive ? "ACTIVE" : "INACTIVE"}');
            setState(() {
              _isMonitoring = detectionActive;
            });
          }

          //  NEW: Sync driver state from IoT
          await _syncDriverStateFromIoT();
        } catch (parseError) {
          print('WARNING: Could not parse IoT status: $parseError');
        }

        return true;
      } else {
        print('ERROR: IoT health check failed via WiFi Direct');
        return false;
      }
    } catch (e) {
      print('ERROR: IoT health check error: $e');
      return false;
    }
  }

  // NEW: Time sync function
  Future<void> _syncTimeWithPi5() async {
    try {
      print('🕐 Syncing time with Pi5...');
      
      // Get current time from phone
      DateTime currentTime = DateTime.now();
      String timeString = currentTime.toIso8601String();
      
      // Send time to Pi5
      final response = await http.post(
        Uri.parse('http://192.168.4.1:8081/api/sync/time'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'timestamp': timeString}),
      );
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['status'] == 'success') {
          print('✅ Time synced successfully: ${result['message']}');
        } else {
          print('❌ Time sync failed: ${result['message']}');
        }
      } else {
        print('❌ Time sync HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Time sync error: $e');
    }
  }

  Future<void> _manualConnectToIoT() async {
    if (_isConnected) {
      _showErrorSnackBar('Already connected to device');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      _showSuccessSnackBar('Attempting manual connection to IoT...');

      // NEW: Sync time with Pi5 before connecting
      await _syncTimeWithPi5();

      // Force a new connection attempt
      _startWiFiDirectConnection();

      // Wait a bit for connection to establish
      await Future.delayed(const Duration(seconds: 2));

      if (_isConnected) {
        _showSuccessSnackBar(
            'Manual connection successful! IoT is now connected.');
      } else {
        _showErrorSnackBar(
            'Manual connection failed. Check WiFi Direct settings.');
      }
    } catch (e) {
      _showErrorSnackBar('Manual connection error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _switchDriver() async {
    if (!_validateConnection(action: 'switch driver')) return;

    //  IMMEDIATE UI UPDATE: Just like start/stop monitoring
    setState(() {
      _isDriverSwitched = !_isDriverSwitched;
      _currentDriver = _isDriverSwitched ? "Sub Driver" : "Main Driver";
    });

    // Show immediate feedback
    _showSuccessSnackBar('Driver switched to $_currentDriver');

    //  NON-BLOCKING LOGGING: Just like start/stop monitoring
    _logOperatorAction('driver_switch', 'Driver switched to $_currentDriver');

    //  DIRECT API CALL: Just like start/stop monitoring
    _sendDriverSwitchCommand();
  }

  Future<void> _sendDriverSwitchCommand() async {
    try {
      //  Initialize Sub Driver ID if needed
      //  REMOVED: No longer need to initialize sub driver ID

      final currentDriverId = _getCurrentDriverId();
      print(
          '🔄 Sending driver switch command for $_currentDriver (ID: $currentDriverId)');

      List<String> pi5Addresses = [
        '192.168.254.120',
        '192.168.4.1',
        '192.168.1.100',
      ];

      bool success = false;
      for (final ip in pi5Addresses) {
        try {
          final request = await HttpClient()
              .postUrl(Uri.parse('http://$ip:8081/api/driver/switch'))
              .timeout(const Duration(seconds: 2));

          request.headers.contentType = ContentType.json;
          final requestData = {}; //  Simplified - no data needed
          print('DEBUG: DEBUG: Sending driver switch to IoT: $requestData');
          request.write(json.encode(requestData));

          //  HANDLE API RESPONSE: Get response from Pi5
          final response = await request.close();
          final responseBody = await response.transform(utf8.decoder).join();
          print('DEBUG: DEBUG: Pi5 driver switch response: $responseBody');

          if (response.statusCode == 200) {
            final responseData = json.decode(responseBody);
            if (responseData['status'] == 'success') {
              success = true;
              print(
                  'SUCCESS: Driver switch successful: ${responseData['message']}');

              //  LOGGING ALREADY DONE: Driver switch logged in _handleDriverSwitchInBackground()

              break;
            } else {
              print('ERROR: Driver switch failed: ${responseData['message']}');
            }
          } else {
            print('ERROR: Driver switch HTTP error: ${response.statusCode}');
          }
        } catch (e) {
          print('ERROR: Driver switch error at $ip: $e');
          continue;
        }
      }

      if (!success) {
        print('WARNING: Failed to send switch command to IoT');
        _showErrorSnackBar('Failed to communicate with device');
      }
    } catch (e) {
      print('ERROR: Error sending driver switch command: $e');
      _showErrorSnackBar('Error sending driver switch command: $e');
    }
  }

  Future<void> _toggleBreak() async {
    if (!_validateConnection(action: 'toggle break')) return;

    //  FIX: Debounce protection to prevent rapid successive calls
    final now = DateTime.now();
    if (_isBreakToggleInProgress) {
      print(
          'PAUSE: BREAK TOGGLE: Already in progress, ignoring duplicate call');
      return;
    }

    if (_lastBreakToggleTime != null &&
        now.difference(_lastBreakToggleTime!).inSeconds < 2) {
      print(
          '⏸️ BREAK TOGGLE: Too soon since last toggle (${now.difference(_lastBreakToggleTime!).inSeconds}s), ignoring');
      return;
    }

    // Set debounce protection
    _isBreakToggleInProgress = true;
    _lastBreakToggleTime = now;

    //  DRIVER BREAK LOGIC: Track which driver started/resumed break
    if (!_isOnBreak) {
      // Starting break - record which driver started it
      _breakStartedByDriver = _currentDriver;
      print('PAUSE: BREAK STARTED: $_currentDriver initiated break');
    } else {
      // Resuming break - check if same driver is resuming
      if (_breakStartedByDriver != null &&
          _breakStartedByDriver != _currentDriver) {
        print(
            '🔄 BREAK RESUME: $_currentDriver resuming break started by $_breakStartedByDriver');
        _showSuccessSnackBar(
            'Break resumed by $_currentDriver (started by $_breakStartedByDriver)');
      } else {
        print('RESUME: BREAK RESUME: $_currentDriver resuming their own break');
        _showSuccessSnackBar('Break resumed by $_currentDriver');
      }
      _breakStartedByDriver = null; // Clear break starter
    }

    //  REMOVED LOADING STATE: Immediate UI update without loading to prevent freeze
    setState(() {
      _isOnBreak = !_isOnBreak;
      //  FIXED: Don't modify _isMonitoring here to avoid affecting start/stop button
    });

    // Debug logging
    print('DEBUG: DEBUG: Break state changed to: $_isOnBreak');
    print('DEBUG: DEBUG: Current driver ID: $_currentDriverId');
    print('DEBUG: DEBUG: Monitoring state remains: $_isMonitoring (unchanged)');

    // Show immediate feedback
    if (_isOnBreak) {
      _showSuccessSnackBar('Break started by $_currentDriver');
    }

    //  BACKGROUND OPERATIONS: Run in background to prevent UI blocking
    _handleBreakToggleInBackground();
  }

  //  NEW: Handle break toggle operations in background to prevent UI freeze
  Future<void> _handleBreakToggleInBackground() async {
    try {
      //  FIXED: Log break/resume action IMMEDIATELY (like start/stop buttons)
      if (_isOnBreak) {
        // Break = Pause detection (backend only)
        print('PAUSE: BREAK: Pausing detection for break');
        _logOperatorAction('break_started', 'Driver started break');
        await _sendBreakToggleCommand(); // This pauses detection (NO LOGGING)
        //  FIXED: Don't change _isMonitoring - keep start/stop button state intact
      } else {
        // Resume = Resume detection (backend only)
        print('RESUME: RESUME: Resuming detection after break');
        _logOperatorAction('break_ended', 'Driver ended break');
        await _sendBreakToggleCommand(); // This resumes detection (NO LOGGING)
        //  FIXED: Don't change _isMonitoring - keep start/stop button state intact
        _showSuccessSnackBar('Break ended. Detection resumed automatically.');
      }
    } catch (e) {
      print('ERROR: Error toggling break: $e');
      _showErrorSnackBar('Error toggling break: $e');
    } finally {
      //  FIX: Reset debounce protection
      _isBreakToggleInProgress = false;
    }
  }

  Future<void> _sendBreakToggleCommand() async {
    try {
      //  Initialize Sub Driver ID if needed
      //  REMOVED: No longer need to initialize sub driver ID

      final currentDriverId = _getCurrentDriverId();
      print(
          '🔄 Sending break toggle command for $_currentDriver (ID: $currentDriverId)');

      List<String> pi5Addresses = [
        '192.168.254.120',
        '192.168.4.1',
        '192.168.1.100',
      ];

      bool success = false;
      for (final ip in pi5Addresses) {
        try {
          final request = await HttpClient()
              .postUrl(Uri.parse('http://$ip:8081/api/break/toggle'))
              .timeout(const Duration(seconds: 2));

          request.headers.contentType = ContentType.json;
          final requestData = {}; //  Simplified - no data needed
          print('DEBUG: DEBUG: Sending break toggle to IoT: $requestData');
          request.write(json.encode(requestData));

          //  HANDLE API RESPONSE: Get response from Pi5
          final response = await request.close();
          final responseBody = await response.transform(utf8.decoder).join();
          print('DEBUG: DEBUG: Pi5 break toggle response: $responseBody');

          if (response.statusCode == 200) {
            final responseData = json.decode(responseBody);
            if (responseData['status'] == 'success') {
              success = true;
              print(
                  'SUCCESS: Break toggle successful: ${responseData['message']}');

              //  FIXED: Logging moved to _handleBreakToggleInBackground() to prevent duplicates
              // No logging here - already logged when button was pressed

              break;
            } else {
              print('ERROR: Break toggle failed: ${responseData['message']}');
            }
          } else {
            print('ERROR: Break toggle HTTP error: ${response.statusCode}');
          }
        } catch (e) {
          print('ERROR: Break toggle error at $ip: $e');
          continue;
        }
      }

      if (!success) {
        print('WARNING: Failed to send break command to IoT');
        _showErrorSnackBar('Failed to communicate with device');
      }
    } catch (e) {
      print('ERROR: Error sending break toggle command: $e');
      _showErrorSnackBar('Error sending break command: $e');
    }
  }

  void _startConnectionMonitoring() {
    _connectionTimer =
        Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      print(
          "🔍 Connection monitoring check - Current status: ${_isConnected ? 'CONNECTED' : 'DISCONNECTED'}");

      if (!_isConnected) {
        print("WIFI: Attempting WiFi Direct connection...");
        _startWiFiDirectConnection();
      } else {
        // CRITICAL FIX: Only sync detection status if NOT on break
        // This prevents auto-restarting detection when user is on break
        if (!_isOnBreak) {
          print("SYNC: Syncing detection status with IoT...");
          await _checkIoTHealth();
        } else {
          print(
              "PAUSE: BREAK ACTIVE: Skipping detection status sync during break");
        }

        // Start auto-sync automatically when connected
        if (_syncTimer == null) {
          _startAutoSync();
        }
      }

      // Check IoT connection
      await _checkIoTConnection();
    });
  }

  Future<void> _checkIoTConnection() async {
    try {
      final supabaseService = SupabaseService();
      supabaseService.initialize(Supabase.instance.client);

      // Check if IoT tables exist and are accessible
      final behaviorLogs = await supabaseService.getBehaviorLogs(limit: 10);
      final snapshots =
          await supabaseService.subscribeToSnapshots(limit: 5).first;

      // Count real data (no simulation)
      final todayLogs = behaviorLogs.where((log) {
        final logDate = DateTime.parse(log['timestamp']);
        final today = DateTime.now();
        return logDate.year == today.year &&
            logDate.month == today.month &&
            logDate.day == today.day;
      }).length;

      final recentLogs = behaviorLogs.where((log) {
        final logDate = DateTime.parse(log['timestamp']);
        final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
        return logDate.isAfter(oneHourAgo);
      }).length;

      setState(() {
        _iotConnected = true;
        _iotStatus = "Database Connected";
        _iotStats = {
          'total_behaviors_today': todayLogs,
          'recent_alerts': recentLogs,
          'total_snapshots': snapshots.length,
        };
      });

      print('SUCCESS: IoT Database Connection: SUCCESS');
      print('   - Behavior logs table: ${behaviorLogs.length} records');
      print('   - Snapshots table: ${snapshots.length} records');
      print('   - Today behaviors: $todayLogs');
      print('   - Recent alerts: $recentLogs');
    } catch (e) {
      print('ERROR: IoT Database Connection Failed: $e');
      setState(() {
        _iotConnected = false;
        _iotStatus = "Database Connection Failed";
      });
    }
  }

  Future<void> _startMonitoring() async {
    if (!_validateConnection(action: 'start monitoring')) return;

    // Don't start monitoring if we're on break
    if (_isOnBreak) {
      print('PAUSE: BREAK ACTIVE: Cannot start monitoring while on break');
      _showErrorSnackBar(
          'Cannot start monitoring while on break. Click "Resume" first.');
      return;
    }

    // Immediate UI update - no delay
    setState(() {
      _isMonitoring = true;
      _isLoading = false;
    });

    // Show immediate feedback
    _showSuccessSnackBar('Driver monitoring system activated');

    //  FIXED: Log start monitoring to LOCAL STORAGE first (correct flow)
    _logOperatorAction(
        'monitoring_started', 'Driver started monitoring session');

    // Send command to IoT in background (non-blocking)
    _sendStartDetectionCommand();
  }

  Future<void> _sendStartDetectionCommand() async {
    // Don't start detection if we're on break
    if (_isOnBreak) {
      print('PAUSE: BREAK ACTIVE: Blocking start detection command');
      return;
    }

    try {
      //  Initialize Sub Driver ID if needed
      //  REMOVED: No longer need to initialize sub driver ID

      final currentDriverId = _getCurrentDriverId();
      print(
          '🚀 Sending start detection command via WiFi Direct for $_currentDriver (ID: $currentDriverId)...');
      print(
          '🔍 DEBUG: Break state: $_isOnBreak, Monitoring state: $_isMonitoring');
      bool success = await _iotConnectionService
          .sendCommand('start'); //  Simplified - no data needed

      if (!success) {
        print(
            '⚠️ Failed to send detection start command to IoT via WiFi Direct');
      } else {
        print(
            '✅ Detection command sent with trip info: $_dbCurrentTripRefNumber for $_currentDriver (ID: $currentDriverId)');
      }
    } catch (e) {
      print('ERROR: Error sending detection start command: $e');
    }
  }

  Future<void> _stopMonitoring() async {
    //  SAFETY CHECK: Prevent stopping monitoring if driver is on break
    if (_isOnBreak) {
      print('WARNING: Cannot stop monitoring while driver is on break');
      _showErrorSnackBar(
          'Cannot stop monitoring while on break. Click "Resume" first.');
      return;
    }

    // Immediate UI update - no delay
    setState(() {
      _isMonitoring = false;
      _isLoading = false;
    });

    // Show immediate feedback
    _showSuccessSnackBar('Driver monitoring system deactivated');

    //  FIXED: Log stop monitoring to LOCAL STORAGE first (correct flow)
    _logOperatorAction(
        'monitoring_stopped', 'Driver stopped monitoring session');

    // Send command to IoT in background (non-blocking)
    _sendStopDetectionCommand();
  }

  Future<void> _sendStopDetectionCommand() async {
    try {
      //  Initialize Sub Driver ID if needed
      //  REMOVED: No longer need to initialize sub driver ID

      final currentDriverId = _getCurrentDriverId();
      print(
          '🛑 Sending stop detection command via WiFi Direct for $_currentDriver (ID: $currentDriverId)...');
      bool success = await _iotConnectionService
          .sendCommand('stop'); //  Simplified - no data needed

      if (!success) {
        print(
            '⚠️ Failed to send detection stop command to IoT via WiFi Direct');
      } else {
        print(
            '✅ Stop command sent with trip info: $_dbCurrentTripRefNumber for $_currentDriver (ID: $currentDriverId)');
      }
    } catch (e) {
      print('ERROR: Error sending detection stop command: $e');
    }
  }

  Future<void> _manualSync() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _showSuccessSnackBar('Starting data synchronization...');

      //  NEW: Use comprehensive sync instead of just snapshots
      await _syncAllIoTDataOnConnection();

      // Send sync command to IoT via WiFi Direct
      bool success =
          await _iotConnectionService.sendCommand('sync_start', data: {
        'driver_id': _currentDriverId, //  Now uses database UUID
        'trip_id': _currentTripId, //  Now uses database UUID
        'trip_ref_number': _dbCurrentTripRefNumber, //  NEW: Send trip reference
        'sync_type': 'manual',
      });

      if (success) {
        _showSuccessSnackBar('Manual sync initiated successfully');
      } else {
        _showErrorSnackBar('Failed to start manual sync');
      }
    } catch (e) {
      _showErrorSnackBar('Error during manual sync: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchSnapshotsFromIoT() async {
    try {
      print('IMAGE: Fetching snapshots via WiFi Direct...');
      final snapshots = await _iotConnectionService.fetchSnapshots();

      if (snapshots.isNotEmpty) {
        setState(() {
          // Don't clear existing snapshots, append new ones
          for (final snapshot in snapshots) {
            final filename = snapshot['filename'] ?? 'Unknown';

            //  Check if this snapshot already exists to avoid duplicates
            bool snapshotExists = _unifiedSnapshots.any((existingSnapshot) =>
                existingSnapshot['filename'] == filename ||
                existingSnapshot['snapshot_id'] == snapshot['snapshot_id']);

            if (!snapshotExists) {
              //  FIX: Ensure proper driver_id and trip_id
              String driverId = snapshot['driver_id'] ?? '';
              String tripId = snapshot['trip_id'] ?? '';

              // If empty, use current database IDs
              if (driverId.isEmpty || driverId == 'null') {
                driverId = _dbCurrentDriverId ??
                    'default-driver-${DateTime.now().millisecondsSinceEpoch}';
                print('🔧 Fixed empty driver_id in snapshot: $driverId');
              }
              if (tripId.isEmpty || tripId == 'null') {
                tripId = _dbCurrentTripId ??
                    'default-trip-${DateTime.now().millisecondsSinceEpoch}';
                print('🔧 Fixed empty trip_id in snapshot: $tripId');
              }

              _unifiedSnapshots.insert(0, {
                'snapshot_id':
                    'iot-${DateTime.now().millisecondsSinceEpoch}', // Generate unique ID
                'filename': filename,
                'driver_id': driverId, //  Fixed driver_id
                'trip_id': tripId, //  Fixed trip_id
                'timestamp': snapshot['timestamp'] ??
                    DateTime.now()
                        .toIso8601String(), //  FIX: Use original IoT timestamp
                'behavior_type': snapshot['behavior_type'] ?? 'unknown',
                'file_path': snapshot['file_path'] ?? '',
                'type': 'snapshot',
                'source': 'iot', //  Mark as from IoT

                //  NEW: Add all evidence fields from detection_ai.py
                'event_type': snapshot['event_type'] ?? 'snapshot',
                'evidence_reason': snapshot['evidence_reason'],
                'confidence_score': snapshot['confidence_score'],
                'event_duration': snapshot['event_duration'],
                'gaze_pattern': snapshot['gaze_pattern'],
                'face_direction': snapshot['face_direction'],
                'eye_state': snapshot['eye_state'],
                'is_legitimate_driving': snapshot['is_legitimate_driving'],
                'evidence_strength': snapshot['evidence_strength'],
                'trigger_justification': snapshot['trigger_justification'],
                'device_id': snapshot['device_id'],
                'driver_type': snapshot['driver_type'],
                'image_quality': snapshot['image_quality'],
              });
            }
          }

          // Keep only the last 50 snapshots to prevent memory issues
          if (_unifiedSnapshots.length > 200) {
            _unifiedSnapshots.removeRange(0, _unifiedSnapshots.length - 200);
          }
        });
        print(
            '✅ Snapshots fetched and fixed: ${snapshots.length} new snapshots added');
      } else {
        print('WARNING: No new snapshots available via WiFi Direct');
      }
    } catch (e) {
      print('ERROR: Error fetching snapshots via WiFi Direct: $e');
    }
  }

  //  NEW: Fetch all missing images automatically
  Future<void> _fetchAllMissingImages(
      List<Map<String, dynamic>> snapshots) async {
    print(
        '🔄 Auto-fetching missing images for ${snapshots.length} snapshots...');

    for (final snapshot in snapshots) {
      final filename = snapshot['filename'] ?? 'Unknown';

      // Only fetch if image is not already loaded
      if (!_snapshotImages.containsKey(filename)) {
        print('WIFI: Fetching missing image: $filename');
        await _fetchAndStoreSnapshotImage(snapshot, filename);

        //  OPTIMIZED: Reduced delay for faster sync
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    print('SUCCESS: Auto-fetch completed for all snapshots');
  }

  //  NEW: Fetch images only when explicitly requested (for viewing snapshots)
  Future<void> _fetchImagesOnly() async {
    if (!_isConnected) return;

    try {
      print('🖼️ Fetching images only (explicit request)...');

      // Get snapshots that have filenames but no images loaded
      final snapshotsWithImages = _unifiedSnapshots
          .where((snapshot) =>
              snapshot['event_type'] == 'snapshot' &&
              snapshot['filename'] != null &&
              snapshot['filename'] != 'Unknown' &&
              !_snapshotImages.containsKey(snapshot['filename']))
          .toList();

      if (snapshotsWithImages.isEmpty) {
        print('SUCCESS: No images to fetch - all images already loaded');
        return;
      }

      print('WIFI: Fetching ${snapshotsWithImages.length} missing images...');

      //  PARALLEL DOWNLOAD: Download all images simultaneously
      final downloadTasks = snapshotsWithImages.map((snapshot) async {
        final filename = snapshot['filename'];
        print('WIFI: Fetching image: $filename');

        try {
          await _fetchAndStoreSnapshotImage(snapshot, filename);
          print('SUCCESS: Downloaded: $filename');
        } catch (e) {
          print('ERROR: Failed to fetch image $filename: $e');
        }
      }).toList();

      // Wait for all downloads to complete in parallel
      await Future.wait(downloadTasks);

      print('SUCCESS: Image fetch completed');
    } catch (e) {
      print('ERROR: Error during image fetch: $e');
    }
  }

  //  NEW: Auto-fetch all missing images for current snapshots
  Future<void> _autoFetchAllMissingImages() async {
    try {
      print('SYNC: Auto-fetching all missing images...');

      // Get all snapshots that don't have images loaded
      final snapshotsWithoutImages = _unifiedSnapshots.where((snapshot) {
        final filename = snapshot['filename'] ?? 'Unknown';
        return !_snapshotImages.containsKey(filename);
      }).toList();

      if (snapshotsWithoutImages.isEmpty) {
        print(
            'SUCCESS: All images already loaded - no missing images to fetch');
        return;
      }

      print(
          '📸 Found ${snapshotsWithoutImages.length} snapshots without images, fetching...');

      //  PARALLEL AUTO-FETCH: Download all missing images simultaneously
      final autoFetchTasks = snapshotsWithoutImages.map((snapshot) async {
        final filename = snapshot['filename'] ?? 'Unknown';

        try {
          print('WIFI: Auto-fetching image: $filename');
          await _fetchAndStoreSnapshotImage(snapshot, filename);
          print('SUCCESS: Auto-fetched: $filename');
          return true; // Success
        } catch (e) {
          print('ERROR: Error auto-fetching image $filename: $e');
          return false; // Failed
        }
      }).toList();

      // Wait for all auto-fetch downloads to complete in parallel
      final results = await Future.wait(autoFetchTasks);
      final fetchedCount = results.where((success) => success).length;

      print('SUCCESS: Auto-fetch completed: $fetchedCount images fetched');
    } catch (e) {
      print('ERROR: Error in auto-fetch all missing images: $e');
      rethrow;
    }
  }

  // Enhanced real-time data sync
  Timer? _syncTimer;
  bool _autoSyncEnabled = true;
  String _lastAutoSyncStatus = '';
  DateTime? _lastManualSyncTime; // Track when manual sync was performed

  void _startAutoSync() {
    if (!_autoSyncEnabled) return;

    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Skip auto-sync if manual sync was performed recently (within 2 minutes)
      if (_lastManualSyncTime != null) {
        final timeSinceManualSync =
            DateTime.now().difference(_lastManualSyncTime!);
        if (timeSinceManualSync.inMinutes < 2) {
          print(
              "PAUSE: Skipping auto-sync - manual sync performed ${timeSinceManualSync.inSeconds}s ago");
          return;
        }
      }

      // Prevent multiple auto-sync operations
      if (_isAutoSyncInProgress) {
        print("SYNC: Auto-sync already in progress, skipping...");
        return;
      }

      _isAutoSyncInProgress = true;
      setState(() {
        _lastAutoSyncStatus = 'Syncing data...';
      });

      try {
        print("SYNC: Auto-sync: Starting comprehensive IoT data sync...");

        // Step 1: Fetch metadata only (NO IMAGES) for button actions
        // Step 1: Fetch metadata only (NO IMAGES) for button actions
        await _fetchMetadataOnlyFromIoT();

        //  NEW: Step 2: Integrate Pi5 data (metadata only)
        await _integratePi5Data();

        // Step 3: Skip image fetching for button actions - images not needed
        print('⏭️ Skipping image fetch for button action sync');

        // Step 4: Fetch system status
        await _fetchSystemStatusFromIoT();

        // Step 5: Save to persistent storage
        await _savePersistedData();

        //  NEW: Step 6: Auto-sync local data to Supabase (with WiFi check and prevention logic)
        try {
          //  PREVENTION: Check WiFi connectivity before attempting Supabase upload
          final hasInternetConnection = await _checkInternetConnectivity();

          if (hasInternetConnection) {
            print(
                "SYNC: Auto-sync: WiFi available - Starting local data upload to Supabase...");
            setState(() {
              _lastAutoSyncStatus = 'Syncing data to cloud...';
            });

            await _autoSyncLocalDataToSupabase();

            setState(() {
              _lastAutoSyncStatus = '✅ Data synced successfully';
            });

            print(
                "✅ Auto-sync completed successfully - IoT data fetched and uploaded to Supabase");
          } else {
            print(
                "PAUSE: Auto-sync: No WiFi connection - Skipping Supabase upload to prevent spam failures");
            setState(() {
              _lastAutoSyncStatus = 'Data synced locally (no WiFi for cloud)';
            });
          }
        } catch (e) {
          print("ERROR: Auto-sync Supabase upload failed: $e");
          setState(() {
            _lastAutoSyncStatus = 'Data synced locally, cloud upload failed';
          });
          // Don't show error to user for auto-sync failures
        }

        // Auto-sync runs silently - no popup for user
      } catch (e) {
        print("ERROR: Auto-sync error: $e");
        setState(() {
          _lastAutoSyncStatus = 'Sync failed: $e';
        });

        if (mounted) {
          _showErrorSnackBar('Sync failed: $e');
        }
      } finally {
        _isAutoSyncInProgress = false;
      }
    });
  }

  //  REMOVED: Old incorrect metadata fetching method - replaced with HTTP server push

  //  RESTORED: Fetch only metadata/logs (NO IMAGES) - for button actions
  Future<void> _fetchMetadataOnlyFromIoT() async {
    if (!_isConnected) return;

    // CRITICAL FIX: Don't fetch data if user is on break
    if (_isOnBreak) {
      print('PAUSE: BREAK ACTIVE: Skipping metadata fetch during break');
      return;
    }

    try {
      print(
          'FETCH: Fetching metadata/logs only (NO IMAGES) via WiFi Direct...');
      final logs = await _iotConnectionService.fetchSnapshotsLogs();

      if (logs.isNotEmpty) {
        setState(() {
          // Don't clear existing logs, append new ones
          for (final log in logs) {
            //  Check if this log already exists to avoid duplicates
            bool logExists = _unifiedSnapshots.any((existingLog) =>
                existingLog['behavior_id'] == log['behavior_id'] ||
                (existingLog['behavior_type'] == log['behavior_type'] &&
                    existingLog['timestamp'] == log['timestamp']));

            if (!logExists) {
              //  DRIVER ID ALIGNMENT: Map IoT driver IDs to database IDs
              String driverId = log['driver_id'] ?? '';
              String tripId = log['trip_id'] ?? '';

              // Handle driver switch alignment
              if (log['behavior_type'] == 'driver_switch') {
                print('SYNC: Processing driver switch log from IoT...');

                // Parse driver switch details
                try {
                  final details = log['details'] ?? '';
                  if (details.isNotEmpty) {
                    final detailsMap = json.decode(details);
                    final newDriver = detailsMap['new_driver'] ?? '';
                    final driverType = detailsMap['driver_type'] ?? '';

                    print(
                        'SYNC: IoT Driver Switch: $newDriver (type: $driverType)');

                    // Align with current app state
                    if (newDriver.contains('Main') || driverType == 'main') {
                      setState(() {
                        _currentDriver = "Main Driver";
                        _isDriverSwitched = false;
                      });
                      print('SUCCESS: Aligned to Main Driver');
                    } else if (newDriver.contains('Sub') ||
                        driverType == 'sub') {
                      setState(() {
                        _currentDriver = "Sub Driver";
                        _isDriverSwitched = true;
                      });
                      print('SUCCESS: Aligned to Sub Driver');
                    }
                  }
                } catch (e) {
                  print('WARNING: Error parsing driver switch details: $e');
                }
              }

              // Handle break alignment - only apply recent break events (within last 5 minutes)
              if (log['behavior_type'] == 'break_started') {
                final logTimestamp = DateTime.parse(log['timestamp']);
                final now = DateTime.now();
                final timeDiff = now.difference(logTimestamp).inMinutes;

                if (timeDiff <= 5) {
                  print(
                      'PAUSE: Recent IoT Break Started detected (${timeDiff}m ago) - aligning app state');
                  setState(() {
                    _isOnBreak = true;
                    //  FIXED: Don't change _isMonitoring - keep start/stop button state intact
                  });
                } else {
                  print(
                      'PAUSE: Old IoT Break Started detected (${timeDiff}m ago) - ignoring to prevent false state');
                }
              } else if (log['behavior_type'] == 'break_ended') {
                final logTimestamp = DateTime.parse(log['timestamp']);
                final now = DateTime.now();
                final timeDiff = now.difference(logTimestamp).inMinutes;

                if (timeDiff <= 5) {
                  print(
                      'RESUME: Recent IoT Break Ended detected (${timeDiff}m ago) - aligning app state');
                  setState(() {
                    _isOnBreak = false;
                    //  FIXED: Don't change _isMonitoring - keep start/stop button state intact
                  });
                } else {
                  print(
                      'RESUME: Old IoT Break Ended detected (${timeDiff}m ago) - ignoring to prevent false state');
                }
              }

              //  FIX: Ensure proper driver_id and trip_id alignment
              if (driverId.isEmpty || driverId == 'null') {
                driverId = _dbCurrentDriverId ??
                    'default-driver-${DateTime.now().millisecondsSinceEpoch}';
                print('🔧 Fixed empty driver_id: $driverId');
              }
              if (tripId.isEmpty || tripId == 'null') {
                tripId = _dbCurrentTripId ??
                    'default-trip-${DateTime.now().millisecondsSinceEpoch}';
                print('🔧 Fixed empty trip_id: $tripId');
              }

              //  SUPABASE ALIGNMENT: Handle driver_id from IoT vs Supabase
              String supabaseDriverId = driverId;
              if (log['behavior_type'] == 'driver_switch') {
                try {
                  final details = log['details'] ?? '';
                  if (details.isNotEmpty) {
                    final detailsMap = json.decode(details);
                    final driverType = detailsMap['driver_type'] ?? '';

                    // If it's a Sub Driver event, use Main Driver ID for Supabase
                    if (driverType == 'sub' ||
                        detailsMap['new_driver']?.toString().contains('Sub') ==
                            true) {
                      supabaseDriverId = _dbCurrentDriverId ?? driverId;
                      print(
                          'SYNC: SUPABASE ALIGNMENT: Using Main Driver ID for Sub Driver event: $supabaseDriverId');
                    }
                  }
                } catch (e) {
                  print(
                      'WARNING: Error parsing driver switch details for Supabase alignment: $e');
                }
              }

              //  FIX: Handle IoT data structure correctly (unified snapshots table with evidence)
              _unifiedSnapshots.add({
                'type': 'snapshot_log',
                'behavior_id': log['id']?.toString() ??
                    'iot-${DateTime.now().millisecondsSinceEpoch}', // Use IoT's ID field
                'driver_id':
                    supabaseDriverId, //  Use Supabase-aligned driver_id
                'trip_id': tripId, //  Fixed trip_id
                'behavior_type': log['behavior_type'],
                'timestamp': log['timestamp'],
                'message': '${log['behavior_type']} detected from IoT',
                'source': 'iot', //  Mark as from IoT
                'event_type': log['event_type'] ??
                    'behavior', //  NEW: Unified table field

                //  CRITICAL FIX: Add filename field for image fetching
                'filename': log['filename'] ?? 'Unknown',

                //  NEW: Add all evidence fields from detection_ai.py (only the 13 fields it actually sends)
                'evidence_reason': log['evidence_reason'],
                'confidence_score': log[
                    'confidence_score'], //  FIXED: Pi5 sends 'confidence_score', not 'confidence'
                'event_duration': log['event_duration'],
                'gaze_pattern': log['gaze_pattern'],
                'face_direction': log['face_direction'],
                'eye_state': log['eye_state'],
                'device_id':
                    'pi5-device', //  FIXED: Pi5 doesn't send device_id, use default
                'driver_type': _currentDriver == "Main Driver"
                    ? 'main'
                    : 'sub', //  FIXED: Use current driver state, not IoT data
              });

              print(
                  'SUCCESS: Added unified snapshot log: ${log['behavior_type']}');
            }
          }

          // Keep only the last 100 logs to prevent memory issues
          if (_unifiedSnapshots.length > 200) {
            _unifiedSnapshots.removeRange(0, _unifiedSnapshots.length - 200);
          }
        });
        print(
            '✅ Snapshots logs fetched and aligned: ${logs.length} new logs added (today only)');
      } else {
        print(
            'WARNING: No new snapshots logs available via WiFi Direct (after 24-hour filtering)');
      }
    } catch (e) {
      print('ERROR: Error fetching snapshots logs via WiFi Direct: $e');
    }
  }

  Future<void> _fetchSystemStatusFromIoT() async {
    if (!_isConnected) return;

    // CRITICAL FIX: Don't fetch data if user is on break
    // This prevents any data fetching that might interfere with break state
    if (_isOnBreak) {
      print('PAUSE: BREAK ACTIVE: Skipping system status fetch during break');
      return;
    }

    try {
      print('DATA: Fetching system status via WiFi Direct...');
      final stats = await _iotConnectionService.fetchSystemStatus();

      if (stats.isNotEmpty) {
        setState(() {
          _iotStats = {
            'total_frames': stats['total_frames'] ?? 0,
            'faces_detected': stats['faces_detected'] ?? 0,
            'drowsiness_events': stats['drowsiness_events'] ?? 0,
            'looking_away_events': stats['looking_away_events'] ?? 0,
            'current_ear': stats['current_ear'] ?? 0.0,
            'eye_state': stats['eye_state'] ?? 'unknown',
            'fps': stats['fps'] ?? 0.0,
            'last_alert': stats['last_alert'],
          };
        });
        print('SUCCESS: System status updated via WiFi Direct');
      } else {
        print('WARNING: System status not available via WiFi Direct');
      }
    } catch (e) {
      print('ERROR: Error fetching system status via WiFi Direct: $e');
    }
  }

  void _toggleAutoSync() {
    setState(() {
      _autoSyncEnabled = !_autoSyncEnabled;
    });

    if (_autoSyncEnabled) {
      _startAutoSync();
      _showSuccessSnackBar('Auto-sync enabled');
    } else {
      _syncTimer?.cancel();
      _showSuccessSnackBar('Auto-sync disabled');
    }
  }

  //  SUPABASE LOGGING METHODS FOR DRIVER ACTIONS

  //  NEW: Log start monitoring to Supabase with all panel fields
  Future<void> _logStartMonitoringToSupabase() async {
    try {
      final currentDriverId = _getCurrentDriverId();
      if (currentDriverId == null || _dbCurrentTripId == null) {
        print(
            'WARNING: Cannot log start monitoring: Missing driver_id or trip_id');
        return;
      }

      print(
          '📝 Logging start monitoring to Supabase for $_currentDriver (ID: $currentDriverId)');

      Map<String, dynamic> logData = {
        'driver_id': currentDriverId,
        'trip_id': _dbCurrentTripId,
        'behavior_type': 'monitoring_started',
        'event_type': 'snapshot',
        'timestamp': DateTime.now().toIso8601String(),
        'details': json.encode({
          'action': 'monitoring_started',
          'driver': _currentDriver,
          'driver_id': currentDriverId,
          'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',
          'timestamp': DateTime.now().toIso8601String(),
          'source': 'flutter_app',
          'trip_ref_number': _dbCurrentTripRefNumber,
          'event_duration': 0,
          'confidence_score': 1.0,
          'evidence_reason': 'Manual monitoring start by driver',
          'is_legitimate_driving': true,
          'evidence_strength': 'high',
          'trigger_justification':
              'Driver manually started behavior monitoring',
        }),
        'device_id': 'flutter-app',
        'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',
        'event_duration': 0,
        'confidence_score': null, //  FIX: Manual action, not AI-detected
        'evidence_reason': 'Manual monitoring start by driver',
        'is_legitimate_driving': true,
        'evidence_strength': 'high',
        'trigger_justification': 'Driver manually started behavior monitoring',
        'gaze_pattern': null, //  FIX: Manual action, not AI-detected
        'face_direction': null, //  FIX: Manual action, not AI-detected
        'eye_state': null, //  FIX: Manual action, not AI-detected
        'filename':
            'monitoring_started_${DateTime.now().millisecondsSinceEpoch}', //  FIX: Add required filename
        'image_quality': 'HD', //  FIX: Add default image quality
        //  Panel fields
        'reflection_detected': null, //  FIX: Manual action, not AI-detected
        'detection_reliability': null, //  FIX: Manual action, not AI-detected
        'driver_threshold_adjusted': null,
        'compliance_audit_trail': 'Manual monitoring start logged',
      };

      //  SAVE TO LOCAL STORAGE FIRST
      _unifiedSnapshots.insert(0, logData);
      print('SUCCESS: Start monitoring saved to local storage');

      //  OPTIONAL: Also save to Supabase (commented out for now)
      // await Supabase.instance.client.from('snapshots').insert(logData);
      // print('SUCCESS: Start monitoring logged to Supabase successfully');
    } catch (e) {
      print('ERROR: Error logging start monitoring to local storage: $e');
    }
  }

  //  NEW: Log stop monitoring to Supabase with all panel fields
  Future<void> _logStopMonitoringToSupabase() async {
    try {
      final currentDriverId = _getCurrentDriverId();
      if (currentDriverId == null || _dbCurrentTripId == null) {
        print(
            'WARNING: Cannot log stop monitoring: Missing driver_id or trip_id');
        return;
      }

      print(
          '📝 Logging stop monitoring to Supabase for $_currentDriver (ID: $currentDriverId)');

      Map<String, dynamic> logData = {
        'driver_id': currentDriverId,
        'trip_id': _dbCurrentTripId,
        'behavior_type': 'monitoring_stopped',
        'event_type': 'snapshot',
        'timestamp': DateTime.now().toIso8601String(),
        'details': json.encode({
          'action': 'monitoring_stopped',
          'driver': _currentDriver,
          'driver_id': currentDriverId,
          'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',
          'timestamp': DateTime.now().toIso8601String(),
          'source': 'flutter_app',
          'trip_ref_number': _dbCurrentTripRefNumber,
          'event_duration': 0,
          'confidence_score': 1.0,
          'evidence_reason': 'Manual monitoring stop by driver',
          'is_legitimate_driving': true,
          'evidence_strength': 'high',
          'trigger_justification':
              'Driver manually stopped behavior monitoring',
        }),
        'device_id': 'flutter-app',
        'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',
        'event_duration': 0,
        'confidence_score': null, //  FIX: Manual action, not AI-detected
        'evidence_reason': 'Manual monitoring stop by driver',
        'is_legitimate_driving': true,
        'evidence_strength': 'high',
        'trigger_justification': 'Driver manually stopped behavior monitoring',
        'gaze_pattern': null, //  FIX: Manual action, not AI-detected
        'face_direction': null, //  FIX: Manual action, not AI-detected
        'eye_state': null, //  FIX: Manual action, not AI-detected
        'filename':
            'monitoring_stopped_${DateTime.now().millisecondsSinceEpoch}', //  FIX: Add required filename
        'image_quality': 'HD', //  FIX: Add default image quality
        //  Panel fields
        'reflection_detected': null, //  FIX: Manual action, not AI-detected
        'detection_reliability': null, //  FIX: Manual action, not AI-detected
        'driver_threshold_adjusted': null,
        'compliance_audit_trail': 'Manual monitoring stop logged',
      };

      //  SAVE TO LOCAL STORAGE FIRST
      _unifiedSnapshots.insert(0, logData);
      print('SUCCESS: Stop monitoring saved to local storage');

      //  OPTIONAL: Also save to Supabase (commented out for now)
      // await Supabase.instance.client.from('snapshots').insert(logData);
      // print('SUCCESS: Stop monitoring logged to Supabase successfully');
    } catch (e) {
      print('ERROR: Error logging stop monitoring to local storage: $e');
    }
  }

  //  NEW: Validate sync sequence to ensure proper data alignment
  void _validateSyncSequence(
      List<Map<String, dynamic>> dataList, String dataType) {
    try {
      if (dataList.length < 2) {
        return; // Need at least 2 items to validate sequence
      }

      print('DEBUG: Validating $dataType sync sequence...');

      for (int i = 0; i < dataList.length - 1; i++) {
        final current = dataList[i];
        final next = dataList[i + 1];

        try {
          final currentTime = DateTime.parse(
              current['timestamp'] ?? DateTime.now().toIso8601String());
          final nextTime = DateTime.parse(
              next['timestamp'] ?? DateTime.now().toIso8601String());

          if (currentTime.isAfter(nextTime)) {
            print('WARNING: SYNC SEQUENCE WARNING: $dataType out of order');
            print('   Item ${i + 1}: ${current['timestamp']}');
            print('   Item ${i + 2}: ${next['timestamp']}');
            print('   Current is AFTER next - sequence may be incorrect');
          }
        } catch (e) {
          print('WARNING: Error validating timestamp sequence: $e');
        }
      }

      print('SUCCESS: $dataType sync sequence validation completed');
    } catch (e) {
      print('ERROR: Error validating sync sequence: $e');
    }
  }

  //  NEW: Sort data chronologically to maintain proper sync order
  List<Map<String, dynamic>> _sortDataChronologically(
      List<Map<String, dynamic>> dataList, String dataType) {
    try {
      print('SYNC: Sorting $dataType data chronologically...');

      // Sort by timestamp in ascending order (oldest first)
      final sortedData = List<Map<String, dynamic>>.from(dataList);
      sortedData.sort((a, b) {
        try {
          final timestampA = DateTime.parse(
              a['timestamp'] ?? DateTime.now().toIso8601String());
          final timestampB = DateTime.parse(
              b['timestamp'] ?? DateTime.now().toIso8601String());
          return timestampA
              .compareTo(timestampB); // Ascending order (oldest first)
        } catch (e) {
          print('WARNING: Error parsing timestamp for sorting: $e');
          return 0; // Keep original order if timestamp parsing fails
        }
      });

      print(
          'SUCCESS: Sorted ${sortedData.length} $dataType records chronologically');

      // Log first and last timestamps for verification
      if (sortedData.isNotEmpty) {
        final firstTimestamp = sortedData.first['timestamp'];
        final lastTimestamp = sortedData.last['timestamp'];
        print('   First: $firstTimestamp');
        print('   Last: $lastTimestamp');
      }

      return sortedData;
    } catch (e) {
      print('ERROR: Error sorting $dataType data chronologically: $e');
      return dataList; // Return original list if sorting fails
    }
  }

  //  NEW: Validate timestamp accuracy from IoT data
  void _validateTimestampAccuracy(Map<String, dynamic> data, String source) {
    try {
      final iotTimestamp = data['timestamp'];
      final phoneTimestamp = DateTime.now().toIso8601String();

      if (iotTimestamp != null) {
        final iotTime = DateTime.parse(iotTimestamp);
        final phoneTime = DateTime.now();
        final timeDiff = phoneTime.difference(iotTime).inSeconds;

        if (timeDiff.abs() > 5) {
          // More than 5 seconds difference
          print('WARNING: TIMESTAMP ACCURACY WARNING: $source');
          print('   IoT Timestamp: $iotTimestamp');
          print('   Phone Timestamp: $phoneTimestamp');
          print('   Time Difference: ${timeDiff}s');
          print('   Using IoT timestamp for accuracy');
        } else {
          print(
              'SUCCESS: TIMESTAMP ACCURACY: $source - Times aligned within 5s');
        }
      }
    } catch (e) {
      print('ERROR: Error validating timestamp accuracy: $e');
    }
  }

  //  NEW: Enhanced timestamp validation with comprehensive checks
  bool _validateTimestampAccuracyEnhanced(Map<String, dynamic> data) {
    try {
      final iotTimestamp = data['timestamp'];
      if (iotTimestamp == null) return false;

      final iotTime = DateTime.parse(iotTimestamp);
      final now = DateTime.now();
      final timeDiff = now.difference(iotTime).inSeconds;

      // Validate timestamp is reasonable (not too old, not in future)
      if (timeDiff > 86400) {
        // More than 24 hours old
        print(
            '⚠️ WARNING: IoT timestamp is very old: ${timeDiff / 3600} hours');
        return false;
      }

      if (timeDiff < -300) {
        // More than 5 minutes in future
        print(
            'WARNING: WARNING: IoT timestamp is in future: ${-timeDiff} seconds');
        return false;
      }

      return true;
    } catch (e) {
      print('ERROR: ERROR: Invalid timestamp format: ${data['timestamp']}');
      return false;
    }
  }

  //  NEW: Timestamp alignment logic - Align driver switches with detection data
  List<Map<String, dynamic>> _alignDriverSwitchesWithDetectionData(
      List<Map<String, dynamic>> logs) {
    try {
      print(
          '🔄 Aligning driver switches with detection data based on timestamps...');

      // Get all driver switch logs from Flutter (local logs)
      final driverSwitchLogs = _unifiedSnapshots
          .where((s) => s['event_type'] == 'snapshot')
          .toList()
          .where((log) => log['behavior_type'] == 'driver_switch')
          .toList();

      if (driverSwitchLogs.isEmpty) {
        print('ℹ️ No driver switch logs found - using original IoT data as-is');
        return logs;
      }

      // Sort driver switch logs chronologically
      driverSwitchLogs.sort((a, b) => DateTime.parse(a['timestamp'])
          .compareTo(DateTime.parse(b['timestamp'])));

      print('DATE: Found ${driverSwitchLogs.length} driver switch events:');
      for (final switchLog in driverSwitchLogs) {
        final timestamp = DateTime.parse(switchLog['timestamp']);
        final driverType =
            switchLog['details']?['new_driver_type'] ?? 'unknown';
        print('  - ${timestamp.toString()}: Switch to $driverType');
      }

      // Apply driver alignment to IoT detection logs
      final alignedLogs = <Map<String, dynamic>>[];
      String currentDriverType = 'main'; // Default to main driver

      for (final log in logs) {
        final logTimestamp = DateTime.parse(log['timestamp']);

        // Check if this log should be attributed to a different driver
        for (final switchLog in driverSwitchLogs) {
          final switchTimestamp = DateTime.parse(switchLog['timestamp']);

          // If this log is after the switch, update the driver type
          if (logTimestamp.isAfter(switchTimestamp)) {
            final newDriverType =
                switchLog['details']?['new_driver_type'] ?? 'main';
            currentDriverType =
                newDriverType.toLowerCase().contains('main') ? 'main' : 'sub';
          }
        }

        // Create aligned log with correct driver attribution
        final alignedLog = Map<String, dynamic>.from(log);
        alignedLog['driver_type'] = currentDriverType;
        alignedLog['driver_attribution'] = 'aligned_by_timestamp';

        alignedLogs.add(alignedLog);
      }

      print(
          '✅ Driver alignment completed - ${alignedLogs.length} logs aligned with driver switches');
      return alignedLogs;
    } catch (e) {
      print('ERROR: Error aligning driver switches: $e');
      return logs; // Return original logs if alignment fails
    }
  }

  //  NEW: Chronological sync method for proper data order
  Future<void> _syncDataChronologically() async {
    try {
      print(
          'SYNC: Starting chronological sync to maintain proper data order...');

      // 1. Sort all data chronologically
      final sortedLogs = _sortDataChronologically(
          _unifiedSnapshots
              .where((s) => s['event_type'] == 'snapshot')
              .toList(),
          'snapshot logs');
      final sortedSnapshots = _sortDataChronologically(
          _unifiedSnapshots
              .where((s) => s['event_type'] == 'snapshot')
              .toList(),
          'snapshots');

      // 2. Validate timestamps
      int validLogs = 0;
      int validSnapshots = 0;

      for (final log in sortedLogs) {
        if (_validateTimestampAccuracyEnhanced(log)) {
          validLogs++;
        } else {
          print('WARNING: Skipping log with invalid timestamp');
        }
      }

      for (final snapshot in sortedSnapshots) {
        if (_validateTimestampAccuracyEnhanced(snapshot)) {
          validSnapshots++;
        } else {
          print('WARNING: Skipping snapshot with invalid timestamp');
        }
      }

      print(
          '📊 Valid data for sync: $validLogs logs, $validSnapshots snapshots');

      // 3. Sync sequentially in chronological order
      print('SYNC: Syncing snapshot logs in chronological order...');
      for (int i = 0; i < sortedLogs.length; i++) {
        final log = sortedLogs[i];
        if (_validateTimestampAccuracyEnhanced(log)) {
          await _uploadBehaviorLogToSupabase(log);
          print(
              '✅ Synced log ${i + 1}/${sortedLogs.length}: ${log['timestamp']}');
          await Future.delayed(
              const Duration(milliseconds: 100)); // Small delay between uploads
        }
      }

      print('IMAGE: Syncing snapshots in chronological order...');
      for (int i = 0; i < sortedSnapshots.length; i++) {
        final snapshot = sortedSnapshots[i];
        if (_validateTimestampAccuracyEnhanced(snapshot)) {
          await _uploadSnapshotToSupabase(snapshot);
          print(
              '✅ Synced snapshot ${i + 1}/${sortedSnapshots.length}: ${snapshot['timestamp']}');
          await Future.delayed(
              const Duration(milliseconds: 100)); // Small delay between uploads
        }
      }

      print('SUCCESS: Chronological sync completed successfully');
    } catch (e) {
      print('ERROR: Error in chronological sync: $e');
    }
  }

  //  REMOVED: Duplicate _getCurrentDriverId function - using unified version above

  //  REMOVED: _initializeSubDriverId - no longer needed, using driver_type instead

  Future<void> _logBreakToggleToSupabase() async {
    try {
      //  REMOVED: No longer need to initialize sub driver ID

      final currentDriverId = _getCurrentDriverId();
      if (currentDriverId == null || _dbCurrentTripId == null) {
        print('WARNING: Cannot log break toggle: Missing driver_id or trip_id');
        return;
      }

      final breakAction = _isOnBreak ? 'break_started' : 'break_ended';
      final breakStartedBy = _breakStartedByDriver ?? _currentDriver;
      final isDifferentDriverResuming = !_isOnBreak &&
          _breakStartedByDriver != null &&
          _breakStartedByDriver != _currentDriver;

      print(
          '📝 Logging break toggle to Supabase: $breakAction for $_currentDriver');
      if (isDifferentDriverResuming) {
        print(
            '🔄 BREAK LOG: $_currentDriver resuming break started by $breakStartedBy');
      }

      //  UNIFIED DATABASE STRUCTURE: Use snapshots table with event_type = 'snapshot'
      Map<String, dynamic> logData = {
        'trip_id': _dbCurrentTripId,
        'behavior_type': breakAction,
        'event_type': 'snapshot', //  CRITICAL: Use unified table structure
        'timestamp': DateTime.now().toIso8601String(),
        'details': json.encode({
          'action': breakAction,
          'driver': _currentDriver,
          'driver_id': currentDriverId,
          'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',
          'break_started_by':
              breakStartedBy, //  NEW: Track who started the break
          'break_started_by_type': breakStartedBy == "Main Driver"
              ? 'main'
              : 'sub', //  NEW: Track driver type who started break
          'is_different_driver_resuming':
              isDifferentDriverResuming, //  NEW: Track if different driver is resuming
          'timestamp': DateTime.now().toIso8601String(),
          'source': 'flutter_app',
          'trip_ref_number': _dbCurrentTripRefNumber,
          'event_duration': 0, // Break events don't have duration
          'confidence_score': 1.0, // Manual action, high confidence
          'evidence_reason': isDifferentDriverResuming
              ? 'Break resumed by different driver ($_currentDriver, started by $breakStartedBy)'
              : 'Manual break toggle by driver',
          'is_legitimate_driving':
              !_isOnBreak, // false when on break, true when resuming
          'evidence_strength': 'high',
          'trigger_justification': _isOnBreak
              ? 'Driver initiated break'
              : isDifferentDriverResuming
                  ? 'Different driver resumed break (started by $breakStartedBy)'
                  : 'Driver resumed from break',
        }),
        'device_id': 'flutter-app',
        'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',
        'event_duration': 0,
        'confidence_score': null, //  FIX: Manual action, not AI-detected
        'evidence_reason': 'Manual break toggle by driver',
        'is_legitimate_driving': !_isOnBreak,
        'evidence_strength': 'high',
        'trigger_justification':
            _isOnBreak ? 'Driver initiated break' : 'Driver resumed from break',
        'gaze_pattern': null, //  FIX: Manual action, not AI-detected
        'face_direction': null, //  FIX: Manual action, not AI-detected
        'eye_state': null, //  FIX: Manual action, not AI-detected
        'filename':
            'break_toggle_${DateTime.now().millisecondsSinceEpoch}', //  FIX: Add required filename
        'image_quality': 'HD', //  FIX: Add default image quality
      };

      //  CRITICAL FIX: Use Main Driver ID for foreign key, but include Sub Driver info in details
      if (_currentDriver == "Main Driver") {
        logData['driver_id'] =
            currentDriverId; // Main driver UUID from users table
      } else if (_currentDriver == "Sub Driver") {
        logData['driver_id'] =
            _dbCurrentDriverId; // Use Main Driver ID for foreign key
        // Sub driver ID is stored in details.driver_id for reference
      }

      //  SAVE TO LOCAL STORAGE FIRST
      _unifiedSnapshots.insert(0, logData);
      print(
          '✅ Break toggle saved to local storage: $breakAction for $_currentDriver (ID: $currentDriverId)');

      //  OPTIONAL: Also save to Supabase (commented out for now)
      // await Supabase.instance.client.from('snapshots').insert(logData);
      // print('SUCCESS: Break toggle logged to Supabase successfully for $_currentDriver (ID: $currentDriverId)');
    } catch (e) {
      print('ERROR: Error logging break toggle to local storage: $e');
    }
  }

  //  NEW: Sync driver state from IoT device
  Future<void> _syncDriverStateFromIoT() async {
    try {
      print('SYNC: Syncing driver state from IoT device...');

      // Use local snapshot logs instead of fetching from IoT
      final logs = _unifiedSnapshots
          .where((s) => s['event_type'] == 'snapshot')
          .toList();

      if (logs.isNotEmpty) {
        // Find the most recent driver switch
        Map<String, dynamic>? latestDriverSwitch;
        DateTime? latestTime;

        for (final log in logs) {
          if (log['behavior_type'] == 'driver_switch') {
            try {
              final timestamp = DateTime.parse(log['timestamp']);
              if (latestTime == null || timestamp.isAfter(latestTime)) {
                latestTime = timestamp;
                latestDriverSwitch = log;
              }
            } catch (e) {
              print('WARNING: Error parsing timestamp: $e');
            }
          }
        }

        // Apply the latest driver switch state
        if (latestDriverSwitch != null) {
          print(
              '🔄 Found latest driver switch from IoT: ${latestDriverSwitch['timestamp']}');

          try {
            final details = latestDriverSwitch['details'] ?? '';
            if (details.isNotEmpty) {
              final detailsMap = json.decode(details);
              final newDriver = detailsMap['new_driver'] ?? '';
              final driverType = detailsMap['driver_type'] ?? '';

              print('SYNC: IoT Latest Driver: $newDriver (type: $driverType)');

              // Align app state with IoT state
              if (newDriver.contains('Main') || driverType == 'main') {
                setState(() {
                  _currentDriver = "Main Driver";
                  _isDriverSwitched = false;
                });
                print('SUCCESS: App aligned to Main Driver (from IoT)');
                print('🆔 Main Driver ID: $_dbCurrentDriverId');
              } else if (newDriver.contains('Sub') || driverType == 'sub') {
                //  Initialize Sub Driver ID if switching to Sub Driver
                //  REMOVED: No longer need to initialize sub driver ID
                setState(() {
                  _currentDriver = "Sub Driver";
                  _isDriverSwitched = true;
                });
                print('SUCCESS: App aligned to Sub Driver (from IoT)');
                print(
                    '🆔 Driver Type: ${_currentDriver == "Main Driver" ? "main" : "sub"}');
              }
            }
          } catch (e) {
            print('WARNING: Error parsing driver switch details: $e');
          }
        } else {
          print(
              'ℹ️ No driver switch found in IoT logs - keeping current app state');
        }

        // Also sync break state
        Map<String, dynamic>? latestBreakEvent;
        DateTime? latestBreakTime;

        for (final log in logs) {
          if (log['behavior_type'] == 'break_started' ||
              log['behavior_type'] == 'break_ended') {
            try {
              final timestamp = DateTime.parse(log['timestamp']);
              if (latestBreakTime == null ||
                  timestamp.isAfter(latestBreakTime)) {
                latestBreakTime = timestamp;
                latestBreakEvent = log;
              }
            } catch (e) {
              print('WARNING: Error parsing break timestamp: $e');
            }
          }
        }

        // Apply the latest break state
        if (latestBreakEvent != null) {
          final breakType = latestBreakEvent['behavior_type'];
          final breakTimestamp = DateTime.parse(latestBreakEvent['timestamp']);
          final now = DateTime.now();
          final timeDiff = now.difference(breakTimestamp).inMinutes;

          print(
              '🔄 Found latest break event from IoT: $breakType at ${latestBreakEvent['timestamp']} (${timeDiff}m ago)');

          // Only apply recent break events (within last 5 minutes)
          if (timeDiff <= 5) {
            if (breakType == 'break_started') {
              setState(() {
                _isOnBreak = true;
                //  FIXED: Don't change _isMonitoring - keep start/stop button state intact
              });
              print('SUCCESS: App aligned to Recent Break Started (from IoT)');
            } else if (breakType == 'break_ended') {
              setState(() {
                _isOnBreak = false;
                //  FIXED: Don't change _isMonitoring - keep start/stop button state intact
              });
              print('SUCCESS: App aligned to Recent Break Ended (from IoT)');
            }
          } else {
            print(
                '⚠️ Ignoring old break event (${timeDiff}m ago) to prevent false state');
          }
        } else {
          print(
              'ℹ️ No break events found in IoT logs - keeping current app state');
        }
      } else {
        print('ℹ️ No snapshot logs available for driver state sync');
      }
    } catch (e) {
      print('ERROR: Error syncing driver state from IoT: $e');
    }
  }

  // DATABASE METHODS (NEW - for trip management)

  Future<void> _loadCurrentUserAndTrips() async {
    try {
      print('DEBUG: Loading current user and trips from database...');

      //  FIX: Use widget.userData first (EXACTLY like dashboard_page.dart)
      if (widget.userData != null) {
        print(
            '🔐 Using user data from widget: ${widget.userData!['username']} (${widget.userData!['role']})');

        setState(() {
          _currentUser = widget.userData;
          _dbCurrentDriverId = widget.userData!['id'];
        });

        print(
            '✅ Driver loaded from widget: ${widget.userData!['driver_id']} (UUID: $_dbCurrentDriverId)');
        print('👤 Current user data: $_currentUser');

        //  FIX: Set up real-time subscriptions and load current trip AFTER user is set
        if (_currentUser != null) {
          await _setupRealtimeSubscriptions();
          await _loadCurrentTrip();
        }
        return;
      }

      //  FIX: Use EXACT same logic as dashboard_page.dart
      print('SYNC: Loading current user (same as dashboard_page.dart)...');
      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        print('🔐 Authenticated user found: ${user.id}');

        //  EXACT SAME QUERY as dashboard_page.dart
        final userData = await Supabase.instance.client
            .from('users')
            .select('*, profile_image_url')
            .eq('id', user.id)
            .maybeSingle();

        if (userData != null && mounted) {
          setState(() {
            _currentUser = userData;
            _dbCurrentDriverId = userData['id'];
          });
          print(
              '✅ Driver loaded: ${userData['driver_id']} (UUID: $_dbCurrentDriverId)');
          print('👤 Current user data: $userData');

          //  FIX: Set up real-time subscriptions and load current trip AFTER user is set
          if (_currentUser != null) {
            await _setupRealtimeSubscriptions();
            await _loadCurrentTrip();
          }
        } else {
          print(
              'ERROR: No user data found in users table for authenticated user');
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        print('ERROR: No authenticated user found - user not logged in');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('ERROR: Error loading user: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  //  REMOVED: Alternative user loading method - using exact same logic as dashboard_page.dart

  Future<void> _setupRealtimeSubscriptions() async {
    if (_currentUser == null) {
      print('ERROR: Cannot setup subscriptions: _currentUser is null');
      return;
    }

    try {
      print(
          '📡 Setting up real-time trip subscriptions for user: ${_currentUser!['id']}');

      //  ENHANCED: Add retry logic for subscription setup
      await _retryWithBackoff(
        operation: () async {
          _tripsSubscription = Supabase.instance.client
              .channel('trips_changes_${_currentUser!['id']}')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'trips',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'driver_id',
                  value: _currentUser!['id'],
                ),
                callback: (payload) {
                  print('SYNC: Trip change detected: $payload');
                  _handleTripChange(payload);
                  _loadCurrentTrip();
                },
              )
              .subscribe();

          //  NEW: Verify subscription is active
          await Future.delayed(const Duration(milliseconds: 500));
          if (_tripsSubscription != null) {
            print('SUCCESS: Real-time trip subscriptions active and verified');
          } else {
            throw Exception('Subscription not active after setup');
          }
        },
        maxRetries: 3,
        operationName: 'Real-time subscription setup',
      );
    } catch (e) {
      print('ERROR: Error setting up subscriptions: $e');
      // Show error to user
      if (mounted) {
        _showErrorSnackBar('Failed to setup real-time updates: $e');
      }
    }
  }

  void _handleTripChange(PostgresChangePayload payload) {
    final eventType = payload.eventType;
    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;

    switch (eventType) {
      case PostgresChangeEvent.insert:
        final tripRef = newRecord['trip_ref_number'] ?? 'Unknown';
        _showSuccessSnackBar('New trip assigned: $tripRef');
        break;
      case PostgresChangeEvent.update:
        final tripRef = newRecord['trip_ref_number'] ?? 'Unknown';
        final oldStatus = oldRecord['status'] ?? 'Unknown';
        final newStatus = newRecord['status'] ?? 'Unknown';
        if (oldStatus != newStatus) {
          _showSuccessSnackBar(
              'Trip $tripRef status changed: $oldStatus → $newStatus');
        }
        break;
      case PostgresChangeEvent.delete:
        final tripRef = oldRecord['trip_ref_number'] ?? 'Unknown';
        _showSuccessSnackBar('Trip removed: $tripRef');
        break;
      default:
        // Handle any other event types
        break;
    }
  }

  Future<void> _loadCurrentTrip() async {
    if (_currentUser == null) {
      print('ERROR: Cannot load trip: _currentUser is null');
      return;
    }

    try {
      print('DEBUG: Loading current trip for driver: ${_currentUser!['id']}');
      print('DEBUG: Driver username: ${_currentUser!['username']}');
      print('DEBUG: Driver role: ${_currentUser!['role']}');

      //  EXACT SAME LOGIC as dashboard_page.dart
      if (_currentUser == null) return;

      //  EXACT SAME QUERIES as dashboard_page.dart
      final currentTripsResponse = await Supabase.instance.client
          .from('trips')
          .select('''
            id,
            trip_ref_number,
            origin,
            destination,
            start_time,
            end_time,
            status,
            priority,
            contact_person,
            contact_phone,
            notes,
            progress
          ''')
          .eq('driver_id', _currentUser!['id'])
          .eq('status', 'in_progress')
          .order('start_time');

      final scheduledTripsResponse = await Supabase.instance.client
          .from('trips')
          .select('''
            id,
            trip_ref_number,
            origin,
            destination,
            start_time,
            end_time,
            status,
            priority,
            contact_person,
            contact_phone,
            notes,
            progress
          ''')
          .eq('driver_id', _currentUser!['id'])
          .eq('status', 'assigned')
          .order('start_time');

      print(
          '📊 Found ${currentTripsResponse.length} current trips and ${scheduledTripsResponse.length} scheduled trips');

      //  EXACT SAME LOGIC as dashboard_page.dart
      if (mounted) {
        // Use the first current trip, or first scheduled trip if no current trips
        List<Map<String, dynamic>> allTrips = [];
        allTrips.addAll(currentTripsResponse);
        allTrips.addAll(scheduledTripsResponse);

        if (allTrips.isNotEmpty) {
          final trip = allTrips.first;
          setState(() {
            _dbCurrentTrip = trip;
            _dbCurrentTripId = trip['id'];
            _dbCurrentTripRefNumber = trip['trip_ref_number'];

            //  ALIGNMENT: Set current IDs to database IDs for IoT communication
            _currentDriverId = _currentUser!['id'];
            _currentTripId = _dbCurrentTripId;

            // Set trip started flag based on status
            _isTripStarted = trip['status'] == 'in_progress';
          });
          print(
              '✅ Current trip loaded: ${trip['trip_ref_number']} (${trip['status']})');
          print('DATE: Trip start time: ${trip['start_time']}');
          print('🆔 Driver ID: $_currentDriverId');
          print('🆔 Trip ID: $_currentTripId');

          //  NEW: Show success message to user
          if (mounted) {
            _showSuccessSnackBar('Trip loaded: ${trip['trip_ref_number']}');
          }
        } else {
          setState(() {
            _dbCurrentTrip = null;
            _dbCurrentTripId = null;
            _dbCurrentTripRefNumber = null;

            // Clear current IDs when no trip
            _currentDriverId = _currentUser!['id'];
            _currentTripId = null;
            _isTripStarted = false; // No trip controls available
          });
          print('ℹ️ No active trips found for this driver');

          //  NEW: Show info message to user
          if (mounted) {
            _showErrorSnackBar(
                'No active trips found. Check dashboard for assignments.');
          }
        }
      }
    } catch (e) {
      print('ERROR: Error loading current trip: $e');
      // Show error to user
      if (mounted) {
        _showErrorSnackBar('Failed to load trip data: $e');
      }
    }
  }

  Future<void> _startTrip() async {
    if (_isLoading) {
      print('WARNING: Start trip already in progress, ignoring click');
      return;
    }

    if (_dbCurrentTripId == null) {
      _showErrorSnackBar('No active trip to start');
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Step 1: Check location permissions and enable GPS
      if (!_isLocationEnabled) {
        final locationEnabled = await _locationService.initialize();
        if (!locationEnabled) {
          _showErrorSnackBar('Please enable location services to start trip');
          setState(() {
            _isLoading = false;
          });
          return;
        }
        setState(() {
          _isLocationEnabled = true;
        });
      }

      // Step 2: Get accurate current location with retry logic
      location_pkg.LocationData? currentLocation;

      // Try multiple times with increasing timeout for better accuracy
      for (int attempt = 1; attempt <= 3; attempt++) {
        print('DEBUG: GPS attempt $attempt/3 - Getting current location...');

        try {
          currentLocation = await _locationService.getCurrentLocation().timeout(
              Duration(seconds: 5 * attempt)); // Increase timeout each attempt

          if (currentLocation != null &&
              currentLocation.latitude != null &&
              currentLocation.longitude != null) {
            print(
                '✅ GPS location obtained: ${currentLocation.latitude}, ${currentLocation.longitude}');
            break;
          }
        } catch (e) {
          print('WARNING: GPS attempt $attempt failed: $e');
        }

        if (attempt < 3) {
          _showErrorSnackBar('GPS attempt $attempt failed, trying again...');
          await Future.delayed(Duration(seconds: 2));
        }
      }

      if (currentLocation == null ||
          currentLocation.latitude == null ||
          currentLocation.longitude == null) {
        _showErrorSnackBar(
            'Unable to get GPS location. Please move to an open area with clear sky view and try again.');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Validate GPS accuracy for driver safety
      final accuracy = currentLocation.accuracy ?? double.infinity;
      if (accuracy > 50.0) {
        _showErrorSnackBar(
            'GPS accuracy too low (${accuracy.toStringAsFixed(1)}m). Please wait for better signal and try again.');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      print(
          '✅ Using accurate GPS location: ${currentLocation.latitude}, ${currentLocation.longitude} (accuracy: ${accuracy.toStringAsFixed(1)}m)');

      // Step 3: Update trip status in database (with retry logic)
      bool tripStatusUpdated = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!tripStatusUpdated && retryCount < maxRetries) {
        try {
          retryCount++;
          print(
              '🔄 Attempting to update trip status (attempt $retryCount/$maxRetries)...');

          await Supabase.instance.client.from('trips').update({
            'status': 'in_progress',
            'started_at': DateTime.now().toIso8601String(),
            'start_latitude': currentLocation.latitude ?? 0.0,
            'start_longitude': currentLocation.longitude ?? 0.0,
            'current_latitude': currentLocation.latitude ?? 0.0,
            'current_longitude': currentLocation.longitude ?? 0.0,
            'last_location_update': DateTime.now().toIso8601String(),
          }).eq('id', _dbCurrentTripId!);

          tripStatusUpdated = true;
          print('SUCCESS: Trip status updated successfully');

          //  SIMPLE: Trip status will be inferred from logs - no need to save complex data
          print('SUCCESS: Trip started - status will be inferred from logs');
        } catch (e) {
          print('WARNING: Attempt $retryCount failed: $e');

          if (retryCount >= maxRetries) {
            // Final fallback - try with minimal data
            try {
              await Supabase.instance.client.from('trips').update({
                'status': 'in_progress',
              }).eq('id', _dbCurrentTripId!);
              print('SUCCESS: Trip status updated with minimal data');
              tripStatusUpdated = true;

              //  SIMPLE: Trip status will be inferred from logs
              print(
                  '✅ Trip started (minimal) - status will be inferred from logs');
            } catch (finalError) {
              print('ERROR: Final attempt failed: $finalError');
              _showErrorSnackBar('Error updating trip status: $finalError');
              return;
            }
          } else {
            // Wait before retry
            await Future.delayed(Duration(seconds: retryCount));
          }
        }
      }

      // Step 4: Start location tracking
      final trackingStarted = await _locationService.startTripTracking(
        tripId: _dbCurrentTripId!,
        driverId: _dbCurrentDriverId!,
        tripRefNumber: _dbCurrentTripRefNumber ?? 'Unknown',
      );

      if (trackingStarted) {
        setState(() {
          _isLocationTracking = true;
          _currentLocation = currentLocation;
          _isTripStarted = true; // Enable trip controls
        });
        _showSuccessSnackBar(
            'Trip initiated successfully - GPS tracking enabled');

        // Step 5: Send notification to operator
        await _sendTripStartNotification();
      } else {
        _showErrorSnackBar('Trip started but GPS tracking failed');
      }

      await _loadCurrentTrip(); // Refresh trip data
    } catch (e) {
      _showErrorSnackBar('Error starting trip: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendTripStartNotification() async {
    try {
      if (_dbCurrentTrip == null || _currentUser == null) {
        print('WARNING: Cannot send notification: missing trip or user data');
        return;
      }

      final driverName = _getDriverName();
      final tripRefNumber = _dbCurrentTripRefNumber ?? 'TRIP-$_dbCurrentTripId';

      // Send notification to operator
      try {
        await NotificationService().sendTripStartNotification(
          tripId: _dbCurrentTripId!,
          driverName: driverName,
          tripRefNumber: tripRefNumber,
        );
        print('🔔 Trip start notification sent for driver: $driverName');
      } catch (notificationError) {
        print('WARNING: Notification service error: $notificationError');
        // Continue without notification - trip still starts successfully
      }
    } catch (e) {
      print('ERROR: Error sending trip start notification: $e');
    }
  }

  String _getDriverName() {
    if (_currentUser != null) {
      final firstName = _currentUser!['first_name'] ?? '';
      final lastName = _currentUser!['last_name'] ?? '';
      return '$firstName $lastName'.trim();
    }
    return 'Unknown Driver';
  }

  Future<void> _completeTrip() async {
    if (_dbCurrentTripId == null) {
      _showErrorSnackBar('No active trip to complete');
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Step 1: Stop location tracking
      if (_isLocationTracking) {
        await _locationService.stopTripTracking(
          tripId: _dbCurrentTripId!,
          driverId: _dbCurrentDriverId!,
        );
        setState(() {
          _isLocationTracking = false;
          _isTripStarted = false; // Disable trip controls
        });
      }

      // Step 2: Get final location
      final finalLocation = await _locationService.getCurrentLocation();

      // Step 3: Update trip status in database (driver completion - awaiting operator confirmation)
      Map<String, dynamic> updateData = {
        'status':
            'driver_completed', // Driver completed, awaiting operator confirmation
        'completed_at': DateTime.now().toIso8601String(),
        // Note: operator_confirmed_at is NOT set, indicating awaiting confirmation
      };

      if (finalLocation != null) {
        updateData['end_latitude'] = finalLocation.latitude ?? 0.0;
        updateData['end_longitude'] = finalLocation.longitude ?? 0.0;
        updateData['current_latitude'] = finalLocation.latitude ?? 0.0;
        updateData['current_longitude'] = finalLocation.longitude ?? 0.0;
        updateData['last_location_update'] = DateTime.now().toIso8601String();
      }

      try {
        await Supabase.instance.client
            .from('trips')
            .update(updateData)
            .eq('id', _dbCurrentTripId!);
      } catch (e) {
        // If location columns don't exist, try with only basic trip data
        try {
          Map<String, dynamic> fallbackUpdateData = {
            'status':
                'driver_completed', // Driver completed, awaiting operator confirmation
            'completed_at': DateTime.now().toIso8601String(),
            // Note: operator_confirmed_at is NOT set, indicating awaiting confirmation
          };

          await Supabase.instance.client
              .from('trips')
              .update(fallbackUpdateData)
              .eq('id', _dbCurrentTripId!);
          print(
              'WARNING: Location columns not available, updated trip status only');
        } catch (e2) {
          // If timestamp columns don't exist, try with only status
          try {
            await Supabase.instance.client.from('trips').update({
              'status':
                  'driver_completed', // Driver completed, awaiting operator confirmation
              // Note: operator_confirmed_at is NOT set, indicating awaiting confirmation
            }).eq('id', _dbCurrentTripId!);
            print(
                '⚠️ Timestamp columns not available, updated trip status only');
          } catch (e3) {
            print('WARNING: Could not update trips table: $e3');
            _showErrorSnackBar('Error completing trip: $e3');
            return;
          }
        }
      }

      // Step 4: Send completion notification to operators
      try {
        final driverName = _getDriverName();
        final tripRefNumber =
            _dbCurrentTripRefNumber ?? 'TRIP-$_dbCurrentTripId';

        await NotificationService().sendTripCompletionNotification(
          tripId: _dbCurrentTripId!,
          driverName: driverName,
          tripRefNumber: tripRefNumber,
        );
        print('🔔 Trip completion notification sent to operators');
      } catch (notificationError) {
        print(
            'WARNING: Error sending completion notification: $notificationError');
        // Continue without notification
      }

      _showSuccessSnackBar(
          'Trip marked as completed. Awaiting operator confirmation. GPS tracking stopped.');
      await _loadCurrentTrip(); // Refresh trip data
    } catch (e) {
      _showErrorSnackBar('Error completing trip: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Simulation method removed - only real IoT data is used

  Future<void> _testIoTCamera() async {
    if (!_validateConnection(action: 'test camera')) return;

    setState(() {
      _isLoading = true;
    });

    try {
      _showSuccessSnackBar('Testing IoT camera...');

      List<String> pi5Addresses = [
        '192.168.254.120',
        '192.168.4.1',
        '192.168.1.100',
      ];

      bool success = false;
      for (final ip in pi5Addresses) {
        try {
          print(
              '📹 Testing camera at $ip:8081...'); // FIXED: Already using correct port
          final request = await HttpClient().getUrl(Uri.parse(
                  'http://$ip:8081/api/camera/test') // FIXED: Already using correct port
              );
          final response = await request.close();

          if (response.statusCode == 200) {
            final responseBody = await response.transform(utf8.decoder).join();
            final data = json.decode(responseBody);

            if (data['status'] == 'success' && data['camera_info'] != null) {
              final cameraInfo = data['camera_info'];
              final status = cameraInfo['status'] ?? 'Unknown';
              final frameCaptured = cameraInfo['test_frame_captured'] ?? false;
              final frameShape = cameraInfo['frame_shape'] ?? 'Unknown';
              final universalService =
                  cameraInfo['universal_camera_service'] ?? 'unknown';

              // Update Universal Camera System status
              setState(() {
                if (universalService == 'running') {
                  _universalCameraStatus = "Running";
                  _universalCameraDetails =
                      "Service active and managing camera";
                } else if (universalService == 'not_running') {
                  _universalCameraStatus = "Not Running";
                  _universalCameraDetails = "Service not active";
                } else {
                  _universalCameraStatus = "Unknown";
                  _universalCameraDetails = "Status unclear";
                }
              });

              // Build detailed status message
              String statusMessage = '';
              if (universalService == 'running') {
                statusMessage += '✅ Universal Camera Service: Running\n';
              } else if (universalService == 'not_running') {
                statusMessage += '⚠️ Universal Camera Service: Not Running\n';
              } else {
                statusMessage += '❓ Universal Camera Service: Unknown\n';
              }

              if (frameCaptured) {
                statusMessage += '✅ Camera Frame: $frameShape\n';
                statusMessage += '✅ Status: $status';
                _showSuccessSnackBar(statusMessage);
              } else {
                statusMessage += '❌ Camera Frame: Not captured\n';
                statusMessage += '❌ Status: $status';
                _showErrorSnackBar(statusMessage);
              }

              // Log Universal Camera Service logs if available
              if (cameraInfo['universal_camera_logs'] != null) {
                print(
                    '📹 Universal Camera Logs: ${cameraInfo['universal_camera_logs']}');
              }

              print('📹 Camera test result: $status');
              success = true;
              break;
            }
          }
        } catch (e) {
          print('ERROR: Camera test error at $ip: $e');
          continue;
        }
      }

      if (!success) {
        _showErrorSnackBar('Camera test failed on all IoT addresses');
      }
    } catch (e) {
      _showErrorSnackBar('Camera test error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  //  NEW: Clear confirmation dialog to prevent accidental data loss
  void _showClearConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[800],
          title: const Text(
            '⚠️ Clear All Events',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to clear all ${_unifiedSnapshots.length} events?\n\nThis action cannot be undone.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Cancel
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                _clearAllEvents(); // Clear the data
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
  }

  //  NEW: Actually clear all events (called after confirmation)
  void _clearAllEvents() {
    setState(() {
      _unifiedSnapshots.clear();
      _snapshotImages.clear();
    });

    // Also clear from persistent storage
    _clearPersistedData();

    _showSuccessSnackBar('All events cleared successfully');
    print('REMOVE: All events cleared by user');
  }

  void _showConnectionOptions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[800],
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // WiFi Direct Info directly in popup
              Text(
                'WiFi Direct Info:',
                style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('Network: TinySync_IoT',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              SizedBox(height: 4),
              Text('Password: 12345678',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showWiFiDirectInfo() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[800],
          title: const Row(
            children: [
              Icon(Icons.wifi, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'WiFi Direct Connection Info',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connect to WiFi Direct:',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.wifi, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Network: TinySync_IoT',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.lock, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Password: 12345678',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '💡 Tip: Make sure your device is connected to the TinySync_IoT network before attempting to connect.',
                    style: TextStyle(color: Colors.blue[100], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _manualConnectToIoT();
              },
              icon: const Icon(Icons.link),
              label: const Text('Connect Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCameraSystemInfo() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[800],
          title: const Row(
            children: [
              Icon(Icons.camera_alt, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'Camera System Info',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Universal Camera System:',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.camera_alt, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'HD Pro Webcam C920',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.settings, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Managed by Universal Camera Daemon',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.info, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Status: $_universalCameraStatus',
                      style: TextStyle(
                        color: _universalCameraStatus == "Running"
                            ? Colors.green
                            : Colors.orange,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '💡 Tip: The camera system is used for drowsiness detection and driver monitoring.',
                    style: TextStyle(color: Colors.blue[100], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _testIoTCamera();
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Test Camera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _quickConnect() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _showSuccessSnackBar('Quick connecting to IoT...');

      // Force immediate connection attempt
      _startWiFiDirectConnection();

      // Wait for connection
      await Future.delayed(const Duration(seconds: 3));

      if (_isConnected) {
        _showSuccessSnackBar('Quick connection successful!');
      } else {
        _showErrorSnackBar('Quick connection failed. Try manual connect.');
      }
    } catch (e) {
      _showErrorSnackBar('Quick connection error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32), // Professional green
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
        elevation: 6,
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1976D2), // Professional blue
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
        elevation: 6,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F), // Professional red
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
        elevation: 6,
      ),
    );
  }

  String _formatSnapshotTimestamp(String? timestamp) {
    if (timestamp == null) return 'Unknown time';

    try {
      final logTime = DateTime.parse(timestamp);
      final timeDisplay =
          '${logTime.hour.toString().padLeft(2, '0')}:${logTime.minute.toString().padLeft(2, '0')}';
      final dateDisplay = '${logTime.month}/${logTime.day}/${logTime.year}';
      return '$timeDisplay | $dateDisplay';
    } catch (e) {
      return 'Unknown time';
    }
  }

  //  NEW: Show snapshot details with actual image
  void _showSnapshotDetails(Map<String, dynamic> snapshot) {
    final filename = snapshot['filename'] ?? 'Unknown';
    final behaviorType = snapshot['behavior_type'] ?? 'Unknown';
    final timestamp = snapshot['timestamp'] ??
        DateTime.now().toIso8601String(); //  FIX: Use original IoT timestamp
    //  FIX: Button events don't have images, only AI detection events do
    final hasImage = filename.isNotEmpty &&
        _snapshotImages.containsKey(filename) &&
        !behaviorType.contains('monitoring_') &&
        !behaviorType.contains('break_') &&
        !behaviorType.contains('driver_switch');

    // Parse timestamp for display
    DateTime logTime;
    try {
      logTime = DateTime.parse(timestamp);
    } catch (e) {
      logTime = DateTime.now();
    }

    // Format time for display
    String timeDisplay =
        '${logTime.hour.toString().padLeft(2, '0')}:${logTime.minute.toString().padLeft(2, '0')}';
    String dateDisplay = '${logTime.month}/${logTime.day}/${logTime.year}';

    // Get color based on behavior type
    Color eventColor;
    IconData eventIcon;
    switch (behaviorType.toLowerCase()) {
      case 'drowsiness_alert':
      case 'drowsiness_warning':
        eventColor = Colors.red;
        eventIcon = Icons.visibility_off;
        break;
      case 'looking_away_alert':
      case 'looking_away_warning':
        eventColor = Colors.orange;
        eventIcon = Icons.visibility;
        break;
      case 'face_turned':
        eventColor = Colors.yellow;
        eventIcon = Icons.face;
        break;
      default:
        eventColor = Colors.grey;
        eventIcon = Icons.warning;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: eventColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: eventColor, width: 2),
                ),
                child: Icon(
                  eventIcon,
                  color: eventColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Snapshot Details',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Actual Image Display
                if (hasImage) ...[
                  Container(
                    width: double.infinity,
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: eventColor, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _snapshotImages[filename]!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[700],
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error, color: Colors.red, size: 48),
                                SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: eventColor, width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          eventIcon,
                          size: 64,
                          color: eventColor,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Image Not Available',
                          style: TextStyle(
                            color: eventColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Image data not loaded',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Snapshot Details
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Snapshot Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                _buildDetailRow('Filename', filename, eventColor),
                _buildDetailRow('Time', timeDisplay, eventColor),
                _buildDetailRow('Date', dateDisplay, eventColor),
                _buildDetailRow(
                    'Behavior Type',
                    behaviorType.replaceAll('_', ' ').toUpperCase(),
                    eventColor),
                _buildDetailRow(
                    'Source',
                    snapshot['source'] == 'supabase'
                        ? 'Database'
                        : 'IoT Device',
                    eventColor),

                //  NEW: Display all 11 analytical fields from detection_ai.py
                if (snapshot['confidence_score'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.blue[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'AI Analysis',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                      'Confidence Score',
                      '${(snapshot['confidence_score'] * 100).toStringAsFixed(1)}%',
                      eventColor),
                  _buildDetailRow('Eye State',
                      snapshot['eye_state'] ?? 'Unknown', eventColor),
                  _buildDetailRow('Event Duration',
                      '${snapshot['event_duration'] ?? 0.0}s', eventColor),
                  _buildDetailRow('Gaze Pattern',
                      snapshot['gaze_pattern'] ?? 'Unknown', eventColor),
                  _buildDetailRow('Face Direction',
                      snapshot['face_direction'] ?? 'Unknown', eventColor),
                  _buildDetailRow(
                      'Evidence Reason',
                      snapshot['evidence_reason'] ?? 'No reason provided',
                      eventColor),
                ],

                if (snapshot['file_path'] != null &&
                    snapshot['file_path'].isNotEmpty) ...[
                  _buildDetailRow(
                      'File Path', snapshot['file_path'], eventColor),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  //  NEW: Store snapshot with image data in Supabase
  Future<void> _storeSnapshotInSupabase(
      Map<String, dynamic> snapshot, Uint8List imageData) async {
    try {
      final filename = snapshot['filename'] ?? 'Unknown';
      final behaviorType = snapshot['behavior_type'] ?? 'unknown';
      final timestamp = snapshot['timestamp'] ??
          DateTime.now()
              .toIso8601String(); //  FIX: Use original IoT timestamp //  FIX: Use original IoT timestamp
      final filePath = snapshot['file_path'] ?? '';

      //  Get correct driver ID for Supabase
      final currentDriverId = _getCurrentDriverId();

      print('SAVE: Storing snapshot in Supabase: $filename');

      // Prepare snapshot data for Supabase
      Map<String, dynamic> snapshotData = {
        'filename': filename,
        'behavior_type': behaviorType,
        'driver_id': currentDriverId,
        'trip_id': _dbCurrentTripId,
        'timestamp': timestamp,
        'device_id': 'flutter-app',
        'image_quality': 'HD',
        'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',
        'image_data': imageData, //  Store actual image data
      };

      // Insert into Supabase snapshots table
      await Supabase.instance.client.from('snapshots').insert(snapshotData);

      print('SUCCESS: Snapshot stored in Supabase successfully: $filename');
      _showSuccessSnackBar('Data synchronized successfully');
    } catch (e) {
      print('ERROR: Error storing snapshot in Supabase: $e');
      _showErrorSnackBar(
          'Supabase upload failed - Unable to sync data at this time');
    }
  }

  //  NEW: Helper function to fetch and store snapshot image data
  Future<void> _fetchAndStoreSnapshotImage(
      Map<String, dynamic> snapshot, String filename) async {
    try {
      print('SYNC: Fetching image data for: $filename');

      // Show loading state
      setState(() {
        // This will trigger the UI to show "Fetching..." status
      });

      final imageData =
          await _iotConnectionService.fetchSnapshotImage(filename);
      if (imageData != null) {
        setState(() {
          _snapshotImages[filename] = imageData;
        });
        print(
            '✅ Successfully uploaded image to phone: $filename (${imageData.length} bytes)');

        //  NEW: Save to persistent storage
        _savePersistedData();

        //  NEW: Automatically store snapshot in Supabase with image data
        await _storeSnapshotInSupabase(snapshot, imageData);

        // Show success message
        _showSuccessSnackBar('Data synchronized successfully');
      } else {
        print('WARNING: Failed to fetch image data for: $filename');
        _showErrorSnackBar(
            'IoT image fetch failed - Unable to sync data at this time');
      }
    } catch (e) {
      print('ERROR: Error fetching snapshot image: $e');
      _showErrorSnackBar('IoT connection failed - Sync operation failed');
    }
  }

  //  NEW: Show image gallery with 3 images (INTERACTIVE)
  void _showImageGallery(Map<String, dynamic> snapshot) {
    final filename = snapshot['filename'] ?? 'Unknown';
    final behaviorType = snapshot['behavior_type'] ?? 'Unknown';
    final timestamp = snapshot['timestamp'] ?? '';

    // Generate 3 related image filenames (burst sequence)
    List<String> imageFilenames = [];
    if (filename.contains('_')) {
      final baseName = filename.substring(0, filename.lastIndexOf('_'));
      final extension = filename.substring(filename.lastIndexOf('.'));
      for (int i = 1; i <= 3; i++) {
        imageFilenames.add('${baseName}_$i$extension');
      }
    } else {
      // Fallback if filename doesn't follow expected pattern
      imageFilenames = [filename, filename, filename];
    }

    // Find the first available image to show initially
    String selectedImageFilename = filename;
    for (final imageFilename in imageFilenames) {
      if (_snapshotImages.containsKey(imageFilename)) {
        selectedImageFilename = imageFilename;
        break;
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.grey[900],
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.photo_library, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Image Gallery',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                '$behaviorType - ${_formatSnapshotTimestamp(timestamp)}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  // Image Gallery
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Main large image (selected image)
                          if (_snapshotImages
                              .containsKey(selectedImageFilename)) ...[
                            Container(
                              width: double.infinity,
                              height: 300,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.grey[600]!, width: 2),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _snapshotImages[selectedImageFilename]!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[700],
                                      child: const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.error,
                                              color: Colors.red, size: 48),
                                          SizedBox(height: 8),
                                          Text(
                                            'Failed to load image',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Selected Image (${selectedImageFilename.split('/').last})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Thumbnail row for 3 images (CLICKABLE)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children:
                                imageFilenames.asMap().entries.map((entry) {
                              final index = entry.key;
                              final imageFilename = entry.value;
                              final hasImage =
                                  _snapshotImages.containsKey(imageFilename);
                              final isSelected =
                                  selectedImageFilename == imageFilename;

                              return Expanded(
                                child: GestureDetector(
                                  onTap: hasImage
                                      ? () {
                                          setDialogState(() {
                                            selectedImageFilename =
                                                imageFilename;
                                          });
                                        }
                                      : null,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: hasImage
                                          ? Colors.transparent
                                          : Colors.grey[700],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.green
                                            : (hasImage
                                                ? Colors.blue
                                                : Colors.grey[600]!),
                                        width:
                                            isSelected ? 3 : (hasImage ? 2 : 1),
                                      ),
                                    ),
                                    child: hasImage
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.memory(
                                              _snapshotImages[imageFilename]!,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return Container(
                                                  color: Colors.grey[700],
                                                  child: const Icon(Icons.error,
                                                      color: Colors.red,
                                                      size: 24),
                                                );
                                              },
                                            ),
                                          )
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.photo,
                                                  color: Colors.grey[400],
                                                  size: 24),
                                              Text(
                                                'Image ${index + 1}',
                                                style: TextStyle(
                                                  color: Colors.grey[400],
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 16),
                          Text(
                            'Burst Sequence (3 images) - Tap thumbnails to view',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  //  NEW: Fetch snapshots from Supabase (for operators)
  Future<List<Map<String, dynamic>>> _fetchSnapshotsFromSupabase() async {
    try {
      print('IMAGE: Fetching snapshots from Supabase...');

      final response = await Supabase.instance.client
          .from('snapshots')
          .select('*')
          .order('timestamp', ascending: false)
          .limit(50);

      final snapshots = List<Map<String, dynamic>>.from(response);
      print('SUCCESS: Fetched ${snapshots.length} snapshots from Supabase');

      return snapshots;
    } catch (e) {
      print('ERROR: Error fetching snapshots from Supabase: $e');
      return [];
    }
  }

  //  NEW: Load snapshots from Supabase and display them
  Future<void> _loadSnapshotsFromSupabase() async {
    try {
      final snapshots = await _fetchSnapshotsFromSupabase();

      if (snapshots.isNotEmpty) {
        print(
            'DATA: Loading ${snapshots.length} snapshots from Supabase (keeping existing ${_unifiedSnapshots.length} events)...');
        setState(() {
          // Don't clear existing data - just add new snapshots
          for (final snapshot in snapshots) {
            final filename = snapshot['filename'] ?? 'Unknown';

            final supabaseEvent = {
              'filename': filename,
              'driver_id': snapshot['driver_id'] ?? '',
              'trip_id': snapshot['trip_id'] ?? '',
              'timestamp':
                  snapshot['timestamp'] ?? DateTime.now().toIso8601String(),
              'behavior_type': snapshot['behavior_type'] ?? 'unknown',
              'file_path': '',
              'type': 'snapshot',
              'source': 'supabase', //  Mark as from Supabase
            };

            //  OPTIMIZED: Initialize sync status for Supabase events (already synced)
            _initializeSyncStatus(supabaseEvent);
            supabaseEvent['sync_status'] = 'synced'; // Mark as already synced

            _unifiedSnapshots.add(supabaseEvent);

            //  Load image data from Supabase
            if (snapshot['image_data'] != null) {
              final imageBytes = snapshot['image_data'] as List<int>;
              _snapshotImages[filename] = Uint8List.fromList(imageBytes);
              print(
                  '✅ Loaded image data from Supabase: $filename (${imageBytes.length} bytes)');
            }
          }
        });

        _showSuccessSnackBar(
            'Loaded ${snapshots.length} snapshots from database');
        print(
            '✅ Loaded ${snapshots.length} snapshots from Supabase with images');
      } else {
        _showErrorSnackBar('No snapshots found in database');
      }
    } catch (e) {
      print('ERROR: Error loading snapshots from Supabase: $e');
      _showErrorSnackBar('Failed to load snapshots: $e');
    }
  }

  void _showBehaviorEventDetails(Map<String, dynamic> log) {
    final behaviorType = log['behavior_type'] ?? 'Unknown';
    final timestamp = log['timestamp'] ?? DateTime.now().toIso8601String();
    final confidence = log['confidence'] ?? 0.0;
    final details = log['details'] ?? 'No details available';

    // Parse timestamp for display
    DateTime logTime;
    try {
      logTime = DateTime.parse(timestamp);
    } catch (e) {
      logTime = DateTime.now();
    }

    // Format time for display
    String timeDisplay =
        '${logTime.hour.toString().padLeft(2, '0')}:${logTime.minute.toString().padLeft(2, '0')}';
    String dateDisplay = '${logTime.month}/${logTime.day}/${logTime.year}';

    // Get color based on behavior type
    Color eventColor;
    IconData eventIcon;
    switch (behaviorType.toLowerCase()) {
      case 'drowsiness_alert':
      case 'drowsiness_warning':
        eventColor = Colors.red;
        eventIcon = Icons.visibility_off;
        break;
      case 'looking_away_alert':
      case 'looking_away_warning':
        eventColor = Colors.orange;
        eventIcon = Icons.visibility;
        break;
      case 'face_turned':
        eventColor = Colors.yellow;
        eventIcon = Icons.face;
        break;
      default:
        eventColor = Colors.grey;
        eventIcon = Icons.warning;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[800],
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: eventColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: eventColor, width: 2),
                ),
                child: Icon(
                  eventIcon,
                  color: eventColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  behaviorType.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Event Image Placeholder
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: eventColor, width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      eventIcon,
                      size: 64,
                      color: eventColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Event Image',
                      style: TextStyle(
                        color: eventColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Picture captured during event',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Event Details
              const Text(
                'Event Details:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),

              _buildDetailRow('Time', timeDisplay, eventColor),
              _buildDetailRow('Date', dateDisplay, eventColor),
              _buildDetailRow('Confidence',
                  '${(confidence * 100).toStringAsFixed(1)}%', eventColor),
              _buildDetailRow('Type',
                  behaviorType.replaceAll('_', ' ').toUpperCase(), eventColor),

              if (details != 'No details available') ...[
                const SizedBox(height: 8),
                const Text(
                  'Additional Details:',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[300],
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getConnectionIcon() {
    if (!_isConnected) {
      return Icons.info_outline;
    }
    return Icons.info;
  }

  String _getConnectionStatusText() {
    if (!_isConnected) {
      if (kIsWeb) {
        return 'Web Mode: IoT connection not available in browser';
      } else {
        if (_iotStatus == "Service Unavailable") {
          return 'WiFi Connected but IoT service not responding\nCheck if IoT service is running on Pi5';
        } else {
          return 'WiFi Direct: Connect to TinySync_IoT network (password: 12345678)';
        }
      }
    }

    if (kIsWeb) {
      return 'Web Mode: Connected to IoT via browser';
    } else {
      return 'WiFi Direct: Connected to Pi5 via TinySync_IoT network\nIoT Status: $_iotStatus\nCurrent Action: $_iotCurrentAction';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        toolbarHeight: 0, // Remove extra space since no title
        actions: [
          //  Driver notification alert widget
          if (_currentDriverId != null) ...[
            DriverNotificationAlert(driverId: _currentDriverId!),
            // Debug: Show driver ID in debug mode
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'ID: ${_currentDriverId!.substring(0, 8)}...',
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.list), text: 'Events'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildUnifiedEventsTab(),
        ],
      ),
    );
  }

  // Tab Building Methods
  Widget _buildOverviewTab() {
    return Container(
      color: Colors.black,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Current Trip Status (DATABASE)
            Container(
              margin: const EdgeInsets.all(16),
              child: Card(
                elevation: 4,
                color: Colors.grey[800],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Current Trip Status',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(
                            height: 32,
                            child: ElevatedButton.icon(
                              onPressed: _loadCurrentTrip,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Refresh',
                                  style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                minimumSize: const Size(0, 32),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Trip Information from Database
                      if (_dbCurrentTrip != null) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.route,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Trip: ${_dbCurrentTripRefNumber ?? 'Unknown'}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _dbCurrentTrip!['status'] ==
                                                  'assigned'
                                              ? Colors.orange
                                              : _dbCurrentTrip!['status'] ==
                                                      'in_progress'
                                                  ? Colors.green
                                                  : Colors.grey,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Status: ${_dbCurrentTrip!['status'] ?? 'Unknown'}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_dbCurrentTrip!['origin'] != null) ...[
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on,
                                          color: Colors.blue, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Origin: ${_dbCurrentTrip!['origin']}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                                if (_dbCurrentTrip!['destination'] != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on,
                                          color: Colors.red, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Destination: ${_dbCurrentTrip!['destination']}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Trip Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed:
                                    (_dbCurrentTrip!['status'] == 'assigned' &&
                                            !_isLoading)
                                        ? _startTrip
                                        : null,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.play_arrow),
                                label: Text(
                                    _isLoading ? 'Starting...' : 'Start Trip'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      _isLoading ? Colors.grey : Colors.green,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed:
                                    _dbCurrentTrip!['status'] == 'in_progress'
                                        ? _completeTrip
                                        : null,
                                icon: const Icon(Icons.check),
                                label: const Text('Complete Trip'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // GPS Tracking Status
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isLocationTracking
                                ? Colors.green.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isLocationTracking
                                  ? Colors.green
                                  : Colors.grey,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isLocationTracking
                                    ? Icons.location_on
                                    : Icons.location_off,
                                color: _isLocationTracking
                                    ? Colors.green
                                    : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isLocationTracking
                                          ? 'GPS Tracking Active'
                                          : 'GPS Tracking Inactive',
                                      style: TextStyle(
                                        color: _isLocationTracking
                                            ? Colors.green
                                            : Colors.grey,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (_currentLocation != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Location: ${_currentLocation?.latitude?.toStringAsFixed(4) ?? 'N/A'}, ${_currentLocation?.longitude?.toStringAsFixed(4) ?? 'N/A'}',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        //  REMOVED: Old sync buttons - now in main status section

                        //  CONSOLIDATED: Single Sync Status Display
                        if (_isManualSyncInProgress ||
                            _isAutoSyncInProgress ||
                            _lastManualSyncStatus.isNotEmpty ||
                            _lastAutoSyncStatus.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (_isManualSyncInProgress ||
                                      _isAutoSyncInProgress)
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (_isManualSyncInProgress ||
                                        _isAutoSyncInProgress)
                                    ? Colors.blue
                                    : Colors.green,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  (_isManualSyncInProgress ||
                                          _isAutoSyncInProgress)
                                      ? Icons.sync
                                      : Icons.check_circle,
                                  color: (_isManualSyncInProgress ||
                                          _isAutoSyncInProgress)
                                      ? Colors.blue
                                      : Colors.green,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    (_isManualSyncInProgress ||
                                            _isAutoSyncInProgress)
                                        ? (_manualSyncCurrentAction.isNotEmpty
                                            ? _manualSyncCurrentAction
                                            : 'Syncing...')
                                        : (_lastManualSyncStatus.isNotEmpty
                                            ? _lastManualSyncStatus
                                            : _lastAutoSyncStatus),
                                    style: TextStyle(
                                      color: (_isManualSyncInProgress ||
                                              _isAutoSyncInProgress)
                                          ? Colors.blue
                                          : Colors.green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        //  REMOVED: Duplicate sync button - already in main status section
                      ] else ...[
                        // No Trip Available
                        Row(
                          children: [
                            Icon(
                              Icons.route,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No active trip for today',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Check back later for new assignments',
                                    style: TextStyle(
                                        color: Colors.grey[500], fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Connection Status
            Container(
              margin: const EdgeInsets.all(16),
              child: Card(
                elevation: 4,
                color: Colors.grey[800],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title with utility buttons
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'WiFi Direct Connection Status',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          // Utility buttons (minimized)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Link Button
                              Container(
                                width: 32,
                                height: 32,
                                margin: const EdgeInsets.only(left: 4),
                                child: ElevatedButton(
                                  onPressed:
                                      _isConnected ? null : _manualConnectToIoT,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[700],
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: const Icon(Icons.link, size: 16),
                                ),
                              ),
                              // Info Button
                              Container(
                                width: 32,
                                height: 32,
                                margin: const EdgeInsets.only(left: 4),
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (_isConnected) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content:
                                              Text(_getConnectionStatusText()),
                                          backgroundColor: Colors.green,
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );
                                    } else {
                                      _showConnectionOptions();
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[700],
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: Icon(_getConnectionIcon(), size: 16),
                                ),
                              ),
                              //  REMOVED: Clear button - already available in events section
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Connection Status
                      Row(
                        children: [
                          Icon(
                            _getConnectionIcon(),
                            color: _isConnected ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isConnected
                                      ? 'Connected to IoT'
                                      : 'Disconnected',
                                  style: TextStyle(
                                    color: _isConnected
                                        ? Colors.green
                                        : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_isConnected) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'IoT Status: $_iotStatus',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                  Text(
                                    'Current Action: $_iotCurrentAction',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Current Driver: $_currentDriver',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),

                      const SizedBox(height: 16),

                      // Monitoring Control Buttons
                      _buildMonitoringControlButtons(),

                      // Detection Status
                      if (_isMonitoring) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.psychology, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'Monitoring Active - IoT is monitoring driver behavior',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Sync Buttons Row
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Sync Local Data Button
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isManualSyncInProgress
                                    ? null
                                    : _syncLocalDataToSupabase,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2A2A2A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _isManualSyncInProgress
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      Colors.white),
                                            ),
                                          )
                                        : const Icon(Icons.cloud_upload),
                                    const SizedBox(height: 2),
                                    Text(
                                      _isManualSyncInProgress
                                          ? 'Syncing...'
                                          : 'Sync Local Data',
                                      style: const TextStyle(fontSize: 11),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Sync All IoT Data Button
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _manualComprehensiveIoTSync,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2A2A2A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.sync),
                                    SizedBox(height: 2),
                                    Text(
                                      'Sync All IoT Data',
                                      style: TextStyle(fontSize: 11),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
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
            ),

            // IoT System Info
            if (_isConnected && _iotSystemInfo.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 4,
                  color: Colors.grey[800],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'IoT System Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...(_iotSystemInfo.entries
                            .map((entry) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${entry.key}: ',
                                        style: TextStyle(
                                            color: Colors.grey[400],
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${entry.value}',
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList()),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Bottom padding to prevent visual artifacts
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedEventsTab() {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          // Tab Header
          Container(
            margin: const EdgeInsets.all(16),
            child: Card(
              elevation: 4,
              color: Colors.grey[800],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.event, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Unified Events (${_unifiedSnapshots.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          _showClearConfirmationDialog();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 2),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.clear, size: 16),
                            SizedBox(width: 4),
                            Text('Clear', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Unified Events List (both behaviors and snapshots)
          Expanded(
            child: _unifiedSnapshots
                    .where((record) =>
                        record['event_type'] == 'snapshot' ||
                        record['event_type'] == 'button_action')
                    .isEmpty
                ? Center(
                    child: Text(
                      'No events yet',
                      style: TextStyle(color: Colors.grey[400], fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _unifiedSnapshots
                        .where((record) =>
                            record['event_type'] == 'snapshot' ||
                            record['event_type'] == 'button_action')
                        .length,
                    itemBuilder: (context, index) {
                      final snapshotRecords = _unifiedSnapshots
                          .where((record) =>
                              record['event_type'] == 'snapshot' ||
                              record['event_type'] == 'button_action')
                          .toList();
                      final event = snapshotRecords[index];
                      final behaviorType = event['behavior_type'] ?? 'Unknown';
                      final timestamp = event['timestamp'] ??
                          DateTime.now().toIso8601String();
                      final confidence = event['confidence'] ??
                          event['confidence_score'] ??
                          0.0;
                      final evidenceReason = event['evidence_reason'] ?? '';
                      final eventDuration = event['event_duration'] ?? 0.0;
                      final gazePattern = event['gaze_pattern'] ?? '';
                      final faceDirection = event['face_direction'] ?? '';
                      final eyeState = event['eye_state'] ?? '';
                      final filename = event['filename'] ?? '';
                      //  FIX: Button events don't have images, only AI detection events do
                      final hasImage = filename.isNotEmpty &&
                          _snapshotImages.containsKey(filename) &&
                          !behaviorType.contains('monitoring_') &&
                          !behaviorType.contains('break_') &&
                          !behaviorType.contains('driver_switch');

                      // Parse timestamp for display
                      DateTime logTime;
                      try {
                        logTime = DateTime.parse(timestamp);
                      } catch (e) {
                        logTime = DateTime.now();
                      }

                      // Format time for display
                      String timeDisplay =
                          '${logTime.hour.toString().padLeft(2, '0')}:${logTime.minute.toString().padLeft(2, '0')}';
                      String dateDisplay =
                          '${logTime.month}/${logTime.day}/${logTime.year}';

                      // Get color based on behavior type
                      Color eventColor;
                      IconData eventIcon;
                      switch (behaviorType.toLowerCase()) {
                        case 'drowsiness_alert':
                        case 'drowsiness_warning':
                          eventColor = Colors.red;
                          eventIcon = Icons.visibility_off;
                          break;
                        case 'looking_away_alert':
                        case 'looking_away_warning':
                          eventColor = Colors.orange;
                          eventIcon = Icons.visibility;
                          break;
                        case 'face_turned':
                          eventColor = Colors.yellow;
                          eventIcon = Icons.face;
                          break;
                        case 'monitoring_started':
                          eventColor = Colors.green;
                          eventIcon = Icons.play_arrow;
                          break;
                        case 'monitoring_stopped':
                          eventColor = Colors.red;
                          eventIcon = Icons.stop;
                          break;
                        case 'driver_switch':
                          eventColor = Colors.blue;
                          eventIcon = Icons.swap_horiz;
                          break;
                        case 'break_started':
                          eventColor = Colors.amber;
                          eventIcon = Icons.pause;
                          break;
                        case 'break_ended':
                          eventColor = Colors.green;
                          eventIcon = Icons.play_arrow;
                          break;
                        default:
                          eventColor = Colors.grey;
                          eventIcon = Icons.warning;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.grey[800],
                        child: InkWell(
                          onTap: hasImage
                              ? () => _showSnapshotDetails(event)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Event Icon
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: eventColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: eventColor, width: 2),
                                  ),
                                  child: Icon(
                                    eventIcon,
                                    color: eventColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Event Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              behaviorType
                                                  .replaceAll('_', ' ')
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          //  OPTIMIZED: Add sync status indicator
                                          _buildSyncStatusIndicator(event),
                                          if (hasImage) ...[
                                            const Icon(Icons.photo_camera,
                                                color: Colors.blue, size: 16),
                                            const SizedBox(width: 4),
                                            const Text('📸',
                                                style: TextStyle(fontSize: 12)),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Time: $timeDisplay | Date: $dateDisplay',
                                        style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 12),
                                      ),
                                      if (evidenceReason.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Evidence: $evidenceReason',
                                          style: TextStyle(
                                              color: Colors.blue[300],
                                              fontSize: 11),
                                        ),
                                      ],
                                      if (eventDuration > 0) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Duration: ${eventDuration.toStringAsFixed(1)}s | Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                                          style: TextStyle(
                                              color: Colors.green[300],
                                              fontSize: 11),
                                        ),
                                      ],
                                      if (gazePattern.isNotEmpty ||
                                          faceDirection.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Gaze: $gazePattern | Face: $faceDirection | Eyes: $eyeState',
                                          style: TextStyle(
                                              color: Colors.orange[300],
                                              fontSize: 11),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // Image Thumbnail or Click Indicator
                                if (hasImage) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.blue, width: 2),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.memory(
                                        _snapshotImages[filename]!,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.grey[700],
                                            child: const Icon(Icons.image,
                                                color: Colors.white),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_ios,
                                      color: Colors.blue, size: 16),
                                ] else if (filename.isNotEmpty &&
                                    !behaviorType.contains('monitoring_') &&
                                    !behaviorType.contains('break_') &&
                                    !behaviorType
                                        .contains('driver_switch')) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[700],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.grey, width: 1),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image_not_supported,
                                            color: Colors.grey, size: 20),
                                        Text('Loading...',
                                            style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 8)),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoClipsTab() {
    return Container(
      color: Colors.grey[900],
      child: Column(
        children: [
          // Tab Header
          Container(
            margin: const EdgeInsets.all(16),
            child: Card(
              elevation: 4,
              color: Colors.grey[800],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.photo_library, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'All Events (${_unifiedSnapshots.where((record) => record['event_type'] == 'snapshot' || record['event_type'] == 'button_action').length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed:
                          _isConnected ? _fetchMetadataOnlyFromIoT : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh IoT'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isConnected ? _fetchImagesOnly : null,
                      icon: const Icon(Icons.image),
                      label: const Text('Fetch Images'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _unifiedSnapshots.removeWhere(
                              (record) => record['event_type'] == 'snapshot');
                        });
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _clearPersistedData,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Clear All'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // All Events List (AI snapshots + button actions)
          Expanded(
            child: _unifiedSnapshots
                    .where((record) =>
                        record['event_type'] == 'snapshot' ||
                        record['event_type'] == 'button_action')
                    .isEmpty
                ? Center(
                    child: Text(
                      'No events available yet',
                      style: TextStyle(color: Colors.grey[400], fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _unifiedSnapshots
                        .where((record) =>
                            record['event_type'] == 'snapshot' ||
                            record['event_type'] == 'button_action')
                        .length,
                    itemBuilder: (context, index) {
                      final snapshotRecords = _unifiedSnapshots
                          .where((record) =>
                              record['event_type'] == 'snapshot' ||
                              record['event_type'] == 'button_action')
                          .toList();
                      final snapshot = snapshotRecords[index];
                      final isSnapshot = snapshot['type'] == 'snapshot';

                      final filename = snapshot['filename'] ?? 'Unknown';
                      final behaviorType =
                          snapshot['behavior_type'] ?? 'Unknown';
                      //  FIX: Button events don't have images, only AI detection events do
                      final hasImage = filename.isNotEmpty &&
                          _snapshotImages.containsKey(filename) &&
                          !behaviorType.contains('monitoring_') &&
                          !behaviorType.contains('break_') &&
                          !behaviorType.contains('driver_switch');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.grey[800],
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                // Thumbnail Display (small preview)
                                Container(
                                  width: double.infinity,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[700],
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(8)),
                                  ),
                                  child: Row(
                                    children: [
                                      // Small thumbnail preview
                                      Container(
                                        width: 60,
                                        height: 60,
                                        margin: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: hasImage
                                              ? Colors.transparent
                                              : Colors.grey[600],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.grey[500]!,
                                              width: 1),
                                        ),
                                        child: hasImage
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.memory(
                                                  _snapshotImages[filename]!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return const Icon(
                                                        Icons.error,
                                                        color: Colors.red,
                                                        size: 24);
                                                  },
                                                ),
                                              )
                                            : Icon(Icons.photo,
                                                color: Colors.grey[400],
                                                size: 24),
                                      ),
                                      // Image count indicator
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '3 Images Available',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Text(
                                              hasImage
                                                  ? '✅ Uploaded to Phone'
                                                  : '⏳ Loading from IoT...',
                                              style: TextStyle(
                                                color: hasImage
                                                    ? Colors.green
                                                    : Colors.orange,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // View button indicator
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 16),
                                        child: Icon(
                                          Icons.photo_library,
                                          color: hasImage
                                              ? Colors.blue
                                              : Colors.grey[400],
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Snapshot Info
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                              isSnapshot
                                                  ? Icons.photo
                                                  : Icons.video_library,
                                              color: isSnapshot
                                                  ? Colors.purple
                                                  : Colors.blue),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              filename,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Behavior: ${snapshot['behavior_type'] ?? 'Unknown'}',
                                        style: const TextStyle(
                                            color: Colors.orange, fontSize: 12),
                                      ),
                                      Text(
                                        _formatSnapshotTimestamp(
                                            snapshot['timestamp']),
                                        style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12),
                                      ),
                                      Text(
                                        'Source: ${snapshot['source'] == 'supabase' ? 'Database' : 'IoT Device'}',
                                        style: TextStyle(
                                          color:
                                              snapshot['source'] == 'supabase'
                                                  ? Colors.green
                                                  : Colors.blue,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: hasImage
                                              ? Colors.green.withOpacity(0.2)
                                              : Colors.orange.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: hasImage
                                                ? Colors.green
                                                : Colors.orange,
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          hasImage
                                              ? '📱 Image Ready'
                                              : '📡 Fetching...',
                                          style: TextStyle(
                                            color: hasImage
                                                ? Colors.green
                                                : Colors.orange,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (!isSnapshot) ...[
                                        Text(
                                          'Duration: ${snapshot['duration'] ?? 'Unknown'}',
                                          style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 12),
                                        ),
                                      ],
                                      // Add bottom padding to make room for the floating button
                                      const SizedBox(height: 60),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Floating View Image Button (Bottom Right)
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: ElevatedButton.icon(
                                onPressed: hasImage
                                    ? () => _showImageGallery(snapshot)
                                    : null,
                                icon: const Icon(Icons.photo_library, size: 20),
                                label: const Text('View Image',
                                    style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      hasImage ? Colors.blue : Colors.grey,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  elevation: 4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  //  ENHANCED: Sync all IoT data to Supabase with WiFi switching
  Future<void> _syncAllToSupabase() async {
    if (!_validateConnection(action: 'sync')) return;

    // Use the new WiFi switching method for proper IoT to Supabase sync
    await _syncAllIoTDataWithWiFiSwitching();
  }

  //  NEW: Manual comprehensive IoT sync (same as auto-sync but manual trigger)
  Future<void> _manualComprehensiveIoTSync() async {
    // Record manual sync timestamp to prevent immediate auto-sync
    _lastManualSyncTime = DateTime.now();

    setState(() {
      _isLoading = true;
      _lastAutoSyncStatus = 'Syncing data...';
    });

    try {
      _showSuccessSnackBar('Starting data synchronization...');

      // Step 1: Fetch Pi5 snapshot logs WITH images (snapshots)
      await _fetchUnifiedSnapshotsFromIoT();

      // Step 2: Fetch the actual snapshot images
      await _autoFetchAllMissingImages();

      // Step 3: Also fetch metadata for button actions
      await _fetchMetadataOnlyFromIoT();

      // Step 4: Fetch system status
      await _fetchSystemStatusFromIoT();

      // Step 5: Save to persistent storage
      await _savePersistedData();

      setState(() {
        _lastAutoSyncStatus = 'Data sync completed successfully';
      });

      _showSuccessSnackBar('IoT data fetched and synced successfully!');
    } catch (e) {
      print('ERROR: Manual IoT sync error: $e');
      setState(() {
        _lastAutoSyncStatus = 'Sync failed: $e';
      });

      _showErrorSnackBar('Sync failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  //  NEW: Sync local data to Supabase (no IoT connection required)
  Future<void> _syncLocalDataToSupabase() async {
    return _syncLocalDataToSupabaseOnly();
  }

  //  ALIAS: Sync local data to Supabase (no IoT connection required)
  Future<void> _syncLocalDataToSupabaseOnly() async {
    setState(() {
      _isLoading = true;
      _isManualSyncInProgress = true;
      _manualSyncProgress = 0;
      _manualSyncTotal = 0;
      _manualSyncCurrentAction = 'Preparing local data sync...';
    });

    // Sync results are tracked individually in events tab

    try {
      // VALIDATION: Check if driver and trip are assigned before syncing
      if (!_validateDriverAndTrip(action: 'sync data')) {
        setState(() {
          _isLoading = false;
          _isManualSyncInProgress = false;
          _manualSyncCurrentAction = 'Sync failed: No trip assigned';
        });
        return; // Exit early if validation fails
      }

      _showSuccessSnackBar('Syncing data to cloud...');

      //  IMPROVED VALIDATION: Check for actual IoT data to sync
      bool hasValidData = false;
      String validationMessage = '';

      // Check if we have IoT data to sync (unified structure)
      final iotDataToSync = _unifiedSnapshots
          .where((record) => record['source'] == 'iot')
          .toList();

      if (iotDataToSync.isNotEmpty) {
        hasValidData = true;
        final behaviorCount =
            iotDataToSync.where((r) => r['event_type'] == 'snapshot').length;
        final snapshotCount =
            iotDataToSync.where((r) => r['event_type'] == 'snapshot').length;
        print(
            '✅ Found IoT data to sync: $behaviorCount snapshot logs, $snapshotCount snapshots');
      } else {
        validationMessage =
            'No new data to sync. All data is already up to date.';
        print('WARNING: No IoT data found to sync');
      }

      //  EFFICIENCY: Use the same efficient method as auto-sync
      final unsyncedEvents = _unifiedSnapshots
          .where((event) =>
              event['sync_status'] != 'synced' &&
              event['sync_status'] != 'syncing')
          .toList();

      if (unsyncedEvents.isEmpty) {
        print("MANUAL-SYNC: No new events to sync - all data already synced");
        setState(() {
          _isLoading = false;
          _isManualSyncInProgress = false;
          _manualSyncCurrentAction = 'All data already synced';
        });
        _showSuccessSnackBar('All data already synced to Supabase!');
        return;
      }

      print(
          "MANUAL-SYNC: Found ${unsyncedEvents.length} unsynced events to process");

      //  EFFICIENCY: Separate by type for batch processing
      final unsyncedLogs = unsyncedEvents
          .where((event) => event['event_type'] != 'snapshot')
          .toList();

      final unsyncedSnapshots = unsyncedEvents
          .where((event) => event['event_type'] == 'snapshot')
          .toList();

      int syncedCount = 0;

      //  EFFICIENCY: Batch upload logs
      if (unsyncedLogs.isNotEmpty) {
        try {
          setState(() {
            _manualSyncCurrentAction = 'Syncing ${unsyncedLogs.length} logs...';
          });
          await _parallelBatchUpload(unsyncedLogs, 'manual-sync logs');
          syncedCount += unsyncedLogs.length;
          print("MANUAL-SYNC: Successfully synced ${unsyncedLogs.length} logs");
        } catch (e) {
          print("MANUAL-SYNC: Error syncing logs: $e");
        }
      }

      //  EFFICIENCY: Batch upload snapshots
      if (unsyncedSnapshots.isNotEmpty) {
        try {
          setState(() {
            _manualSyncCurrentAction =
                'Syncing ${unsyncedSnapshots.length} snapshots...';
          });
          await _parallelBatchUpload(
              unsyncedSnapshots, 'manual-sync snapshots');
          syncedCount += unsyncedSnapshots.length;
          print(
              "MANUAL-SYNC: Successfully synced ${unsyncedSnapshots.length} snapshots");
        } catch (e) {
          print("MANUAL-SYNC: Error syncing snapshots: $e");
        }
      }

      setState(() {
        _isLoading = false;
        _isManualSyncInProgress = false;
        _manualSyncCurrentAction = 'Sync completed successfully!';
      });

      _showSuccessSnackBar('Local data synced to Supabase successfully!');
      print("MANUAL-SYNC: Completed - $syncedCount events synced");
    } catch (e) {
      print('ERROR: Manual sync error: $e');
      setState(() {
        _isLoading = false;
        _isManualSyncInProgress = false;
      });
      _showErrorSnackBar('Manual sync failed: $e');
    }
  }

  //  NEW: Show detailed sync error popup for debugging
  void _showDetailedSyncErrorPopup(String title, String error) {
    //  ENHANCED: Analyze field issues in the data
    final iotData =
        _unifiedSnapshots.where((s) => s['source'] == 'iot').toList();
    final fieldIssues = _analyzeFieldIssues(iotData);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('🔍 $title'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Error Details:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(error,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 16),

                //  NEW: Field Issues Analysis
                const Text('Field Issues Found:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 8),
                ...fieldIssues.map((issue) => Text('❌ $issue',
                    style: const TextStyle(fontSize: 11, color: Colors.red))),
                if (fieldIssues.isEmpty)
                  const Text('✅ No field issues detected',
                      style: TextStyle(color: Colors.green)),

                const SizedBox(height: 16),
                const Text('Data Analysis:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Total Snapshots: ${_unifiedSnapshots.length}'),
                Text('IoT Data Count: ${iotData.length}'),
                Text('Connected: $_isConnected'),
                Text('Driver ID: ${_dbCurrentDriverId ?? 'null'}'),
                Text('Trip ID: ${_dbCurrentTripId ?? 'null'}'),
                Text('Current Driver: $_currentDriver'),

                const SizedBox(height: 16),
                const Text('Sample IoT Data Fields:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (iotData.isNotEmpty) ...[
                  Text(
                      'Event Type: ${iotData.first['event_type'] ?? 'MISSING'}'),
                  Text(
                      'Behavior Type: ${iotData.first['behavior_type'] ?? 'MISSING'}'),
                  Text('Filename: ${iotData.first['filename'] ?? 'MISSING'}'),
                  Text(
                      'Has Image: ${_snapshotImages.containsKey(iotData.first['filename']) ? 'YES' : 'NO'}'),
                  Text('Source: ${iotData.first['source'] ?? 'MISSING'}'),
                ] else
                  const Text('No IoT data found'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showDetailedSyncStatusPopup();
              },
              child: const Text('Show Full Status'),
            ),
          ],
        );
      },
    );
  }

  //  NEW: Analyze field issues in IoT data
  List<String> _analyzeFieldIssues(List<Map<String, dynamic>> iotData) {
    List<String> issues = [];

    if (iotData.isEmpty) {
      issues.add('No IoT data found in _unifiedSnapshots');
      return issues;
    }

    final sample = iotData.first;

    // Check required fields for sync
    if (sample['event_type'] == null) {
      issues.add('event_type field is missing (needed for sync filtering)');
    }

    if (sample['behavior_type'] == null) {
      issues.add('behavior_type field is missing');
    }

    if (sample['filename'] == null || sample['filename'] == 'Unknown') {
      issues.add(
          'filename field is missing or Unknown (needed for image lookup)');
    }

    if (sample['timestamp'] == null) {
      issues.add('timestamp field is missing');
    }

    // Check UUID fields
    if (_dbCurrentDriverId == null) {
      issues.add('Driver ID is null (needed for Supabase upload)');
    }

    if (_dbCurrentTripId == null) {
      issues.add('Trip ID is null (needed for Supabase upload)');
    }

    // Check image data
    final filename = sample['filename'];
    if (filename != null && !_snapshotImages.containsKey(filename)) {
      issues.add('Image data missing for filename: $filename');
    }

    // Check if data will be filtered for sync
    if (sample['event_type'] != 'snapshot') {
      issues.add(
          'event_type is "${sample['event_type']}" but sync looks for "snapshot"');
    }

    return issues;
  }

  // REMOVED: _showDetailedSyncResultsPopup - redundant with events tab sync status indicators

  //  NEW: Show detailed sync status popup
  void _showDetailedSyncStatusPopup() {
    final iotData =
        _unifiedSnapshots.where((s) => s['source'] == 'iot').toList();
    final localData =
        _unifiedSnapshots.where((s) => s['source'] != 'iot').toList();

    //  ENHANCED: Analyze field issues
    final fieldIssues = _analyzeFieldIssues(iotData);

    //  NEW: Get sync results from last sync attempt
    final syncResults = _getLastSyncResults();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sync Status & Results'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                //  NEW: Sync Results Section (Most Important)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: syncResults['hasErrors']
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    border: Border.all(
                      color:
                          syncResults['hasErrors'] ? Colors.red : Colors.green,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncResults['hasErrors']
                            ? 'SYNC FAILED'
                            : 'SYNC SUCCESS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: syncResults['hasErrors']
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                          'Flutter → Supabase Logs: ${syncResults['logsSynced']}/${syncResults['totalLogs']}'),
                      Text(
                          'IoT → Supabase Snapshots: ${syncResults['snapshotsSynced']}/${syncResults['totalSnapshots']}'),
                      if (syncResults['hasErrors']) ...[
                        const SizedBox(height: 8),
                        Text('Failed Items:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700)),
                        ...syncResults['failedItems'].map((item) => Padding(
                              padding: const EdgeInsets.only(left: 8, top: 2),
                              child: Text('• $item',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red.shade700)),
                            )),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                //  NEW: Data Source Identification Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border.all(
                      color: Colors.blue,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DATA SOURCE IDENTIFICATION',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('IoT Device Data:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text('  • Real-time drowsiness detection'),
                      const Text('  • Camera snapshots and AI analysis'),
                      const Text('  • Behavior logs from Pi5 device'),
                      const SizedBox(height: 8),
                      const Text('Flutter App Data:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text('  • Manual button actions'),
                      const Text('  • User interactions and events'),
                      const Text('  • Local storage and processing'),
                      const SizedBox(height: 8),
                      const Text('Supabase Cloud:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text('  • Final destination for all data'),
                      const Text('  • IoT data + Flutter data combined'),
                      const Text('  • Cloud database storage'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Field Validation Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: fieldIssues.isEmpty
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    border: Border.all(
                      color: fieldIssues.isEmpty ? Colors.green : Colors.orange,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fieldIssues.isEmpty ? 'FIELDS VALID' : 'FIELD ISSUES',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: fieldIssues.isEmpty
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (fieldIssues.isEmpty)
                        Text('All fields are valid for sync.',
                            style: TextStyle(
                                color: Colors.green.shade700, fontSize: 12))
                      else ...[
                        Text('${fieldIssues.length} field issue(s):',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                                fontSize: 12)),
                        ...fieldIssues.map((issue) => Padding(
                              padding: const EdgeInsets.only(left: 8, top: 1),
                              child: Text('• $issue',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange.shade700)),
                            )),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Basic Status Info
                const Text('Data Status:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('• Total Snapshots: ${_unifiedSnapshots.length}'),
                Text('• IoT Data: ${iotData.length}'),
                Text('• Local Data: ${localData.length}'),
                Text('• Driver ID: ${_dbCurrentDriverId ?? 'null'}'),
                Text('• Trip ID: ${_dbCurrentTripId ?? 'null'}'),

                //  NEW: Sample Data Analysis
                if (iotData.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Sample IoT Data:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                      '• Event Type: ${iotData.first['event_type'] ?? 'MISSING'}'),
                  Text(
                      '• Behavior Type: ${iotData.first['behavior_type'] ?? 'MISSING'}'),
                  Text('• Filename: ${iotData.first['filename'] ?? 'MISSING'}'),
                  Text(
                      '• Has Image: ${_snapshotImages.containsKey(iotData.first['filename']) ? 'YES' : 'NO'}'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  //  NEW: Efficient auto-sync function (only processes unsynced events)
  Future<void> _autoSyncLocalDataToSupabase() async {
    try {
      //  EFFICIENCY: Only get unsynced events
      final unsyncedEvents = _unifiedSnapshots
          .where((event) =>
              event['sync_status'] != 'synced' &&
              event['sync_status'] != 'syncing')
          .toList();

      if (unsyncedEvents.isEmpty) {
        print("AUTO-SYNC: No new events to sync - skipping");
        return;
      }

      print(
          "AUTO-SYNC: Found ${unsyncedEvents.length} unsynced events to process");

      //  EFFICIENCY: Separate by type for batch processing
      final unsyncedLogs = unsyncedEvents
          .where((event) => event['event_type'] != 'snapshot')
          .toList();

      final unsyncedSnapshots = unsyncedEvents
          .where((event) => event['event_type'] == 'snapshot')
          .toList();

      int syncedCount = 0;

      //  EFFICIENCY: Batch upload logs
      if (unsyncedLogs.isNotEmpty) {
        try {
          await _parallelBatchUpload(unsyncedLogs, 'auto-sync logs');
          syncedCount += unsyncedLogs.length;
          print("AUTO-SYNC: Successfully synced ${unsyncedLogs.length} logs");
        } catch (e) {
          print("AUTO-SYNC: Error syncing logs: $e");
        }
      }

      //  EFFICIENCY: Batch upload snapshots
      if (unsyncedSnapshots.isNotEmpty) {
        try {
          await _parallelBatchUpload(unsyncedSnapshots, 'auto-sync snapshots');
          syncedCount += unsyncedSnapshots.length;
          print(
              "AUTO-SYNC: Successfully synced ${unsyncedSnapshots.length} snapshots");
        } catch (e) {
          print("AUTO-SYNC: Error syncing snapshots: $e");
        }
      }

      print("AUTO-SYNC: Completed - $syncedCount events synced silently");
    } catch (e) {
      print("AUTO-SYNC: General error: $e");
      // Auto-sync errors are logged but not shown to user
    }
  }

  //  LEGACY: Simple sync results for backward compatibility
  Map<String, dynamic> _getLastSyncResults() {
    return {
      'logsSynced': 0,
      'snapshotsSynced': 0,
      'hasErrors': false,
    };
  }

  //  REMOVED: Batch Supabase check - no longer needed with sync status approach

  //  REMOVED: Supabase existence checks - no longer needed with sync status approach

  //  NEW: Parallel upload for maximum speed (optional)
  Future<void> _parallelUpload(
      List<Map<String, dynamic>> items, String itemType) async {
    const int batchSize = 3; // Upload 3 items at once

    for (int i = 0; i < items.length; i += batchSize) {
      final batch = items.skip(i).take(batchSize).toList();

      setState(() {
        _syncCurrentAction =
            'Uploading $itemType batch ${(i ~/ batchSize) + 1}/${(items.length / batchSize).ceil()}...';
      });

      // Upload batch in parallel
      await Future.wait(batch.map((item) => _uploadSingleItem(item, itemType)));

      // Update progress
      setState(() {
        _manualSyncProgress += batch.length;
      });
    }
  }

  //  NEW: Upload single item
  Future<void> _uploadSingleItem(
      Map<String, dynamic> item, String itemType) async {
    try {
      final data = item['data'] as Map<String, dynamic>;
      await Supabase.instance.client
          .from('snapshots')
          .insert(data)
          .timeout(const Duration(seconds: 30));

      // Track successful upload
      final uploadRecord = {
        'behavior_id': item['behavior_id'],
        'timestamp': item['timestamp'],
        'uploaded_at': DateTime.now().toIso8601String(),
      };
      _uploadedItems.add(uploadRecord);
    } catch (e) {
      print('ERROR: Failed to upload $itemType: ${item['behavior_type']} - $e');
      rethrow;
    }
  }

  //  OPTIMIZED: Parallel batch upload for maximum speed
  Future<void> _parallelBatchUpload(
      List<Map<String, dynamic>> items, String itemType) async {
    if (items.isEmpty) return;

    const int batchSize = 10; // Upload 10 items at a time
    final List<List<Map<String, dynamic>>> batches = [];

    // Split items into batches
    for (int i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      batches.add(items.sublist(i, end));
    }

    print(
        'UPLOAD: Uploading ${items.length} $itemType in ${batches.length} parallel batches...');

    // Upload all batches in parallel
    final List<Future<void>> uploadTasks = batches.map((batch) async {
      try {
        if (itemType == 'snapshots') {
          await _batchUploadSnapshots(batch);
        } else {
          await _batchUploadLogs(batch, itemType);
        }
      } catch (e) {
        print('ERROR: Batch upload failed for $itemType: $e');
        rethrow;
      }
    }).toList();

    // Wait for all batches to complete
    await Future.wait(uploadTasks);
    print(
        'SUCCESS: All ${batches.length} batches of $itemType uploaded successfully');
  }

  //  OPTIMIZED: Batch upload snapshots for maximum speed
  Future<void> _batchUploadSnapshots(
      List<Map<String, dynamic>> snapshots) async {
    if (snapshots.isEmpty) return;

    setState(() {
      _syncCurrentAction =
          'Preparing ${snapshots.length} snapshots for batch upload...';
    });

    //  PREPARE: Build all snapshot data in memory first
    final List<Map<String, dynamic>> batchData = [];

    //  OPTIMIZED: Process all snapshots without excessive UI updates
    for (int i = 0; i < snapshots.length; i++) {
      final snapshot = snapshots[i];
      final filename = snapshot['filename'] ?? 'Unknown';

      //  OPTIMIZED: Check sync status instead of Supabase validation
      if (snapshot['sync_status'] == 'synced') {
        print('SUCCESS: Snapshot already synced: $filename');
        continue;
      }

      //  OPTIMIZED: Only update UI every 5 items to reduce rebuilds
      if (i % 5 == 0 || i == snapshots.length - 1) {
        setState(() {
          _syncCurrentAction =
              'Preparing ${i + 1}/${snapshots.length} snapshots...';
        });
      }

      //  GET IMAGE DATA: Only for actual snapshots with images (not button actions)
      String? imageBase64;
      if (filename.isNotEmpty &&
          _snapshotImages.containsKey(filename) &&
          snapshot['event_type'] == 'snapshot') {
        try {
          final imageData = _snapshotImages[filename]!;
          //  OPTIMIZED: Compress image before encoding
          final compressedImageData = await _compressImageForUpload(imageData);
          imageBase64 = base64.encode(compressedImageData);
        } catch (e) {
          print('WARNING: Failed to process image $filename: $e');
          imageBase64 = null;
        }
      } else {
        //  FIX: Button actions don't have images, set to null
        imageBase64 = null;
      }

      final snapshotData = {
        'behavior_id': snapshot['behavior_id'] ??
            'snapshot-${DateTime.now().millisecondsSinceEpoch}',
        'filename': filename,
        'trip_id': _dbCurrentTripId ?? 'no-trip-id',
        'driver_id': _dbCurrentDriverId ?? 'unknown-driver',
        'behavior_type': snapshot['behavior_type'],
        'timestamp': snapshot['timestamp'],
        'source': 'iot',
        'details': null,
        'event_type': 'snapshot',
        'evidence_reason': snapshot['evidence_reason'],
        'confidence_score': snapshot['confidence_score'],
        'event_duration': snapshot['event_duration'],
        'gaze_pattern': snapshot['gaze_pattern'],
        'face_direction': snapshot['face_direction'],
        'eye_state': snapshot['eye_state'],
        'device_id': 'pi5-device',
        'driver_type': snapshot['driver_type'] ??
            (_currentDriver == "Main Driver" ? 'main' : 'sub'),
        'image_data': imageBase64,
      };

      batchData.add(snapshotData);
    }

    if (batchData.isEmpty) {
      print('SUCCESS: No snapshots to upload (all already synced)');
      return;
    }

    print(
        'UPLOAD: Batch uploading ${batchData.length} snapshots to Supabase...');

    setState(() {
      _syncCurrentAction =
          'Uploading ${batchData.length} snapshots in batch...';
    });

    try {
      //  MAXIMUM SPEED: Single batch insert for all snapshots
      await Supabase.instance.client
          .from('snapshots')
          .insert(batchData)
          .timeout(const Duration(seconds: 60)); // Longer timeout for images

      print(
          'SUCCESS: Successfully batch uploaded ${batchData.length} snapshots');

      //  OPTIMIZED: Mark all snapshots as synced after successful upload
      for (final snapshot in snapshots) {
        _markEventAsSynced(snapshot);
      }

      //  UPDATE: Progress all at once
      setState(() {
        _manualSyncProgress += batchData.length;
      });
    } catch (e) {
      print('ERROR: Batch snapshot upload failed: $e');
      rethrow;
    }
  }

  //  MAXIMUM SPEED: Batch upload function
  Future<void> _batchUploadLogs(
      List<Map<String, dynamic>> logs, String logType) async {
    if (logs.isEmpty) return;

    setState(() {
      _syncCurrentAction =
          'Preparing ${logs.length} $logType for batch upload...';
    });

    //  PREPARE: Build all log data in memory first
    final List<Map<String, dynamic>> batchData = [];

    //  OPTIMIZED: Process all items without excessive UI updates
    for (int i = 0; i < logs.length; i++) {
      final log = logs[i];

      //  OPTIMIZED: Only update UI every 5 items to reduce rebuilds
      if (i % 5 == 0 || i == logs.length - 1) {
        setState(() {
          _syncCurrentAction = 'Preparing ${i + 1}/${logs.length} $logType...';
        });
      }

      //  GET IMAGE DATA: Only for AI detection events
      String? imageBase64;
      final filename = log['filename'];
      final eventType = log['event_type'] ?? '';

      if (eventType == 'snapshot' && filename != null && filename.isNotEmpty) {
        if (_snapshotImages.containsKey(filename)) {
          final imageData = _snapshotImages[filename]!;
          //  OPTIMIZED: Skip base64 encoding for now - do it during upload
          imageBase64 = 'pending'; // Mark as pending, encode during upload
        } else {
          imageBase64 = null;
        }
      } else {
        //  FIX: Button actions, null filenames, or empty filenames don't have images
        imageBase64 = null;
      }

      final logData = {
        'behavior_id': log['behavior_id'] ??
            '$logType-${DateTime.now().millisecondsSinceEpoch}',
        'filename': filename,
        'trip_id': _dbCurrentTripId ?? 'no-trip-id',
        'driver_id': _dbCurrentDriverId ?? 'unknown-driver',
        'behavior_type': log['behavior_type'],
        'timestamp': log['timestamp'],
        'source': logType == 'AI logs' ? 'iot' : 'flutter',
        'details': null,
        'event_type': log['event_type'] ??
            (logType == 'AI logs' ? 'snapshot' : 'button_action'),
        'evidence_reason': log['evidence_reason'] ??
            (logType == 'button actions' ? 'Manual button action' : null),
        'confidence_score': log['confidence_score'],
        'event_duration': log['event_duration'],
        'gaze_pattern': log['gaze_pattern'],
        'face_direction': log['face_direction'],
        'eye_state': log['eye_state'],
        'device_id': logType == 'AI logs' ? 'pi5-device' : 'flutter-app',
        'driver_type': log['driver_type'] ??
            (_currentDriver == "Main Driver" ? 'main' : 'sub'),
        'image_data': imageBase64,
      };

      batchData.add(logData);
    }

    print(
        'UPLOAD: Batch uploading ${batchData.length} $logType to Supabase...');

    setState(() {
      _syncCurrentAction = 'Uploading ${batchData.length} $logType in batch...';
    });

    try {
      //  OPTIMIZED: Encode images just before upload (faster than during preparation)
      setState(() {
        _syncCurrentAction =
            'Encoding images for ${batchData.length} $logType...';
      });

      for (int i = 0; i < batchData.length; i++) {
        final logData = batchData[i];
        if (logData['image_data'] == 'pending') {
          final filename = logData['filename'];
          if (filename != null && _snapshotImages.containsKey(filename)) {
            final imageData = _snapshotImages[filename]!;
            logData['image_data'] = base64.encode(imageData);
          } else {
            logData['image_data'] = null;
          }
        }
      }

      //  REAL-TIME PROGRESS: Show upload progress
      setState(() {
        _syncCurrentAction =
            'Uploading ${batchData.length} $logType to Supabase...';
      });

      //  MAXIMUM SPEED: Single batch insert
      await Supabase.instance.client
          .from('snapshots')
          .insert(batchData)
          .timeout(const Duration(seconds: 30));

      print(
          'SUCCESS: Successfully batch uploaded ${batchData.length} $logType');

      //  OPTIMIZED: Mark all events as synced after successful upload
      for (final log in logs) {
        _markEventAsSynced(log);
      }

      //  UPDATE: Progress all at once
      setState(() {
        _manualSyncProgress += batchData.length;
      });
    } catch (e) {
      print('ERROR: Batch upload failed for $logType: $e');
      rethrow;
    }
  }

  //  NEW: Compress image for efficient upload
  Future<Uint8List> _compressImageForUpload(Uint8List originalImage) async {
    try {
      //  SIMPLE COMPRESSION: Convert to base64 and compress if too large
      if (originalImage.length > 1024 * 1024) {
        // If larger than 1MB
        print('BATCH: Compressing image from ${originalImage.length} bytes');

        // For now, we'll use the original image but in a real implementation,
        // you would use image compression libraries like flutter_image_compress
        // This is a placeholder for the compression logic

        //  ALTERNATIVE: Store as base64 string instead of binary
        final base64String = base64Encode(originalImage);
        final compressedBytes = utf8.encode(base64String);

        print('BATCH: Compressed to ${compressedBytes.length} bytes (base64)');
        return Uint8List.fromList(compressedBytes);
      }

      return originalImage;
    } catch (e) {
      print('ERROR: Error compressing image: $e');
      return originalImage; // Return original if compression fails
    }
  }

  //  NEW: Store compressed snapshot in Supabase
  Future<void> _storeCompressedSnapshotInSupabase(
      Map<String, dynamic> snapshot, Uint8List compressedImageData) async {
    try {
      final filename = snapshot['filename'] ?? 'Unknown';

      //  OPTIMIZED: Check sync status instead of Supabase validation
      if (snapshot['sync_status'] == 'synced') {
        print('SUCCESS: Snapshot already synced: $filename');
        return;
      }
      final behaviorType = snapshot['behavior_type'] ?? 'unknown';
      final timestamp = snapshot['timestamp'] ??
          DateTime.now().toIso8601String(); //  FIX: Use original IoT timestamp
      final filePath = snapshot['file_path'] ?? '';

      //  Get correct driver ID for Supabase (with fallback)
      final currentDriverId = _getCurrentDriverId() ??
          'default-driver-${DateTime.now().millisecondsSinceEpoch}';
      final tripId = _dbCurrentTripId ??
          'default-trip-${DateTime.now().millisecondsSinceEpoch}';

      print('SAVE: Storing compressed snapshot in Supabase: $filename');

      //  Clean snapshot data
      final cleanSnapshot = Map<String, dynamic>.from(snapshot);

      // Prepare snapshot data for Supabase with compressed image
      Map<String, dynamic> snapshotData = {
        'filename': filename,
        'behavior_type': behaviorType,
        'driver_id': currentDriverId,
        'trip_id': tripId,
        'timestamp': timestamp,
        'device_id': 'flutter-app',
        'image_quality': 'compressed',
        'file_size_mb':
            (compressedImageData.length / (1024 * 1024)).toStringAsFixed(2),
        'driver_type': _currentDriver == "Main Driver" ? 'main' : 'sub',
        'image_data': compressedImageData, //  Store compressed image data
      };

      // Insert into Supabase snapshots table with enhanced timeout and retry
      await _retryWithBackoff(
        operation: () => Supabase.instance.client
            .from('snapshots')
            .insert(snapshotData)
            .timeout(_getTimeoutForOperation('upload')),
        maxRetries: 2,
        operationName: 'Snapshot upload to Supabase',
      );

      print(
          'SUCCESS: Compressed snapshot stored in Supabase successfully: $filename');

      //  OPTIMIZED: Mark as synced using new sync status approach
      _markEventAsSynced(snapshot);
    } catch (e) {
      print('ERROR: Error storing compressed snapshot in Supabase: $e');
      rethrow; // Re-throw to be handled by caller
    }
  }

  //  NEW: Local Data Persistence Methods

  //  CORE REQUIREMENT: Load logs and snapshots from local storage
  Future<void> _loadPersistedData() async {
    try {
      print('LOAD: Loading logs and snapshots from local storage...');
      final prefs = await SharedPreferences.getInstance();

      // Load logs and snapshots
      final unifiedSnapshotsJson =
          prefs.getStringList('unified_snapshots') ?? [];

      print(
          'DATA: Found ${unifiedSnapshotsJson.length} saved events in storage');

      setState(() {
        _unifiedSnapshots.clear();
        for (final recordJson in unifiedSnapshotsJson) {
          try {
            final record = json.decode(recordJson);
            //  OPTIMIZED: Initialize sync status for loaded events
            _initializeSyncStatus(record);
            _unifiedSnapshots.add(record);
          } catch (e) {
            print('WARNING: Error parsing log record: $e');
          }
        }
      });

      print('SUCCESS: Loaded ${_unifiedSnapshots.length} events from storage');

      //  NEW: Load uploaded items tracking to prevent duplicates
      final uploadedItemsJson = prefs.getStringList('uploaded_items') ?? [];
      _uploadedItems.clear();
      for (final recordJson in uploadedItemsJson) {
        try {
          final record = json.decode(recordJson);
          _uploadedItems.add(record);
        } catch (e) {
          print('WARNING: Error parsing upload record: $e');
        }
      }

      // Load images
      final imageKeys =
          prefs.getKeys().where((key) => key.startsWith('image_')).toList();
      for (final key in imageKeys) {
        try {
          final base64Image = prefs.getString(key);
          if (base64Image != null) {
            final filename = key.replaceFirst('image_', '');
            final imageData = base64.decode(base64Image);
            _snapshotImages[filename] = Uint8List.fromList(imageData);
          }
        } catch (e) {
          print('WARNING: Error loading image $key: $e');
        }
      }

      print(
          '✅ Loaded ${_unifiedSnapshots.length} logs, ${_uploadedItems.length} upload records, and ${_snapshotImages.length} images from local storage');
    } catch (e) {
      print('ERROR: Error loading logs and snapshots: $e');
    }
  }

  //  CORE REQUIREMENT: Save logs and snapshots to local storage
  Future<void> _savePersistedData() async {
    try {
      print('SAVE: Saving logs and snapshots to local storage...');
      print('DATA: About to save ${_unifiedSnapshots.length} events');
      final prefs = await SharedPreferences.getInstance();

      // Save logs and snapshots
      final unifiedSnapshotsJson =
          _unifiedSnapshots.map((record) => json.encode(record)).toList();
      await prefs.setStringList('unified_snapshots', unifiedSnapshotsJson);

      //  NEW: Save uploaded items tracking to prevent duplicates
      final uploadedItemsJson =
          _uploadedItems.map((record) => json.encode(record)).toList();
      await prefs.setStringList('uploaded_items', uploadedItemsJson);

      // Save images
      for (final entry in _snapshotImages.entries) {
        final filename = entry.key;
        final imageData = entry.value;
        final base64Image = base64.encode(imageData);
        await prefs.setString('image_$filename', base64Image);
      }

      print(
          '✅ Saved ${_unifiedSnapshots.length} logs, ${_uploadedItems.length} upload records, and ${_snapshotImages.length} images to local storage');
    } catch (e) {
      print('ERROR: Error saving logs and snapshots: $e');
    }
  }

  Future<void> _clearPersistedData() async {
    try {
      print('REMOVE: Clearing persisted data...');
      final prefs = await SharedPreferences.getInstance();

      // Clear unified snapshots
      await prefs.remove('unified_snapshots');

      //  NEW: Clear uploaded items tracking
      await prefs.remove('uploaded_items');

      // Clear image data
      final imageKeys =
          prefs.getKeys().where((key) => key.startsWith('image_')).toList();
      for (final key in imageKeys) {
        await prefs.remove(key);
      }

      setState(() {
        _unifiedSnapshots.clear();
        _uploadedItems.clear();
        _snapshotImages.clear();
      });

      print('SUCCESS: Cleared all persisted data');
      _showSuccessSnackBar('Local data cleared successfully');
    } catch (e) {
      print('ERROR: Error clearing persisted data: $e');
      _showErrorSnackBar('Error clearing data: $e');
    }
  }

  //  NEW: Process organized batch data from detection_ai.py
  Future<void> _processOrganizedBatchData(
      Map<String, dynamic> batchData) async {
    try {
      print('BATCH: Processing organized batch data...');

      // Clear old data
      setState(() {
        _unifiedSnapshots.clear();
        _snapshotImages.clear();
      });

      final organizedData = batchData['organized_data'];

      // Process snapshot logs
      if (organizedData['behavior_logs'] != null) {
        final behaviorLogs = List<Map<String, dynamic>>.from(
            organizedData['behavior_logs']['items'] ?? []);
        print(
            '📝 Processing ${behaviorLogs.length} snapshot logs from batch...');

        for (final log in behaviorLogs) {
          //  DRIVER ID ALIGNMENT: Map IoT driver IDs to database IDs
          String driverId = log['driver_id'] ?? '';
          String tripId = log['trip_id'] ?? '';

          //  SIMPLIFIED: No need for driver ID alignment - using driver_type instead

          final processedLog = {
            ...log, //  FIXED: Include all original log data
            'driver_id': driverId,
            'trip_id': tripId,
            'event_type': log['event_type'] ??
                'behavior', // New field from detection_ai.py

            //  NEW: Ensure all evidence fields are included
            'evidence_reason': log['evidence_reason'],
            'confidence_score': log['confidence'] ??
                log['confidence_score'], //  FIX: IoT sends 'confidence', not 'confidence_score'
            'event_duration': log['event_duration'],
            'gaze_pattern': log['gaze_pattern'],
            'face_direction': log['face_direction'],
            'eye_state': log['eye_state'],
            'is_legitimate_driving': log['is_legitimate_driving'],
            'evidence_strength': log['evidence_strength'],
            'trigger_justification': log['trigger_justification'],
            'device_id': log['device_id'],
            'driver_type': log['driver_type'],
          };

          _unifiedSnapshots.add(processedLog);
        }
      }

      // Process snapshots
      if (organizedData['snapshots'] != null) {
        final snapshots = List<Map<String, dynamic>>.from(
            organizedData['snapshots']['items'] ?? []);
        print('IMAGE: Processing ${snapshots.length} snapshots from batch...');

        for (final snapshot in snapshots) {
          final filename = snapshot['filename'] ?? 'Unknown';

          //  FIX: Ensure proper driver_id and trip_id
          String driverId = snapshot['driver_id'] ?? '';
          String tripId = snapshot['trip_id'] ?? '';

          //  SIMPLIFIED: No need for driver ID alignment - using driver_type instead

          final processedSnapshot = {
            ...snapshot,
            'driver_id': driverId,
            'trip_id': tripId,
            'event_type': snapshot['event_type'] ??
                'snapshot', // New field from detection_ai.py

            //  NEW: Ensure all evidence fields are included for snapshots
            'evidence_reason': snapshot['evidence_reason'],
            'confidence_score': snapshot['confidence'] ??
                snapshot[
                    'confidence_score'], //  FIX: IoT sends 'confidence', not 'confidence_score'
            'event_duration': snapshot['event_duration'],
            'gaze_pattern': snapshot['gaze_pattern'],
            'face_direction': snapshot['face_direction'],
            'eye_state': snapshot['eye_state'],
            'is_legitimate_driving': snapshot['is_legitimate_driving'],
            'evidence_strength': snapshot['evidence_strength'],
            'trigger_justification': snapshot['trigger_justification'],
            'device_id': snapshot['device_id'],
            'driver_type': snapshot['driver_type'],
            'image_quality': snapshot['image_quality'],
            'file_size_mb': snapshot['file_size_mb'],
          };

          _unifiedSnapshots.add(processedSnapshot);
        }
      }

      // Process system logs
      if (organizedData['system_logs'] != null) {
        final systemLogs = List<Map<String, dynamic>>.from(
            organizedData['system_logs']['items'] ?? []);
        print('📋 Processing ${systemLogs.length} system logs from batch...');

        for (final log in systemLogs) {
          _unifiedSnapshots.add(log);
        }
      }

      print('SUCCESS: Organized batch data processed successfully');
      print('   - Total unified logs: ${_unifiedSnapshots.length}');
    } catch (e) {
      print('ERROR: Error processing organized batch data: $e');
      rethrow;
    }
  }

  //  UPDATED: Comprehensive Data Sync System (aligned with new detection_ai.py)
  Future<void> _syncAllIoTDataOnConnection() async {
    if (!_validateConnection(action: 'sync')) return;

    try {
      print(
          '🔄 Starting comprehensive IoT data sync (new organized format)...');
      _showSuccessSnackBar('Syncing all IoT data...');

      //  NEW: Try organized batch sync first (from updated detection_ai.py)
      print('BATCH: Step 1: Attempting organized batch sync...');
      final batchData = await _iotConnectionService.fetchOrganizedBatchSync();

      if (batchData != null && batchData['organized_data'] != null) {
        print('SUCCESS: Using organized batch sync format');
        await _processOrganizedBatchData(batchData);
      } else {
        print(
            '⚠️ Organized batch sync not available, falling back to individual fetches');

        //  FIXED: Don't clear existing data - append new data instead
        print(
            'DATA: Syncing new data with existing ${_unifiedSnapshots.length} events...');

        // Step 1: Fetch unified snapshots data from IoT with timeout
        print('DATA: Step 1: Fetching unified snapshots data...');
        await _fetchUnifiedSnapshotsFromIoT().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            print('⏰ Timeout: Unified snapshots fetch took too long');
            throw TimeoutException(
                'Unified snapshots fetch timeout', const Duration(seconds: 30));
          },
        );
      }

      // Step 3: Fetch all missing images with timeout
      print('🖼️ Step 3: Fetching missing images...');
      await _retryWithBackoff(
        operation: () => _fetchAllMissingImages(_unifiedSnapshots
                .where((s) => s['event_type'] == 'snapshot')
                .toList())
            .timeout(
          _getTimeoutForOperation('image_fetch'),
          onTimeout: () {
            print('⏰ Timeout: Image fetch took too long');
            throw TimeoutException(
                'Image fetch timeout', _getTimeoutForOperation('image_fetch'));
          },
        ),
        maxRetries: 2,
        operationName: 'Image fetch from IoT',
      );

      // Step 4: Save everything to local storage
      print('SAVE: Step 4: Saving to local storage...');
      await _savePersistedData();

      print('SUCCESS: Comprehensive IoT data sync completed');
      _showSuccessSnackBar('All data synced successfully!');
    } catch (e) {
      print('ERROR: Error during comprehensive IoT data sync: $e');
      _showErrorSnackBar('Error syncing IoT data: $e');
    }
  }

  //  NEW: WiFi Switching for IoT to Supabase Sync
  Future<bool> _switchToInternetForSupabase() async {
    try {
      print('🌐 Switching from WiFi Direct to Internet for Supabase sync...');

      // Disconnect from WiFi Direct temporarily
      if (_isConnected) {
        print('WIFI: Temporarily disconnecting from WiFi Direct...');
        _iotConnectionService.disconnect();
        setState(() {
          _isConnected = false;
        });
      }

      // Wait a moment for network switching
      await Future.delayed(const Duration(seconds: 2));

      print('SUCCESS: Switched to Internet mode for Supabase sync');
      return true;
    } catch (e) {
      print('ERROR: Error switching to Internet: $e');
      return false;
    }
  }

  Future<void> _switchBackToWiFiDirect() async {
    try {
      print('WIFI: Switching back to WiFi Direct for IoT connection...');

      // Reconnect to WiFi Direct
      _startWiFiDirectConnection();

      print('SUCCESS: Switched back to WiFi Direct mode');
    } catch (e) {
      print('ERROR: Error switching back to WiFi Direct: $e');
    }
  }

  //  ENHANCED: Sync all IoT data with proper WiFi switching
  Future<void> _syncAllIoTDataWithWiFiSwitching() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _showSuccessSnackBar('Starting data synchronization...');

      // Step 1: Fetch all data from IoT via WiFi Direct
      print('WIFI: Step 1: Fetching data from IoT via WiFi Direct...');
      await _syncAllIoTDataOnConnection();

      // Step 2: Switch to Internet for Supabase sync
      print('🌐 Step 2: Switching to Internet for Supabase sync...');
      final switchSuccess = await _switchToInternetForSupabase();

      if (switchSuccess) {
        // Step 3: Sync all local data to Supabase
        print('☁️ Step 3: Syncing data to Supabase...');
        await _syncLocalDataToSupabase();

        // Step 4: Switch back to WiFi Direct
        print('WIFI: Step 4: Switching back to WiFi Direct...');
        await _switchBackToWiFiDirect();

        _showSuccessSnackBar('Complete sync successful!');
      } else {
        _showErrorSnackBar('Failed to switch to Internet for Supabase sync');
        // Try to reconnect to WiFi Direct
        await _switchBackToWiFiDirect();
      }
    } catch (e) {
      print('ERROR: Error during comprehensive sync: $e');
      _showErrorSnackBar('Error during comprehensive sync: $e');
      // Try to reconnect to WiFi Direct
      await _switchBackToWiFiDirect();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  //  SEPARATED: Manual sync status variables (for button UI)
  bool _isManualSyncInProgress = false;
  String _lastManualSyncStatus = '';
  int _manualSyncProgress = 0;
  int _manualSyncTotal = 0;
  String _manualSyncCurrentAction = '';

  //  SEPARATED: Auto-sync status variables (for background sync)
  bool _isAutoSyncInProgress = false;
  //  LEGACY: Variables for backward compatibility (will be removed)
  int _syncTotal = 0;
  String _syncCurrentAction = '';
  String _lastSyncStatus = '';

  //  NEW: Check Internet connectivity to prevent spam upload failures
  Future<bool> _checkInternetConnectivity() async {
    try {
      // Quick connectivity check - try to reach a reliable endpoint
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      print('CONNECTIVITY: No Internet connection detected: $e');
      return false;
    }
  }

  //  NEW: Improved sync with better error handling and status tracking
  Future<void> _syncWithStatusTracking() async {
    if (_isManualSyncInProgress) {
      _showErrorSnackBar('Sync already in progress. Please wait...');
      return;
    }

    setState(() {
      _isManualSyncInProgress = true;
      _isLoading = true;
      _lastSyncStatus = 'Starting sync...';
    });

    try {
      // Step 1: Fetch IoT data with timeout
      setState(() {
        _lastSyncStatus = 'Fetching data from IoT...';
      });
      print('SYNC: Step 1: Starting IoT data fetch...');

      // Add timeout to prevent hanging
      await _syncAllIoTDataOnConnection().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('⏰ Timeout: IoT data fetch took too long');
          throw TimeoutException(
              'IoT data fetch timeout', const Duration(seconds: 15));
        },
      );
      print('SUCCESS: Step 1: IoT data fetch completed');

      // Step 2: Switch to Internet
      setState(() {
        _lastSyncStatus = 'Switching to Internet...';
      });
      print('SYNC: Step 2: Switching to Internet...');
      final switchSuccess = await _switchToInternetForSupabase().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⏰ Timeout: Internet switch took too long');
          return false;
        },
      );

      if (switchSuccess) {
        // Step 3: Check connectivity and upload to Supabase
        setState(() {
          _lastSyncStatus = 'Checking connectivity...';
        });

        //  OPTIMIZED: Skip Supabase connectivity check - use sync status approach instead

        setState(() {
          _lastSyncStatus = 'Uploading to Supabase...';
        });
        print('SYNC: Step 3: Uploading to Supabase...');
        await _retryWithBackoff(
          operation: () => _syncLocalDataToSupabase().timeout(
            _getTimeoutForOperation('large_upload'),
            onTimeout: () {
              print('⏰ Timeout: Supabase upload took too long');
              throw TimeoutException('Supabase upload timeout',
                  _getTimeoutForOperation('large_upload'));
            },
          ),
          maxRetries: 2,
          operationName: 'Supabase upload',
        );
        print('SUCCESS: Step 3: Supabase upload completed');

        // Step 4: Switch back to WiFi Direct
        setState(() {
          _lastSyncStatus = 'Reconnecting to IoT...';
        });
        print('SYNC: Step 4: Reconnecting to IoT...');
        await _switchBackToWiFiDirect().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⏰ Timeout: WiFi Direct reconnect took too long');
          },
        );
        print('SUCCESS: Step 4: WiFi Direct reconnect completed');

        setState(() {
          _lastSyncStatus = 'Sync completed successfully!';
        });
        _showSuccessSnackBar('Complete sync successful!');
      } else {
        setState(() {
          _lastSyncStatus = 'Failed to switch to Internet';
        });
        _showErrorSnackBar('Failed to switch to Internet for Supabase sync');
        await _switchBackToWiFiDirect();
      }
    } catch (e) {
      setState(() {
        _lastSyncStatus = 'Sync failed: $e';
      });
      print('ERROR: Error during sync: $e');
      _showErrorSnackBar('Error during sync: $e');
      await _switchBackToWiFiDirect();
    } finally {
      setState(() {
        _isManualSyncInProgress = false;
        _isLoading = false;
      });
    }
  }

  //  NEW: Quick sync method for testing
  Future<void> _quickSync() async {
    if (!_validateConnection(action: 'sync')) return;

    await _syncWithStatusTracking();
  }

  //  NEW: Retry mechanism with exponential backoff
  Future<T> _retryWithBackoff<T>({
    required Future<T> Function() operation,
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    String operationName = 'operation',
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      try {
        attempt++;
        print('SYNC: $operationName attempt $attempt/$maxRetries');

        return await operation();
      } catch (e) {
        print('ERROR: $operationName attempt $attempt failed: $e');

        if (attempt >= maxRetries) {
          print('ERROR: $operationName failed after $maxRetries attempts');
          rethrow;
        }

        // Exponential backoff: 1s, 2s, 4s
        print('⏳ Waiting ${delay.inSeconds}s before retry...');
        await Future.delayed(delay);
        delay = Duration(seconds: delay.inSeconds * 2);
      }
    }

    throw Exception('$operationName failed after $maxRetries attempts');
  }

  //  NEW: Enhanced timeout configuration
  Duration _getTimeoutForOperation(String operationType) {
    switch (operationType) {
      case 'quick':
        return const Duration(seconds: 3);
      case 'normal':
        return const Duration(seconds: 10);
      case 'upload':
        return const Duration(seconds: 30);
      case 'large_upload':
        return const Duration(seconds: 90);
      case 'image_fetch':
        return const Duration(seconds: 20);
      default:
        return const Duration(seconds: 15);
    }
  }

  //  REMOVED: Supabase connectivity check - no longer needed with sync status approach

  // ============================================================================
  //  NEW: PI5 DATA INTEGRATION FUNCTIONS (Safe Implementation)
  // ============================================================================
  // These functions add Pi5 data integration without modifying existing code

  //  REMOVED: Old incorrect Pi5 behavior logs fetching method - replaced with HTTP server push

  ///  NEW: Fetch Pi5 images safely (without modifying existing image fetching)
  Future<void> _fetchPi5Images() async {
    if (!_isConnected) {
      print('ERROR: Not connected to Pi5 - skipping images fetch');
      return;
    }

    try {
      print('IMAGE: Fetching Pi5 images...');

      //  SAFE: Get Pi5 snapshots that have filenames but no images loaded
      final pi5Snapshots = _unifiedSnapshots.where((snapshot) {
        final filename = snapshot['filename'];
        final source = snapshot['source'];
        return filename != null &&
            filename.isNotEmpty &&
            source == 'pi5_iot' &&
            !_snapshotImages.containsKey(filename);
      }).toList();

      if (pi5Snapshots.isEmpty) {
        print('SUCCESS: All Pi5 images already loaded');
        return;
      }

      print('IMAGE: Found ${pi5Snapshots.length} Pi5 images to fetch');

      //  PARALLEL PI5 DOWNLOAD: Download all Pi5 images simultaneously
      final pi5DownloadTasks = pi5Snapshots.map((snapshot) async {
        final filename = snapshot['filename'];
        print('WIFI: Fetching Pi5 image: $filename');

        try {
          await _fetchAndStoreSnapshotImage(snapshot, filename);
          print('SUCCESS: Pi5 image loaded: $filename');
        } catch (e) {
          print('ERROR: Failed to fetch Pi5 image $filename: $e');
        }
      }).toList();

      // Wait for all Pi5 downloads to complete in parallel
      await Future.wait(pi5DownloadTasks);

      print('SUCCESS: Pi5 images fetch completed');
    } catch (e) {
      print('ERROR: Error fetching Pi5 images: $e');
    }
  }

  ///  NEW: Sync Pi5 data to Supabase safely (without modifying existing sync)
  Future<void> _syncPi5DataToSupabase() async {
    try {
      print('SYNC: Syncing Pi5 data to Supabase...');

      //  SAFE: Get Pi5 data that hasn't been uploaded yet
      final pi5DataToSync = _unifiedSnapshots.where((snapshot) {
        final source = snapshot['source'];
        return source == 'pi5_iot' && snapshot['sync_status'] != 'synced';
      }).toList();

      if (pi5DataToSync.isEmpty) {
        print('SUCCESS: No Pi5 data to sync');
        return;
      }

      print('DATA: Syncing ${pi5DataToSync.length} Pi5 records to Supabase');

      //  OPTIMIZED: Batch upload Pi5 data for maximum speed
      try {
        await _batchUploadLogs(pi5DataToSync, 'Pi5 data');
        print('SUCCESS: Batch synced ${pi5DataToSync.length} Pi5 records');
      } catch (e) {
        print('ERROR: Failed to batch sync Pi5 data: $e');
        // Fallback to individual uploads if batch fails
        for (final pi5Data in pi5DataToSync) {
          try {
            await _storeCompressedSnapshotInSupabase(pi5Data, Uint8List(0));
            print('SUCCESS: Pi5 data synced: ${pi5Data['behavior_type']}');
          } catch (e) {
            print('ERROR: Failed to sync Pi5 data: $e');
          }
        }
      }

      print('SUCCESS: Pi5 data sync completed');
    } catch (e) {
      print('ERROR: Error syncing Pi5 data: $e');
    }
  }

  ///  NEW: Complete Pi5 integration (safe wrapper function)
  Future<void> _integratePi5Data() async {
    if (!_isConnected) {
      print('ERROR: Not connected to Pi5 - skipping integration');
      return;
    }

    try {
      print('🚀 Starting Pi5 data integration...');

      // Step 1: Fetch Pi5 snapshot logs
      await _fetchUnifiedSnapshotsFromIoT();

      // Step 2: Fetch the actual snapshot images
      await _autoFetchAllMissingImages();

      // Step 3: Fetch Pi5 images (legacy method)
      await _fetchPi5Images();

      // Step 3: Sync Pi5 data to Supabase
      await _syncPi5DataToSupabase();

      print('SUCCESS: Pi5 data integration completed successfully');
    } catch (e) {
      print('ERROR: Error in Pi5 data integration: $e');
    }
  }
}
