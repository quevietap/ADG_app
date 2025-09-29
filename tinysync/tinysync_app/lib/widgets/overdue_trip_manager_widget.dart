import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'overdue_trip_action_dialog.dart';
import 'dart:async';

/// Widget for displaying and managing overdue trips for operators
class OverdueTripManagerWidget extends StatefulWidget {
  const OverdueTripManagerWidget({super.key});

  @override
  State<OverdueTripManagerWidget> createState() =>
      _OverdueTripManagerWidgetState();
}

class _OverdueTripManagerWidgetState extends State<OverdueTripManagerWidget> {
  List<Map<String, dynamic>> _overdueTrips = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  RealtimeChannel? _tripChannel;

  @override
  void initState() {
    super.initState();
    _loadOverdueTrips();
    _setupRealtimeSubscription();

    // Refresh every 2 minutes
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _loadOverdueTrips();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tripChannel?.unsubscribe();
    super.dispose();
  }

  /// Set up real-time subscription for trip updates
  void _setupRealtimeSubscription() {
    _tripChannel = Supabase.instance.client
        .channel('overdue_trips_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'trips',
          callback: (payload) {
            print('🔄 Trip update detected, refreshing overdue list');
            _loadOverdueTrips();
          },
        )
        .subscribe();
  }

  /// Load overdue trips from database
  Future<void> _loadOverdueTrips() async {
    try {
      final now = DateTime.now();

      // Get trips that should have started but haven't
      final overdueStartsResponse = await Supabase.instance.client
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
            created_at,
            driver:users!trips_driver_id_fkey(id, first_name, last_name, phone)
          ''')
          .eq('status', 'assigned')
          .lt('start_time', now.toIso8601String())
          .order('start_time');

      // Get trips that should have completed but haven't
      final overdueCompletionsResponse = await Supabase.instance.client
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
            created_at,
            driver:users!trips_driver_id_fkey(id, first_name, last_name, phone)
          ''')
          .eq('status', 'in_progress')
          .lt('end_time', now.toIso8601String())
          .order('end_time');

      final List<Map<String, dynamic>> allOverdueTrips = [];

      // Process overdue starts
      for (final trip in overdueStartsResponse) {
        final startTime = DateTime.parse(trip['start_time']);
        final minutesOverdue = now.difference(startTime).inMinutes;

        if (minutesOverdue >= 10) {
          // Only show if 10+ minutes overdue
          allOverdueTrips.add({
            ...trip,
            'overdue_type': 'not_started',
            'minutes_overdue': minutesOverdue,
            'overdue_severity': _getOverdueSeverity(minutesOverdue),
          });
        }
      }

      // Process overdue completions
      for (final trip in overdueCompletionsResponse) {
        final endTime = DateTime.parse(trip['end_time']);
        final minutesOverdue = now.difference(endTime).inMinutes;

        if (minutesOverdue >= 15) {
          // Only show if 15+ minutes overdue
          allOverdueTrips.add({
            ...trip,
            'overdue_type': 'not_completed',
            'minutes_overdue': minutesOverdue,
            'overdue_severity': _getOverdueSeverity(minutesOverdue),
          });
        }
      }

      // Sort by severity and minutes overdue
      allOverdueTrips.sort((a, b) {
        final severityA = a['overdue_severity'] as int;
        final severityB = b['overdue_severity'] as int;
        if (severityA != severityB) {
          return severityB.compareTo(severityA); // Higher severity first
        }
        return (b['minutes_overdue'] as int)
            .compareTo(a['minutes_overdue'] as int);
      });

      if (mounted) {
        setState(() {
          _overdueTrips = allOverdueTrips;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading overdue trips: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Get overdue severity level (1=low, 2=medium, 3=high, 4=critical)
  int _getOverdueSeverity(int minutesOverdue) {
    if (minutesOverdue >= 120) return 4; // Critical: 2+ hours
    if (minutesOverdue >= 60) return 3; // High: 1+ hour
    if (minutesOverdue >= 30) return 2; // Medium: 30+ minutes
    return 1; // Low: 10-29 minutes
  }

  /// Get color for overdue severity
  Color _getSeverityColor(int severity) {
    switch (severity) {
      case 4:
        return Colors.red.shade800; // Critical
      case 3:
        return Colors.red.shade600; // High
      case 2:
        return Colors.orange.shade600; // Medium
      case 1:
        return Colors.yellow.shade700; // Low
      default:
        return Colors.grey;
    }
  }

  /// Get icon for overdue type
  IconData _getOverdueIcon(String overdueType) {
    return overdueType == 'not_started'
        ? Icons.play_circle_outline
        : Icons.flag_outlined;
  }

  /// Show trip details and actions
  void _showTripActions(Map<String, dynamic> trip) {
    showDialog(
      context: context,
      builder: (context) => OverdueTripActionDialog(
        trip: trip,
        onActionTaken: () {
          _loadOverdueTrips(); // Refresh list
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
                    '🚨 Overdue Trips',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '${_overdueTrips.length} trips',
                        style: TextStyle(
                          color:
                              _overdueTrips.isEmpty ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _loadOverdueTrips,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        tooltip: 'Refresh overdue trips',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_overdueTrips.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green, width: 1),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No overdue trips! All trips are on schedule.',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: _overdueTrips
                      .map((trip) => _buildOverdueTripCard(trip))
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build individual overdue trip card
  Widget _buildOverdueTripCard(Map<String, dynamic> trip) {
    final driver = trip['users'];
    final driverName = '${driver['first_name']} ${driver['last_name']}';
    final severity = trip['overdue_severity'] as int;
    final severityColor = _getSeverityColor(severity);
    final overdueType = trip['overdue_type'] as String;
    final minutesOverdue = trip['minutes_overdue'] as int;

    final severityText = ['', 'Low', 'Medium', 'High', 'CRITICAL'][severity];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Colors.grey[900],
        child: InkWell(
          onTap: () => _showTripActions(trip),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: severityColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        severityText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _getOverdueIcon(overdueType),
                      color: severityColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trip['trip_ref_number'] ?? 'Unknown Trip',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '$minutesOverdue min overdue',
                      style: TextStyle(
                        color: severityColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Trip details
                Text(
                  '$driverName • ${trip['origin']} → ${trip['destination']}',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 4),

                // Status description
                Text(
                  overdueType == 'not_started'
                      ? 'Trip should have started but driver hasn\'t clicked "Start Trip"'
                      : 'Trip should have been completed but is still in progress',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 8),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showTripActions(trip),
                      icon: const Icon(Icons.build, size: 16),
                      label: const Text('Actions'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _callDriver(driver['phone']),
                      icon: const Icon(Icons.phone, size: 16),
                      label: const Text('Call'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Call driver (placeholder - would integrate with phone dialer)
  void _callDriver(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number available for this driver'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // In a real app, this would use url_launcher to open the phone dialer
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Would call: $phoneNumber'),
        backgroundColor: Colors.blue,
      ),
    );
  }
}
