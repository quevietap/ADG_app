import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Beautiful and professional widget for rating drivers on completed trips
/// Shows trip details, driver info, activity logs, behavior logs, and snapshots
class CompletedTripRatingWidget extends StatefulWidget {
  final Map<String, dynamic> trip;
  final VoidCallback? onRatingSubmitted;

  const CompletedTripRatingWidget({
    super.key,
    required this.trip,
    this.onRatingSubmitted,
  });

  @override
  State<CompletedTripRatingWidget> createState() => _CompletedTripRatingWidgetState();
}

class _CompletedTripRatingWidgetState extends State<CompletedTripRatingWidget> {
  int _currentRating = 0;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingData = true;
  
  // Trip data
  Map<String, dynamic>? _driverData;
  Map<String, dynamic>? _subDriverData;
  List<Map<String, dynamic>> _activityLogs = [];
  List<Map<String, dynamic>> _behaviorLogs = [];
  List<Map<String, dynamic>> _snapshots = [];
  Map<String, dynamic>? _existingRating;

  @override
  void initState() {
    super.initState();
    _loadTripData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadTripData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      final tripId = widget.trip['id'];
      final driverId = widget.trip['driver_id'];
      final subDriverId = widget.trip['sub_driver_id'];

      // Load data in parallel with error handling
      final futures = await Future.wait([
        // Driver data
        if (driverId != null)
          Supabase.instance.client
              .from('users')
              .select('id, first_name, last_name, profile_image_url, driver_id')
              .eq('id', driverId)
              .maybeSingle()
              .catchError((e) {
                print('❌ Error loading driver data: $e');
                return null;
              }),
        
        // Sub-driver data
        if (subDriverId != null)
          Supabase.instance.client
              .from('users')
              .select('id, first_name, last_name, profile_image_url, driver_id')
              .eq('id', subDriverId)
              .maybeSingle()
              .catchError((e) {
                print('❌ Error loading sub-driver data: $e');
                return null;
              }),
        
        // Activity logs (session logs) - use created_at instead of timestamp
        Supabase.instance.client
            .from('session_logs')
            .select('*')
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .catchError((e) {
              print('❌ Error loading session logs: $e');
              return <Map<String, dynamic>>[];
            }),
        
        // Behavior logs (from unified snapshots table)
        Supabase.instance.client
            .from('snapshots')
            .select('*')
            .eq('trip_id', tripId)
            .eq('event_type', 'behavior')
            .order('timestamp', ascending: false)
            .catchError((e) {
              print('❌ Error loading behavior logs: $e');
              return <Map<String, dynamic>>[];
            }),
        
        // Snapshots (use snapshots table instead of driver_snapshots)
        Supabase.instance.client
            .from('snapshots')
            .select('*')
            .eq('trip_id', tripId)
            .order('timestamp', ascending: false)
            .catchError((e) {
              print('❌ Error loading snapshots: $e');
              return <Map<String, dynamic>>[];
            }),
        
        // Check for existing rating
        Supabase.instance.client
            .from('driver_ratings')
            .select('*')
            .eq('trip_id', tripId)
            .maybeSingle()
            .catchError((e) {
              print('❌ Error loading existing rating: $e');
              return null;
            }),
      ]);

      // Process results with null safety
      _driverData = futures[0] as Map<String, dynamic>?;
      _subDriverData = futures[1] as Map<String, dynamic>?;
      _activityLogs = List<Map<String, dynamic>>.from(futures[2] as List? ?? []);
      _behaviorLogs = List<Map<String, dynamic>>.from(futures[3] as List? ?? []);
      _snapshots = List<Map<String, dynamic>>.from(futures[4] as List? ?? []);
      _existingRating = futures[5] as Map<String, dynamic>?;

      // Set existing rating if found
      if (_existingRating != null) {
        _currentRating = (_existingRating!['rating'] as num).toInt();
        _commentController.text = _existingRating!['comment'] ?? '';
      }

    } catch (e) {
      print('❌ Error loading trip data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  Future<void> _submitRating() async {
    if (_currentRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating before submitting'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final tripId = widget.trip['id'];
      final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
      
      if (driverId == null) throw Exception('No driver found for this trip');

      final ratingData = {
        'driver_id': driverId,
        'rated_by': currentUser.id,
        'trip_id': tripId,
        'rating': _currentRating,
        'comment': _commentController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      };

      // Insert or update rating
      if (_existingRating != null) {
        await Supabase.instance.client
            .from('driver_ratings')
            .update(ratingData)
            .eq('id', _existingRating!['id']);
      } else {
        await Supabase.instance.client
            .from('driver_ratings')
            .insert(ratingData);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rating submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Call callback if provided
      widget.onRatingSubmitted?.call();

      // Close dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

    } catch (e) {
      print('❌ Error submitting rating: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting rating: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _formatDateTime(String? dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateTime);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  String _getBehaviorTypeDisplay(String behaviorType) {
    switch (behaviorType.toLowerCase()) {
      case 'drowsiness':
        return 'Drowsiness Detected';
      case 'distraction':
        return 'Distraction Detected';
      case 'phone_use':
        return 'Phone Use Detected';
      case 'looking_away':
        return 'Looking Away';
      default:
        return behaviorType.replaceAll('_', ' ').toUpperCase();
    }
  }

  Color _getBehaviorColor(String behaviorType) {
    switch (behaviorType.toLowerCase()) {
      case 'drowsiness':
        return Colors.orange;
      case 'distraction':
        return Colors.red;
      case 'phone_use':
        return Colors.purple;
      case 'looking_away':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 900),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Beautiful Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.star_rate_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rate Driver Performance',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Share your feedback for this trip',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Flexible(
              child: _isLoadingData
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading trip data...'),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTripInfoSection(),
                          const SizedBox(height: 24),
                          _buildDriverInfoSection(),
                          const SizedBox(height: 24),
                          _buildRatingSection(),
                          const SizedBox(height: 24),
                          _buildActivityLogsSection(),
                          const SizedBox(height: 24),
                          _buildBehaviorLogsSection(),
                          const SizedBox(height: 24),
                          _buildSnapshotsSection(),
                          const SizedBox(height: 32),
                          _buildSubmitButton(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.route, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Trip Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Trip ID', widget.trip['trip_ref_number'] ?? 'N/A'),
          _buildInfoRow('Origin', widget.trip['origin'] ?? 'N/A'),
          _buildInfoRow('Destination', widget.trip['destination'] ?? 'N/A'),
          _buildInfoRow('Date', _formatDateTime(widget.trip['start_time']?.toString())),
          _buildInfoRow('Status', widget.trip['status']?.toString().toUpperCase() ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildDriverInfoSection() {
    final mainDriver = _driverData;
    final subDriver = _subDriverData;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Driver Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (mainDriver != null) ...[
            _buildInfoRow('Main Driver', '${mainDriver['first_name']} ${mainDriver['last_name']}'),
            if (mainDriver['driver_id'] != null)
              _buildInfoRow('Driver ID', mainDriver['driver_id']),
          ],
          if (subDriver != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow('Sub Driver', '${subDriver['first_name']} ${subDriver['last_name']}'),
            if (subDriver['driver_id'] != null)
              _buildInfoRow('Sub Driver ID', subDriver['driver_id']),
          ],
          if (mainDriver == null && subDriver == null)
            _buildInfoRow('Driver', 'No driver information available'),
        ],
      ),
    );
  }

  Widget _buildRatingSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.star, color: Colors.amber, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Rate Driver Performance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Star Rating with improved interaction
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentRating = index + 1;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      index < _currentRating ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 48,
                      color: index < _currentRating ? Colors.amber : Colors.grey.shade400,
                    ),
                  ),
                );
              }),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Rating Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Poor', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              Text('Excellent', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Comment Field with better styling
          TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Additional Comments (Optional)',
              hintText: 'Share your experience with this driver...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityLogsSection() {
    if (_activityLogs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Activity Logs (${_activityLogs.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _activityLogs.length,
              itemBuilder: (context, index) {
                final log = _activityLogs[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(_getActivityIcon(log['event_type']), color: Colors.blue, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log['event_type']?.toString().replaceAll('_', ' ').toUpperCase() ?? 'Unknown Event',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            if (log['description'] != null)
                              Text(
                                log['description'],
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              ),
                            Text(
                              _formatDateTime(log['created_at']?.toString()),
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                            ),
                          ],
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

  Widget _buildBehaviorLogsSection() {
    if (_behaviorLogs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Behavior Logs (${_behaviorLogs.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _behaviorLogs.length,
              itemBuilder: (context, index) {
                final log = _behaviorLogs[index];
                final behaviorType = log['behavior_type']?.toString() ?? 'unknown';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getBehaviorColor(behaviorType).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getBehaviorColor(behaviorType).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning,
                        color: _getBehaviorColor(behaviorType),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getBehaviorTypeDisplay(behaviorType),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: _getBehaviorColor(behaviorType),
                              ),
                            ),
                            if (log['details'] != null)
                              Text(
                                log['details'].toString(),
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              ),
                            Text(
                              _formatDateTime(log['timestamp']?.toString()),
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                            ),
                          ],
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

  Widget _buildSnapshotsSection() {
    if (_snapshots.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.photo_camera, color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Snapshots (${_snapshots.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _snapshots.length,
              itemBuilder: (context, index) {
                final snapshot = _snapshots[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.image, color: Colors.grey, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Snapshot ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            if (snapshot['behavior_type'] != null)
                              Text(
                                'Type: ${snapshot['behavior_type']}',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              ),
                            Text(
                              _formatDateTime(snapshot['timestamp']?.toString()),
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                            ),
                          ],
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

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitRating,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          shadowColor: Theme.of(context).primaryColor.withOpacity(0.3),
        ),
        child: _isSubmitting
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Submitting...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              )
            : const Text(
                'Submit Rating',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getActivityIcon(String? eventType) {
    switch (eventType?.toLowerCase()) {
      case 'trip_started':
        return Icons.play_arrow;
      case 'trip_completed':
        return Icons.check_circle;
      case 'trip_confirmed':
        return Icons.verified;
      case 'trip_cancelled':
        return Icons.cancel;
      case 'location_update':
        return Icons.location_on;
      case 'status_change':
        return Icons.swap_horiz;
      case 'operator_action':
        return Icons.admin_panel_settings;
      default:
        return Icons.info;
    }
  }
}
