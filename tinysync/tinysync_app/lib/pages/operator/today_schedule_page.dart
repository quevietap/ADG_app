import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/enhanced_trip_card.dart';
import '../../services/trip_lifecycle_service.dart';

class TodaySchedulePage extends StatefulWidget {
  const TodaySchedulePage({super.key});

  @override
  State<TodaySchedulePage> createState() => _TodaySchedulePageState();
}

class _TodaySchedulePageState extends State<TodaySchedulePage> {
  List<Map<String, dynamic>> _todayTrips = [];
  List<Map<String, dynamic>> _scheduledTrips = [];
  bool _isLoading = true;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _autoTransferOutdatedTrips();
    _fetchData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when returning to this page
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Auto-transfer outdated trips to history
  Future<void> _autoTransferOutdatedTrips() async {
    try {
      print('🔄 Auto-transferring outdated trips...');
      final result = await TripLifecycleService().autoTransferOutdatedTrips();
      print('✅ Auto-transfer completed successfully');
    } catch (e) {
      print('❌ Error in auto-transfer: $e');
    }
  }

  Future<void> _fetchData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final today = DateTime.now();
      final todayStr = today.toIso8601String().split('T')[0];
      final tomorrowStr =
          today.add(const Duration(days: 1)).toIso8601String().split('T')[0];

      print('🔍 Fetching trips for date: $todayStr');
      print('🔍 Today: $todayStr, Tomorrow: $tomorrowStr');

      // First, let's try to fetch ALL trips to see what's in the database
      print('🔍 Fetching ALL trips first...');
      final allTripsResponse = await Supabase.instance.client
          .from('trips')
          .select('id, start_time, status, driver_id, created_at')
          .order('created_at', ascending: false)
          .limit(10);

      print('📊 ALL trips in database: ${(allTripsResponse as List).length}');
      for (var trip in allTripsResponse) {
        print(
            '   Trip ${trip['id']}: start_time=${trip['start_time']}, status=${trip['status']}, created_at=${trip['created_at']}');
      }

      // 1. Fetch trips - try multiple approaches
      List<dynamic> tripsResponse = [];

      // Approach 1: Try with start_time date range
      try {
        tripsResponse = await Supabase.instance.client
            .from('trips')
            .select(
                '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*)')
            .gte('start_time', todayStr)
            .lt('start_time', tomorrowStr);
        print('📊 Trips found with start_time filter: ${tripsResponse.length}');
      } catch (e) {
        print('❌ Error with start_time filter: $e');
      }

      // Approach 2: If no trips found, try with created_at
      if (tripsResponse.isEmpty) {
        try {
          tripsResponse = await Supabase.instance.client
              .from('trips')
              .select(
                  '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*)')
              .gte('created_at', todayStr)
              .lt('created_at', tomorrowStr);
          print(
              '📊 Trips found with created_at filter: ${tripsResponse.length}');
        } catch (e) {
          print('❌ Error with created_at filter: $e');
        }
      }

      // Approach 3: If still no trips, get recent trips regardless of date
      if (tripsResponse.isEmpty) {
        try {
          tripsResponse = await Supabase.instance.client
              .from('trips')
              .select(
                  '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*)')
              .order('created_at', ascending: false)
              .limit(20);
          print('📊 Recent trips found (any date): ${tripsResponse.length}');
        } catch (e) {
          print('❌ Error fetching recent trips: $e');
        }
      }

      // 2. Fetch scheduled trips for today
      final schedulesResponse = await Supabase.instance.client
          .from('schedules')
          .select(
              '*, trips(*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*))')
          .eq('schedule_date', todayStr)
          .order('schedule_date', ascending: true);

      print('📊 Raw trips fetched: ${tripsResponse.length}');
      print('📊 Raw schedules fetched: ${(schedulesResponse as List).length}');

