import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

class ViewLogsModal extends StatefulWidget {
  final Map<String, dynamic> trip;

  const ViewLogsModal({
    super.key,
    required this.trip,
  });

  @override
  State<ViewLogsModal> createState() => _ViewLogsModalState();
}

class _ViewLogsModalState extends State<ViewLogsModal>
    with TickerProviderStateMixin {
  late TabController _tabController;
  RealtimeChannel? _snapshotsChannel;

  List<Map<String, dynamic>> _behaviorLogs = [];
  List<Map<String, dynamic>> _snapshots = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLogs();
    _setupRealTimeSubscriptions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _snapshotsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tripId = widget.trip['id'];
      final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];

      // Load all data from snapshots table (contains both behavior logs and images)
      // Filter by both trip_id and driver_id to ensure driver only sees their own records
      final snapshotsResponse = await Supabase.instance.client
          .from('snapshots')
          .select('*')
          .eq('trip_id', tripId)
          .eq('driver_id', driverId)
          .order('timestamp', ascending: false);

      // Separate behavior logs and snapshots based on data type
      List<Map<String, dynamic>> behaviorLogs = [];
      List<Map<String, dynamic>> snapshots = [];

      for (var record in snapshotsResponse) {
        // If it has image_data AND it's not empty, it's a snapshot with an image
        if (record['image_data'] != null &&
            record['image_data'].toString().trim().isNotEmpty) {
          snapshots.add(record);
        }

        // If it has behavior_type, it's a behavior log (regardless of image_data)
        // This allows drowsiness alerts to appear in BOTH tabs
        if (record['behavior_type'] != null) {
          behaviorLogs.add(record);
        }
      }

      setState(() {
        _behaviorLogs = behaviorLogs;
        _snapshots = snapshots;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading logs: $e';
        _isLoading = false;
      });
    }
  }

  void _setupRealTimeSubscriptions() {
    try {
      final tripId = widget.trip['id'];
      final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];

      // Subscribe to snapshots table updates (contains both behavior logs and images)
      // Filter by both trip_id and driver_id to ensure driver only sees their own records
      _snapshotsChannel = Supabase.instance.client
          .channel('snapshots_${tripId}_$driverId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'snapshots',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'trip_id',
              value: tripId,
            ),
            callback: (payload) {
              // Reload logs when new data arrives
              _loadLogs();
            },
          )
          .subscribe();
    } catch (e) {
      print('❌ Error setting up real-time subscriptions: $e');
    }
  }

  String _formatTripId(Map<String, dynamic> trip) {
    // Use trip_ref_number (like TRIP-20250906-005) instead of database ID
    return trip['trip_ref_number'] ?? 'Trip #${trip['id'] ?? ''}';
  }

  String _getDriverName() {
    final driver = widget.trip['users'] ?? widget.trip['sub_driver'];
    if (driver != null) {
      final firstName = driver['first_name'] ?? '';
      final lastName = driver['last_name'] ?? '';
      return '$firstName $lastName'.trim();
    }
    return 'Unknown Driver';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E1E1E),
              Color(0xFF0A0A0A),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Enhanced Header with Beautiful Gradient (matching Assign Driver)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor.withOpacity(0.2),
                        Theme.of(context).primaryColor.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).primaryColor.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Enhanced Icon with Animation
                      Hero(
                        tag: 'view_logs_icon',
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).primaryColor,
                                Theme.of(context).primaryColor.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context)
                                    .primaryColor
                                    .withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.visibility_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Enhanced Title Section
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'View Logs',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Monitor trip behavior and snapshots',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Trip Info with enhanced styling - vertical layout
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Trip ID row
                      Row(
                        children: [
                          Icon(
                            Icons.local_shipping_rounded,
                            color: Theme.of(context).primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _formatTripId(widget.trip),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Driver label below trip ID
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          'Driver: ${_getDriverName()}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Enhanced Tab Bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorPadding: const EdgeInsets.all(4),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.psychology_rounded, size: 18),
                        text: 'Behavior Logs',
                      ),
                      Tab(
                        icon: Icon(Icons.photo_camera_rounded, size: 18),
                        text: 'Snapshots',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Behavior Logs Tab
                      _buildBehaviorLogsTab(),

                      // Snapshots Tab
                      _buildSnapshotsTab(),
                    ],
                  ),
                ),
              ],
            ),
            // Close button positioned absolutely in the top-right corner
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBehaviorLogsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_behaviorLogs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology, color: Colors.grey, size: 48),
            SizedBox(height: 16),
            Text(
              'No behavior logs available',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _behaviorLogs.length,
      itemBuilder: (context, index) {
        final log = _behaviorLogs[index];
        final behaviorType = log['behavior_type'] ?? 'Unknown Behavior';
        final timestamp = log['timestamp'];
        final filename = log['filename'] ?? 'No filename';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.psychology,
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      behaviorType,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    _formatTimestamp(timestamp),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'File: $filename',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSnapshotsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_snapshots.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera, color: Colors.grey, size: 48),
            SizedBox(height: 16),
            Text(
              'No snapshots available',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: _snapshots.length,
      itemBuilder: (context, index) {
        final snapshot = _snapshots[index];
        final imageData = snapshot['image_data'];
        final behaviorType = snapshot['behavior_type'] ?? 'Unknown';
        final timestamp = snapshot['timestamp'];

        return GestureDetector(
          onTap: () => _showSnapshotDetails(snapshot),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: imageData != null
                        ? ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                            child: FutureBuilder<Uint8List?>(
                              future: _convertImageData(imageData),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  );
                                }

                                final imageBytes = snapshot.data;
                                if (imageBytes != null) {
                                  return Image.memory(
                                    imageBytes,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                        child: Icon(
                                          Icons.photo_camera,
                                          color: Colors.grey,
                                          size: 48,
                                        ),
                                      );
                                    },
                                  );
                                } else {
                                  return const Center(
                                    child: Icon(
                                      Icons.photo_camera,
                                      color: Colors.grey,
                                      size: 48,
                                    ),
                                  );
                                }
                              },
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.photo_camera,
                              color: Colors.grey,
                              size: 48,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Text(
                        behaviorType,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatTimestamp(timestamp),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      final dateTime = DateTime.parse(timestamp.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid Date';
    }
  }

  Future<Uint8List?> _convertImageData(dynamic imageData) async {
    if (imageData == null) return null;

    try {
      // Handle base64 string (from Supabase text field)
      if (imageData is String && imageData.isNotEmpty) {
        return base64.decode(imageData);
      }

      // Handle List<int> directly
      if (imageData is List<int>) {
        return Uint8List.fromList(imageData);
      }

      // Handle List (cast to int)
      if (imageData is List) {
        try {
          final intList = imageData.cast<int>();
          return Uint8List.fromList(intList);
        } catch (e) {
          print('Failed to convert image data: $e');
          return null;
        }
      }

      print('Unsupported image data type: ${imageData.runtimeType}');
      return null;
    } catch (e) {
      print('Error converting image data: $e');
      return null;
    }
  }

  // ✅ NEW: Show detailed snapshot popup with all analytical data
  void _showSnapshotDetails(Map<String, dynamic> snapshot) {
    final filename = snapshot['filename'] ?? 'Unknown';
    final behaviorType = snapshot['behavior_type'] ?? 'Unknown';
    final timestamp = snapshot['timestamp'] ?? DateTime.now().toIso8601String();
    final imageData = snapshot['image_data'];

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
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.8,
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E1E1E),
                  Color(0xFF0A0A0A),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: eventColor.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            eventColor.withOpacity(0.2),
                            eventColor.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: eventColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              eventIcon,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  behaviorType
                                      .replaceAll('_', ' ')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$dateDisplay at $timeDisplay',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Fixed content - Image and Analytical Data header
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Image - Fixed
                          if (imageData != null) ...[
                            Container(
                              width: double.infinity,
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: FutureBuilder<Uint8List?>(
                                  future: _convertImageData(imageData),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      );
                                    }

                                    final imageBytes = snapshot.data;
                                    if (imageBytes != null) {
                                      return Image.memory(
                                        imageBytes,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return const Center(
                                            child: Icon(
                                              Icons.photo_camera,
                                              color: Colors.grey,
                                              size: 48,
                                            ),
                                          );
                                        },
                                      );
                                    } else {
                                      return const Center(
                                        child: Icon(
                                          Icons.photo_camera,
                                          color: Colors.grey,
                                          size: 48,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Analytical Data header - Fixed
                          Text(
                            'Analytical Data',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: eventColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),

                    // Scrollable content - Only data fields
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          children: [
                            _buildDataField('Filename', filename),
                            _buildDataField(
                                'Confidence Score',
                                snapshot['confidence_score']?.toString() ??
                                    'N/A'),
                            _buildDataField(
                                'Evidence Reason',
                                snapshot['evidence_reason']?.toString() ??
                                    'N/A'),
                            _buildDataField(
                                'Event Duration',
                                snapshot['event_duration']?.toString() ??
                                    'N/A'),
                            _buildDataField('Gaze Pattern',
                                snapshot['gaze_pattern']?.toString() ?? 'N/A'),
                            _buildDataField(
                                'Face Direction',
                                snapshot['face_direction']?.toString() ??
                                    'N/A'),
                            _buildDataField('Eye State',
                                snapshot['eye_state']?.toString() ?? 'N/A'),
                            _buildDataField('Driver Type',
                                snapshot['driver_type']?.toString() ?? 'N/A'),
                            _buildDataField('Device ID',
                                snapshot['device_id']?.toString() ?? 'N/A'),
                            _buildDataField('Source',
                                snapshot['source']?.toString() ?? 'N/A'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Close button
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ✅ NEW: Helper method to build data field rows
  Widget _buildDataField(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