      // Filter trips: only show assigned trips (with drivers) scheduled for today, exclude canceled/deleted/completed/archived
      final filteredTrips = tripsResponse.where((trip) {
        final status = trip['status']?.toString().toLowerCase() ?? '';
        final driverId = trip['driver_id'];
        final subDriverId = trip['sub_driver_id'];
        final hasMainDriver =
            driverId != null && driverId.toString().isNotEmpty;
        final hasSubDriver =
            subDriverId != null && subDriverId.toString().isNotEmpty;
        final hasAnyDriver = hasMainDriver || hasSubDriver;

        print(
            'Trip ${trip['id']} has status: $status, driver_id: $driverId, sub_driver_id: $subDriverId, hasAnyDriver: $hasAnyDriver');

        // Only show trips that have any driver assigned and are not in excluded statuses
        return hasAnyDriver &&
            status != 'canceled' &&
            status != 'cancelled' &&
            status != 'deleted' &&
            status !=
                'completed' && // Exclude completed trips from Today's Schedule
            status !=
                'archived'; // Exclude archived trips from Today's Schedule
      }).toList();

      final filteredSchedules = (schedulesResponse).where((schedule) {
        final trip = schedule['trips'];
        if (trip == null) return false; // Skip schedules without trips

        final status = trip['status']?.toString().toLowerCase() ?? '';
        final driverId = trip['driver_id'];
        final subDriverId = trip['sub_driver_id'];
        final hasMainDriver =
            driverId != null && driverId.toString().isNotEmpty;
        final hasSubDriver =
            subDriverId != null && subDriverId.toString().isNotEmpty;
        final hasAnyDriver = hasMainDriver || hasSubDriver;

        print(
            'Scheduled trip ${trip['id']} has status: $status, driver_id: $driverId, sub_driver_id: $subDriverId, hasAnyDriver: $hasAnyDriver');

        // Only show scheduled trips that have any driver assigned and are not in excluded statuses
        return hasAnyDriver &&
            status != 'canceled' &&
            status != 'cancelled' &&
            status != 'deleted' &&
            status !=
                'completed' && // Exclude completed trips from Today's Schedule
            status !=
                'archived'; // Exclude archived trips from Today's Schedule
      }).toList();

      // Fetch vehicle details for filtered trips
      final tripsWithVehicles =
          await Future.wait(filteredTrips.map((trip) async {
        if (trip['vehicle_id'] != null) {
          try {
            final vehicleResponse = await Supabase.instance.client
                .from('vehicles')
                .select('plate_number, make, model, capacity_kg')
                .eq('id', trip['vehicle_id'])
                .single();
            trip['vehicle_details'] = vehicleResponse;
          } catch (e) {
            debugPrint('Error fetching vehicle details: $e');
            trip['vehicle_details'] = null;
          }
        }
        return trip;
      }));

      // Fetch vehicle details for scheduled trips
      final schedulesWithVehicles =
          await Future.wait(filteredSchedules.map((schedule) async {
        final trip = schedule['trips'];
        if (trip != null && trip['vehicle_id'] != null) {
          try {
            final vehicleResponse = await Supabase.instance.client
                .from('vehicles')
                .select('plate_number, make, model, capacity_kg')
                .eq('id', trip['vehicle_id'])
                .single();
            trip['vehicle_details'] = vehicleResponse;
          } catch (e) {
            debugPrint('Error fetching vehicle details: $e');
            trip['vehicle_details'] = null;
          }
        }
        return schedule;
      }));

      print('✅ Filtered trips count: ${tripsWithVehicles.length}');
      print('✅ Filtered schedules count: ${schedulesWithVehicles.length}');

      if (mounted) {
        setState(() {
          _todayTrips = List<Map<String, dynamic>>.from(tripsWithVehicles);
          _scheduledTrips =
              List<Map<String, dynamic>>.from(schedulesWithVehicles);
        });
      }
    } catch (e) {
      print('❌ Error fetching data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to fetch today\'s trips: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Add shared date/time formatting functions
  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(DateTime? date) {
    if (date == null) return 'N/A';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} $ampm';
  }

  String _formatTripId(Map<String, dynamic> trip) {
    // If there's a trip_ref_number, use it (show full reference)
    if (trip['trip_ref_number'] != null &&
        trip['trip_ref_number'].toString().isNotEmpty) {
      return trip['trip_ref_number'].toString();
    }

    // Otherwise, create a formatted ID from the database ID (show full ID)
    final id = trip['id'];
    if (id != null) {
      return 'Trip $id';
    }

    return 'Trip Unknown';
  }

  @override
  Widget build(BuildContext context) {
    // Deduplicate trips by id
    final Map<dynamic, Map<String, dynamic>> uniqueTrips = {};
    for (final trip in _todayTrips) {
      final id = trip['id'] ?? trip['trip_ref_number'];
      if (id != null) uniqueTrips[id] = trip;
    }
    for (final schedule in _scheduledTrips) {
      final trip = schedule['trips'];
      if (trip != null) {
        final id = trip['id'] ?? trip['trip_ref_number'];
        if (id != null) uniqueTrips[id] = trip;
      }
    }
    final List<Map<String, dynamic>> dedupedTrips = uniqueTrips.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed header
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            "Today's Schedule",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),

        // Notifications moved to History → Session tab

        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
                if (_errorMessage != null)
                  Center(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (!_isLoading &&
                    _errorMessage == null &&
                    dedupedTrips.isEmpty)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.event_busy,
                            size: 60,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'No Trips Scheduled',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No trips are scheduled for today. Previous day trips have been moved to History → Sessions.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.blue, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Check History → Sessions for previous day trips',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_isLoading &&
                    _errorMessage == null &&
                    dedupedTrips.isNotEmpty)
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: dedupedTrips.length,
                    itemBuilder: (context, index) {
                      final trip = dedupedTrips[index];
                      return _buildTripCard(trip, index, isToday: true);
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTripCard(Map<String, dynamic>? trip, int cardIndex,
      {bool isFromSchedule = false, bool isToday = false}) {
    if (trip == null) return const SizedBox.shrink();

    // Use the enhanced trip card with real-time tracking
    return EnhancedTripCard(
      trip: trip,
      cardIndex: cardIndex,
      isFromSchedule: isFromSchedule,
      isToday: isToday,
      showRealTimeTracking: true, // Enable GPS tracking
      isDriver: false, // This is operator view
      isOperator: true, // This is operator view
      userData: null, // TODO: Pass userData when available
      onTripUpdated: () {
        // Refresh data when trip is updated
        _fetchData();
      },
      onAssignDriver: null, // Assignment methods not available in dashboard
      onAssignVehicle: null, // Assignment methods not available in dashboard
      onCancel: (trip, reason) async {
        print(
            '🔶 TODAY_SCHEDULE: Cancel callback received - Trip ID: ${trip['id']}, Reason: "$reason"');
        await _cancelTrip(trip, reason);
      },
      onDelete: (trip, reason) async {
        print(
            '🔴 TODAY_SCHEDULE: Delete callback received - Trip ID: ${trip['id']}, Reason: "$reason"');
        await _deleteTrip(trip, reason);
      },
    );
  }

  // Cancel trip method
  Future<void> _cancelTrip(Map<String, dynamic> trip, String reason) async {
    try {
      print(
          '🔶 TODAY_SCHEDULE: Cancelling trip ${trip['id']} with reason: "$reason"');

      final cancelledAt = DateTime.now();
      final formattedReason =
          reason.isNotEmpty ? reason : 'Trip cancelled from Today\'s Schedule';

      await Supabase.instance.client.from('trips').update({
        'status': 'cancelled',
        'canceled_at': cancelledAt.toIso8601String(),
        'notes':
            'CANCELLED: $formattedReason (${cancelledAt.toIso8601String()})',
      }).eq('id', trip['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip cancelled successfully'),
            backgroundColor: Colors.orange,
          ),
        );
        _fetchData(); // Refresh the data
      }
    } catch (e) {
      print('❌ Error cancelling trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling trip: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Delete trip method
  Future<void> _deleteTrip(Map<String, dynamic> trip, String reason) async {
    try {
      print(
          '🔴 TODAY_SCHEDULE: Deleting trip ${trip['id']} with reason: "$reason"');

      final deletedAt = DateTime.now();
      final formattedReason =
          reason.isNotEmpty ? reason : 'Trip deleted from Today\'s Schedule';

      await Supabase.instance.client.from('trips').update({
        'status': 'deleted',
        'deleted_at': deletedAt.toIso8601String(),
        'notes': 'DELETED: $formattedReason (${deletedAt.toIso8601String()})',
      }).eq('id', trip['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip deleted successfully'),
            backgroundColor: Colors.red,
          ),
        );
        _fetchData(); // Refresh the data
      }
    } catch (e) {
      print('❌ Error deleting trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting trip: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
